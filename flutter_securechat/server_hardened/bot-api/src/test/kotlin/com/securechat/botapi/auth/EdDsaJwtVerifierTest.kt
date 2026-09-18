package com.securechat.botapi.auth

import com.google.common.truth.Truth.assertThat
import com.nimbusds.jose.JOSEObjectType
import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.JWSHeader
import com.nimbusds.jose.JWSObject
import com.nimbusds.jose.Payload
import com.nimbusds.jose.util.Base64URL
import com.nimbusds.jwt.JWTClaimsSet
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.util.Base64
import java.util.Date
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName

/**
 * Bot-api JWT dogrulama zinciri.
 *
 * Bu, botun tek kimlik dogrulama sinriridir: burada gecen bir istek
 * kullanicilara mesaj gonderebilir. Her ret sebebi ayri ayri surulur; bir
 * kontrolun sessizce dusmesi dogrudan yetkisiz gonderim demektir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class EdDsaJwtVerifierTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private lateinit var keyPair: KeyPair
    private lateinit var client: AuthenticatedClient
    private lateinit var verifier: EdDsaJwtVerifier

    private val body = """{"recipientRef":"user:x","plaintextBase64":"AAA="}""".toByteArray()

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; JWT testi atlandi")
        redis.start()
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 5).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 91).toByte() }
        BotApiConfig.redisHost = redis.host
        BotApiConfig.redisPort = redis.getMappedPort(6379)
        BotApiConfig.redisPassword = null
        BotRedisManager.init()

        keyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        client = AuthenticatedClient(
            clientId = "AC1",
            kid = "k_test",
            name = "AC1:test",
            publicKey = rawPublicKey(keyPair),
            allowList = emptyList(),
            ratePerHour = 100,
            perRecipientPerDay = 100,
        )
        verifier = EdDsaJwtVerifier { kid -> if (kid == client.kid) client else null }
    }

    @AfterAll
    fun tearDown() {
        if (DockerClientFactory.instance().isDockerAvailable) {
            BotRedisManager.close()
            redis.stop()
        }
    }

    /** X.509 SubjectPublicKeyInfo'nun son 32 baytı ham Ed25519 anahtaridir. */
    private fun rawPublicKey(pair: KeyPair): ByteArray =
        pair.public.encoded.copyOfRange(pair.public.encoded.size - 32, pair.public.encoded.size)

    private fun bodyHash(content: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(MessageDigest.getInstance("SHA-256").digest(content))

    private fun token(
        kid: String? = "k_test",
        algorithm: JWSAlgorithm = JWSAlgorithm.EdDSA,
        audience: String? = EdDsaJwtVerifier.EXPECTED_AUDIENCE,
        issuedAtOffsetSeconds: Long = 0,
        lifetimeSeconds: Long = 30,
        jti: String? = UUID.randomUUID().toString(),
        bodyHashClaim: String? = bodyHash(body),
        signWith: KeyPair = keyPair,
        tamperSignature: Boolean = false,
    ): String {
        val now = System.currentTimeMillis() / 1000 + issuedAtOffsetSeconds
        val builder = JWTClaimsSet.Builder()
            .issueTime(Date(now * 1000))
            .expirationTime(Date((now + lifetimeSeconds) * 1000))
        if (audience != null) builder.audience(audience)
        if (jti != null) builder.jwtID(jti)
        if (bodyHashClaim != null) builder.claim("bh", bodyHashClaim)

        val header = JWSHeader.Builder(algorithm)
            .type(JOSEObjectType.JWT)
            .apply { if (kid != null) keyID(kid) }
            .build()
        val jws = JWSObject(header, Payload(builder.build().toJSONObject()))

        val signature = Signature.getInstance("Ed25519").apply {
            initSign(signWith.private)
            update(jws.signingInput)
        }.sign()
        val encoded = if (tamperSignature) {
            signature.copyOf().also { it[0] = (it[0].toInt() xor 0x01).toByte() }
        } else {
            signature
        }
        return "${jws.signingInput.toString(Charsets.US_ASCII)}.${Base64URL.encode(encoded)}"
    }

    private fun verify(token: String, content: ByteArray = body) = verifier.verify(token, content)

    @Test
    fun `a well formed token is accepted once`() {
        val jti = UUID.randomUUID().toString()

        val result = verify(token(jti = jti))

        assertThat(result).isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
        val ok = result as EdDsaJwtVerifier.Result.Ok
        assertThat(ok.client.clientId).isEqualTo("AC1")
        assertThat(ok.jti).isEqualTo(jti)
    }

    private fun failReason(result: EdDsaJwtVerifier.Result): EdDsaJwtVerifier.Reason {
        assertThat(result).isInstanceOf(EdDsaJwtVerifier.Result.Fail::class.java)
        return (result as EdDsaJwtVerifier.Result.Fail).reason
    }

    @Test
    fun `garbage is rejected as a malformed token`() {
        assertThat(failReason(verify("not-a-jwt")))
            .isEqualTo(EdDsaJwtVerifier.Reason.MALFORMED_TOKEN)
        assertThat(failReason(verify("")))
            .isEqualTo(EdDsaJwtVerifier.Reason.MALFORMED_TOKEN)
        assertThat(failReason(verify("a.b.c")))
            .isEqualTo(EdDsaJwtVerifier.Reason.MALFORMED_TOKEN)
    }

    @Test
    fun `an unsigned or symmetric algorithm is refused`() {
        // alg confusion: HS256'ya dusurulmus bir token kabul edilirse
        // saldirgan public anahtari HMAC sirri gibi kullanabilirdi.
        val hs256 = JWSObject(
            JWSHeader.Builder(JWSAlgorithm.HS256).keyID("k_test").build(),
            Payload(JWTClaimsSet.Builder().jwtID("x").build().toJSONObject()),
        )
        val forged = "${hs256.signingInput.toString(Charsets.US_ASCII)}.${Base64URL.encode(ByteArray(32))}"

        assertThat(failReason(verify(forged))).isEqualTo(EdDsaJwtVerifier.Reason.WRONG_ALG)
    }

    @Test
    fun `a token without a kid is refused`() {
        assertThat(failReason(verify(token(kid = null))))
            .isEqualTo(EdDsaJwtVerifier.Reason.MISSING_KID)
    }

    @Test
    fun `an unknown or revoked client is refused`() {
        assertThat(failReason(verify(token(kid = "k_unknown"))))
            .isEqualTo(EdDsaJwtVerifier.Reason.UNKNOWN_OR_REVOKED_CLIENT)
    }

    @Test
    fun `a signature from another key is refused`() {
        val attacker = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()

        assertThat(failReason(verify(token(signWith = attacker))))
            .isEqualTo(EdDsaJwtVerifier.Reason.BAD_SIGNATURE)
    }

    @Test
    fun `a tampered signature is refused`() {
        assertThat(failReason(verify(token(tamperSignature = true))))
            .isEqualTo(EdDsaJwtVerifier.Reason.BAD_SIGNATURE)
    }

    @Test
    fun `a valid signature with trailing garbage is refused`() {
        val parts = token().split('.')
        val signature = Base64.getUrlDecoder().decode(parts[2]) + byteArrayOf(0)
        val malformed = "${parts[0]}.${parts[1]}.${Base64URL.encode(signature)}"

        assertThat(failReason(verify(malformed)))
            .isEqualTo(EdDsaJwtVerifier.Reason.BAD_SIGNATURE)
    }

    @Test
    fun `a token for another audience is refused`() {
        assertThat(failReason(verify(token(audience = "some-other-service"))))
            .isEqualTo(EdDsaJwtVerifier.Reason.WRONG_AUDIENCE)
        assertThat(failReason(verify(token(audience = null))))
            .isEqualTo(EdDsaJwtVerifier.Reason.WRONG_AUDIENCE)
    }

    @Test
    fun `a token issued in the future beyond the skew is refused`() {
        // +5 sn tolerans var; 60 sn ileri bir saat kabul edilmemeli.
        assertThat(failReason(verify(token(issuedAtOffsetSeconds = 60))))
            .isEqualTo(EdDsaJwtVerifier.Reason.IAT_OUT_OF_WINDOW)
    }

    @Test
    fun `a small forward clock skew is tolerated`() {
        assertThat(verify(token(issuedAtOffsetSeconds = 3)))
            .isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
    }

    @Test
    fun `a token older than the issue window is refused`() {
        assertThat(failReason(verify(token(issuedAtOffsetSeconds = -120, lifetimeSeconds = 600))))
            .isEqualTo(EdDsaJwtVerifier.Reason.IAT_OUT_OF_WINDOW)
    }

    @Test
    fun `an expired token is refused`() {
        assertThat(failReason(verify(token(issuedAtOffsetSeconds = -30, lifetimeSeconds = 10))))
            .isEqualTo(EdDsaJwtVerifier.Reason.EXPIRED)
    }

    @Test
    fun `expiration cannot precede issue time inside clock skew`() {
        // exp su an gelecekte olsa bile iat'ten onceyse zaman araligi ters ve
        // token gecersizdir.
        assertThat(failReason(verify(token(issuedAtOffsetSeconds = 3, lifetimeSeconds = -1))))
            .isEqualTo(EdDsaJwtVerifier.Reason.EXPIRED)
    }

    @Test
    fun `a long lived token is refused even before it expires`() {
        // Kisa omur bir kontrattir: 1 saatlik bir token calindiginda
        // pencere kabul edilemez olurdu.
        assertThat(failReason(verify(token(lifetimeSeconds = 3600))))
            .isEqualTo(EdDsaJwtVerifier.Reason.EXPIRED)
    }

    @Test
    fun `a token without a jti is refused`() {
        assertThat(failReason(verify(token(jti = null))))
            .isEqualTo(EdDsaJwtVerifier.Reason.MALFORMED_TOKEN)
    }

    @Test
    fun `a token without a body hash claim is refused`() {
        assertThat(failReason(verify(token(bodyHashClaim = null))))
            .isEqualTo(EdDsaJwtVerifier.Reason.MALFORMED_TOKEN)
    }

    @Test
    fun `a body that does not match the claim is refused`() {
        val other = """{"recipientRef":"user:victim","plaintextBase64":"BBB="}""".toByteArray()

        assertThat(failReason(verify(token(), other)))
            .isEqualTo(EdDsaJwtVerifier.Reason.BODY_HASH_MISMATCH)
    }

    @Test
    fun `replaying the same token is refused`() {
        val replayed = token()

        assertThat(verify(replayed)).isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
        assertThat(failReason(verify(replayed))).isEqualTo(EdDsaJwtVerifier.Reason.REPLAYED_JTI)
    }

    @Test
    fun `a wrong body does not burn the nonce of the legitimate request`() {
        val jti = UUID.randomUUID().toString()
        val captured = token(jti = jti)
        val tamperedBody = """{"recipientRef":"user:victim"}""".toByteArray()

        // Saldirgan yakaladigi token'i baska bir body ile oynatir.
        assertThat(failReason(verify(captured, tamperedBody)))
            .isEqualTo(EdDsaJwtVerifier.Reason.BODY_HASH_MISMATCH)

        // Mesru istek hala gecmelidir: nonce yanmamis olmali.
        assertThat(verify(captured)).isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
    }

    @Test
    fun `two different requests with distinct nonces both pass`() {
        assertThat(verify(token())).isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
        assertThat(verify(token())).isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
    }

    @Test
    fun `an empty body is still bound by its hash`() {
        val empty = ByteArray(0)

        assertThat(verify(token(bodyHashClaim = bodyHash(empty)), empty))
            .isInstanceOf(EdDsaJwtVerifier.Result.Ok::class.java)
        // Bos body icin uretilmis bir token dolu bir body'yi yetkilendiremez.
        assertThat(failReason(verify(token(bodyHashClaim = bodyHash(empty)), body)))
            .isEqualTo(EdDsaJwtVerifier.Reason.BODY_HASH_MISMATCH)
    }
}
