package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Cihaz anahtariyla yeniden oturum (QA 2026-10-13 R3 madde 3).
 *
 * Kaybolan rotasyon sonrasi olu refresh token + hesabin Ed25519 imzasi yeni
 * token cifti verir; logout/kurtarma sonrasi, yanlis anahtarla ya da
 * yeniden kullanilan soruyla vermez.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class DeviceReauthIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16")
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine")).withExposedPorts(6379)

    private data class Account(val userId: String, val key: KeyPair)

    @BeforeAll fun setup() {
        Assumptions.assumeTrue(DockerClientFactory.instance().isDockerAvailable)
        postgres.start(); redis.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), null)
    }

    @AfterAll fun cleanup() {
        runCatching { Database.close() }; runCatching { RedisManager.close() }
        postgres.stop(); redis.stop()
    }

    private fun account(): Account {
        val userId = UUID.randomUUID().toString()
        val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "INSERT INTO users(user_id, directory_token, signing_public_key) VALUES (?::uuid, ?, ?)",
            ).use {
                it.setString(1, userId); it.setString(2, "pending:$userId"); it.setBytes(3, pub(pair)); it.executeUpdate()
            }
        }
        return Account(userId, pair)
    }

    // JDK Ed25519 X.509/SPKI ciktisi verir; ham 32 bayt icin 12 baytlik oneki soy.
    private fun pub(pair: KeyPair): ByteArray = pair.public.encoded.copyOfRange(12, 44)

    private fun sign(pair: KeyPair, message: String): String = Base64.getEncoder().encodeToString(
        Signature.getInstance("Ed25519").run { initSign(pair.private); update(message.toByteArray(Charsets.UTF_8)); sign() },
    )

    /** Rotasyon yapilir ama yanit "kaybolur": eldeki token artik eski kusak. */
    private fun lostRotation(account: Account): String {
        val stale = AuthService.issueRefreshToken(account.userId)
        val claims = AuthService.refreshClaims(stale)!!
        assertNotNull(CredentialState.rotateRefreshGeneration(account.userId, claims.refreshGeneration))
        // Telafi penceresini de tuket: tek kurtulus yolu cihaz anahtari.
        CredentialState.redeemLostRotation(account.userId, claims.refreshGeneration)
        assertNull(CredentialState.rotateRefreshGeneration(account.userId, claims.refreshGeneration))
        return stale
    }

    private fun request(account: Account, refreshToken: String, key: KeyPair = account.key): DeviceReauthRequest {
        val challenge = DeviceReauth.issueChallenge()!!
        val preimage = DeviceReauth.preimage(challenge.challengeId, challenge.nonce, account.userId, refreshToken)
        return DeviceReauthRequest(challenge.challengeId, refreshToken, sign(key, preimage))
    }

    @Test fun `a dead refresh token plus the device signature restores the session`() {
        val account = account()
        val stale = lostRotation(account)

        val outcome = DeviceReauth.reauthenticate(request(account, stale))

        assertTrue(outcome is DeviceReauth.Outcome.Issued)
        val issued = outcome as DeviceReauth.Outcome.Issued
        assertEquals(account.userId, issued.userId)
        // Yeni token normal yenileme yolunda gecerli.
        val fresh = AuthService.issueRefreshToken(account.userId, issued.snapshot.credentialEpoch, issued.snapshot.refreshGeneration)
        val claims = AuthService.refreshClaims(fresh)!!
        assertNotNull(CredentialState.rotateRefreshGeneration(account.userId, claims.refreshGeneration))
    }

    @Test fun `another key cannot restore the session`() {
        val account = account()
        val stale = lostRotation(account)
        val stranger = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()

        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(request(account, stale, stranger)))
    }

    @Test fun `a challenge is single use even after a failed attempt`() {
        val account = account()
        val stale = lostRotation(account)
        val good = request(account, stale)
        val bad = good.copy(signature = Base64.getEncoder().encodeToString(ByteArray(64)))

        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(bad))
        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(good))
    }

    @Test fun `logout closes the device path`() {
        val account = account()
        val stale = lostRotation(account)
        assertTrue(AuthService.revokeAllTokens(account.userId))

        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(request(account, stale)))
    }

    @Test fun `the signature is bound to the presented refresh token`() {
        val account = account()
        val stale = lostRotation(account)
        val other = AuthService.issueRefreshToken(account.userId)
        val signedForOther = request(account, other)

        assertEquals(
            DeviceReauth.Outcome.Rejected,
            DeviceReauth.reauthenticate(signedForOther.copy(refreshToken = stale)),
        )
    }

    @Test fun `an account without a signing key cannot use the device path`() {
        val userId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.prepareStatement("INSERT INTO users(user_id, directory_token) VALUES (?::uuid, ?)").use {
                it.setString(1, userId); it.setString(2, "pending:$userId"); it.executeUpdate()
            }
        }
        val account = Account(userId, KeyPairGenerator.getInstance("Ed25519").generateKeyPair())

        assertEquals(
            DeviceReauth.Outcome.Rejected,
            DeviceReauth.reauthenticate(request(account, AuthService.issueRefreshToken(userId))),
        )
    }

    @Test fun `unknown and malformed challenges are rejected`() {
        val account = account()
        val stale = lostRotation(account)
        val valid = request(account, stale)

        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(valid.copy(challengeId = RecoveryRecordCipher.opaque())))
        assertEquals(DeviceReauth.Outcome.Rejected, DeviceReauth.reauthenticate(valid.copy(challengeId = "kisa")))
    }
}
