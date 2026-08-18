package com.securechat.signaling

import com.securechat.signaling.db.Database
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Credential iptalinin kalici oldugunu kanitlar.
 *
 * Onceki tasarimda logout/revocation yalniz persistence'siz ve `allkeys-lru`
 * calisan Redis'teydi; restart veya eviction iptal edilmis bir token'i
 * yeniden gecerli hale getiriyordu. Buradaki senaryolarda process RAM'i
 * bilerek bosaltilir (`clearCache`) — bu bir yeniden baslatmanin auth
 * katmanindaki karsiligidir — ve karar yine ayni kalmalidir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class DurableCredentialStateIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_credentials_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; durable credential integration testi atlandi",
        )
        postgres.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password)
            .use { connection ->
                connection.autoCommit = true
                for (version in 1..LAST_MIGRATION) {
                    val migration = Files.list(migrationDir).use { paths ->
                        paths.filter { it.fileName.toString().startsWith("V${version}__") }
                            .findFirst()
                            .orElseThrow()
                    }
                    connection.createStatement().use { it.execute(Files.readString(migration)) }
                }
            }
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        postgres.stop()
    }

    private fun newAccount(): String {
        val userId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "INSERT INTO users(user_id, directory_token) VALUES (?::uuid, ?)",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setString(2, "service:test-${UUID.randomUUID()}")
                statement.executeUpdate()
            }
        }
        CredentialState.clearCache()
        return userId
    }

    /** Yeniden baslatma: surecte tutulan hicbir kopya hayatta kalmaz. */
    private fun restartProcess() = CredentialState.clearCache()

    @Test
    fun `a fresh account can authenticate`() {
        val userId = newAccount()
        val token = AuthService.issueToken(userId)
        restartProcess()
        assertEquals(userId, AuthService.verifyToken(token))
    }

    @Test
    fun `logout survives a restart instead of resurrecting the token`() {
        val userId = newAccount()
        val access = AuthService.issueToken(userId)
        val refresh = AuthService.issueRefreshToken(userId)

        assertTrue(AuthService.revokeAllTokens(userId))
        restartProcess()

        assertNull(AuthService.verifyToken(access))
        assertNull(AuthService.refreshClaims(refresh))
    }

    @Test
    fun `a deleted account cannot refresh into new tokens after a restart`() {
        val userId = newAccount()
        val access = AuthService.issueToken(userId)
        val refresh = AuthService.issueRefreshToken(userId)

        Database.getConnection().use { connection ->
            connection.prepareStatement("DELETE FROM users WHERE user_id = ?::uuid")
                .use { statement ->
                    statement.setString(1, userId)
                    statement.executeUpdate()
                }
        }
        restartProcess()

        assertNull(AuthService.verifyToken(access))
        assertNull(AuthService.refreshClaims(refresh))
    }

    @Test
    fun `a superseded refresh token is refused after rotation`() {
        val userId = newAccount()
        val original = AuthService.issueRefreshToken(userId)

        val claims = AuthService.refreshClaims(original)
        assertNotNull(claims)
        val rotated = CredentialState.rotateRefreshGeneration(
            claims!!.userId,
            claims.refreshGeneration,
        )
        assertNotNull(rotated)
        val replacement = AuthService.issueRefreshToken(
            userId,
            rotated!!.credentialEpoch,
            rotated.refreshGeneration,
        )
        restartProcess()

        // Yeni token calisir, eski token'in kusagi artik kabul edilmez.
        val replacementClaims = AuthService.refreshClaims(replacement)
        assertNotNull(replacementClaims)
        assertNotNull(
            CredentialState.rotateRefreshGeneration(
                replacementClaims!!.userId,
                replacementClaims.refreshGeneration,
            ),
        )
        val reusedClaims = AuthService.refreshClaims(original)
        val reuse = reusedClaims?.let {
            CredentialState.rotateRefreshGeneration(it.userId, it.refreshGeneration)
        }
        assertNull(reuse)
    }

    @Test
    fun `parallel rotations of the same refresh token elect a single winner`() {
        val userId = newAccount()
        val refresh = AuthService.issueRefreshToken(userId)
        val claims = AuthService.refreshClaims(refresh)
        assertNotNull(claims)

        val pool = Executors.newFixedThreadPool(PARALLEL_ATTEMPTS)
        try {
            val tasks = List(PARALLEL_ATTEMPTS) {
                Callable {
                    CredentialState.rotateRefreshGeneration(
                        claims!!.userId,
                        claims.refreshGeneration,
                    )
                }
            }
            val winners = pool.invokeAll(tasks).count { it.get() != null }
            assertEquals(1, winners)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `each account gets an independent opaque credential state`() {
        val first = newAccount()
        val second = newAccount()
        val firstState = CredentialState.snapshot(first)
        val secondState = CredentialState.snapshot(second)
        assertNotNull(firstState)
        assertNotNull(secondState)

        assertNotEquals(firstState!!.credentialEpoch, secondState!!.credentialEpoch)
        assertNotEquals(firstState.credentialEpoch, firstState.refreshGeneration)
        // Sayac degil opaque rastgele deger: bir DB snapshot'i rotasyon sayisi
        // veya hesap yasi cikarimina izin vermemeli.
        assertEquals(32, firstState.credentialEpoch.length)
        assertTrue(firstState.credentialEpoch.matches(Regex("^[0-9a-f]{32}$")))

        // Logout sonrasi her iki deger de degisir.
        AuthService.revokeAllTokens(first)
        val rotatedState = CredentialState.snapshot(first)
        assertNotNull(rotatedState)
        assertNotEquals(firstState.credentialEpoch, rotatedState!!.credentialEpoch)
        assertNotEquals(firstState.refreshGeneration, rotatedState.refreshGeneration)
    }

    private companion object {
        const val LAST_MIGRATION = 18
        const val PARALLEL_ATTEMPTS = 8
    }
}
