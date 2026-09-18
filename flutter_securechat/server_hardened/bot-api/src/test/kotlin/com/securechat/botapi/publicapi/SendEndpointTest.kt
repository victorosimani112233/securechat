package com.securechat.botapi.publicapi

import com.google.common.truth.Truth.assertThat
import com.nimbusds.jose.JOSEObjectType
import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.JWSHeader
import com.nimbusds.jose.JWSObject
import com.nimbusds.jose.Payload
import com.nimbusds.jose.util.Base64URL
import com.nimbusds.jwt.JWTClaimsSet
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.auth.AuthenticatedClient
import com.securechat.botapi.auth.EdDsaJwtVerifier
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.send.EmergencyStopFlag
import com.securechat.botapi.send.SendPipeline
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
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
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * `POST /v1/send` guard zinciri, gercek Ktor motoruyla uctan uca.
 *
 * Bu tek endpoint botun disariya acik butun yuzeyidir. Zincirin her adimi —
 * govde tavani, JWT, acil durdurma, girdi dogrulama, allow-list, rate limit,
 * idempotency — burada bir istemcinin gordugu bicimde surulur. Signal
 * sifreleme ve WebSocket teslimi (adim 8) sinyal sunucusu gerektirdigi icin
 * bu testin kapsaminda degildir; oraya kadar olan her ret yolu kapsamdadir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class SendEndpointTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_send_e2e")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private lateinit var keyPair: KeyPair
    private lateinit var pipeline: SendPipeline
    private val clients = mutableMapOf<String, AuthenticatedClient>()

    private val recipient = "user:${UUID.randomUUID()}"

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; send testi atlandi")
        redis.start()
        postgres.start()
        // Acil durdurma bayragi kalici depoda tutulur; endpoint onsuz
        // fail-closed davranir.
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
        BotApiConfig.databaseUrl = postgres.jdbcUrl
        BotApiConfig.databaseUser = postgres.username
        BotApiConfig.databasePassword = postgres.password
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 29).toByte() }
        BotDatabase.init()
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 23).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 67).toByte() }
        BotApiConfig.idempotencyTtlSeconds = 900
        BotApiConfig.redisHost = redis.host
        BotApiConfig.redisPort = redis.getMappedPort(6379)
        BotApiConfig.redisPassword = null
        BotRedisManager.init()
        EmergencyStopFlag.clear()

        keyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        pipeline = SendPipeline { kid -> clients[kid] }
    }

    @AfterAll
    fun tearDown() {
        if (DockerClientFactory.instance().isDockerAvailable) {
            runCatching { EmergencyStopFlag.clear() }
            BotRedisManager.close()
            runCatching { BotDatabase.close() }
            redis.stop()
            postgres.stop()
        }
    }

    private fun rawPublicKey(pair: KeyPair): ByteArray =
        pair.public.encoded.copyOfRange(pair.public.encoded.size - 32, pair.public.encoded.size)

    /** Her test kendi client'ini kurar; rate limit sayaclari boylece karismaz. */
    private fun registerClient(
        allowList: List<String> = emptyList(),
        ratePerHour: Int = 100,
        perRecipientPerDay: Int = 100,
    ): AuthenticatedClient {
        val kid = "k_${UUID.randomUUID()}"
        val client = AuthenticatedClient(
            clientId = UUID.randomUUID().toString(),
            kid = kid,
            name = "AC1:test",
            publicKey = rawPublicKey(keyPair),
            allowList = allowList,
            ratePerHour = ratePerHour,
            perRecipientPerDay = perRecipientPerDay,
        )
        clients[kid] = client
        return client
    }

    private fun bodyHash(content: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(MessageDigest.getInstance("SHA-256").digest(content))

    private fun token(kid: String, body: ByteArray): String {
        val now = System.currentTimeMillis() / 1000
        val claims = JWTClaimsSet.Builder()
            .audience(EdDsaJwtVerifier.EXPECTED_AUDIENCE)
            .issueTime(Date(now * 1000))
            .expirationTime(Date((now + 30) * 1000))
            .jwtID(UUID.randomUUID().toString())
            .claim("bh", bodyHash(body))
            .build()
        val jws = JWSObject(
            JWSHeader.Builder(JWSAlgorithm.EdDSA).type(JOSEObjectType.JWT).keyID(kid).build(),
            Payload(claims.toJSONObject()),
        )
        val signature = Signature.getInstance("Ed25519").apply {
            initSign(keyPair.private)
            update(jws.signingInput)
        }.sign()
        return "${jws.signingInput.toString(Charsets.US_ASCII)}.${Base64URL.encode(signature)}"
    }

    private fun sendBody(
        recipientRef: String = recipient,
        plaintext: String = Base64.getEncoder().encodeToString("merhaba".toByteArray()),
        recipientUserIds: List<String> = emptyList(),
    ): String {
        val ids = recipientUserIds.joinToString(",") { "\"$it\"" }
        return """{"recipientRef":"$recipientRef","plaintextBase64":"$plaintext",""" +
            """"recipientUserIds":[$ids]}"""
    }

    private fun bot(block: suspend ApplicationTestBuilder.() -> Unit) = testApplication {
        // Production yapilandirmasinin kendisi kosulur.
        application { with(PublicListener) { publicApiModule(pipeline) } }
        block()
    }

    private suspend fun ApplicationTestBuilder.send(
        client: AuthenticatedClient?,
        body: String = sendBody(),
        idempotencyKey: String? = UUID.randomUUID().toString(),
        bearer: String? = null,
    ) = this.client.post("/v1/send") {
        header("Content-Type", "application/json")
        val authorization = bearer ?: client?.let { "Bearer ${token(it.kid, body.toByteArray())}" }
        if (authorization != null) header("Authorization", authorization)
        if (idempotencyKey != null) header("X-Idempotency-Key", idempotencyKey)
        setBody(body)
    }

    // ---------------- Yuzey ----------------

    @Test
    fun `only post to the send path is routed`() = bot {
        assertThat(client.post("/admin/clients").status).isEqualTo(HttpStatusCode.NotFound)
        assertThat(client.post("/v1/send/extra").status).isEqualTo(HttpStatusCode.NotFound)
        assertThat(client.post("/").status).isEqualTo(HttpStatusCode.NotFound)
    }

    // ---------------- Kimlik dogrulamasi ----------------

    @Test
    fun `a request without a credential is refused`() = bot {
        val response = send(client = null)

        assertThat(response.status).isEqualTo(HttpStatusCode.Unauthorized)
    }

    @Test
    fun `a request with an unknown kid is refused`() = bot {
        val stranger = AuthenticatedClient(
            clientId = "unknown", kid = "k_missing", name = "x",
            publicKey = rawPublicKey(keyPair), allowList = emptyList(),
            ratePerHour = 10, perRecipientPerDay = 10,
        )
        val body = sendBody()

        val response = send(null, body, bearer = "Bearer ${token(stranger.kid, body.toByteArray())}")

        assertThat(response.status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(response.bodyAsText()).contains("UNKNOWN_OR_REVOKED_CLIENT")
    }

    @Test
    fun `a token bound to a different body is refused`() = bot {
        val subject = registerClient()
        val signedBody = sendBody()
        val sentBody = sendBody(plaintext = Base64.getEncoder().encodeToString("baska".toByteArray()))

        val response = send(null, sentBody, bearer = "Bearer ${token(subject.kid, signedBody.toByteArray())}")

        assertThat(response.status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(response.bodyAsText()).contains("BODY_HASH_MISMATCH")
    }

    @Test
    fun `a replayed token is refused on the second attempt`() = bot {
        val subject = registerClient()
        val body = sendBody()
        val bearer = "Bearer ${token(subject.kid, body.toByteArray())}"

        val first = send(null, body, bearer = bearer)
        val second = send(null, body, bearer = bearer)

        // Ilk istek adim 8'de sinyal sunucusu olmadigi icin basarisiz olabilir;
        // onemli olan ikinci istegin replay olarak reddedilmesidir.
        assertThat(second.status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(second.bodyAsText()).contains("REPLAYED_JTI")
        assertThat(first.status).isNotEqualTo(HttpStatusCode.Unauthorized)
    }

    // ---------------- Govde ve girdi dogrulama ----------------

    @Test
    fun `an oversized body is refused before authentication`() = bot {
        val subject = registerClient()
        val huge = "A".repeat(300 * 1024)

        val response = send(subject, sendBody(plaintext = huge))

        assertThat(response.status).isEqualTo(HttpStatusCode.PayloadTooLarge)
    }

    @Test
    fun `a malformed json body is refused`() = bot {
        val subject = registerClient()

        val response = send(subject, "{not json")

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
        assertThat(response.bodyAsText()).contains("json_parse_failed")
    }

    @Test
    fun `missing recipient or plaintext is refused`() = bot {
        val subject = registerClient()

        assertThat(send(subject, sendBody(recipientRef = "")).status)
            .isEqualTo(HttpStatusCode.BadRequest)
        assertThat(send(subject, sendBody(plaintext = "")).status)
            .isEqualTo(HttpStatusCode.BadRequest)
    }

    @Test
    fun `a recipient reference that is not private routing is refused`() = bot {
        val subject = registerClient()

        for (bad in listOf(
            "user:not-a-uuid",
            "phone:+905551234567",
            "${UUID.randomUUID()}",
            "group:short-token",
            "user:${UUID.randomUUID()}extra",
        )) {
            val response = send(subject, sendBody(recipientRef = bad))
            assertThat(response.bodyAsText()).contains("invalid_private_routing")
            assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
        }
    }

    @Test
    fun `a group send needs an opaque token and valid member ids`() = bot {
        val subject = registerClient()
        val groupToken = "group:" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32) { 3 })

        // Uye listesi bos: grup routing paketi eksik.
        assertThat(send(subject, sendBody(recipientRef = groupToken)).bodyAsText())
            .contains("invalid_private_routing")
        // Uye listesi bozuk.
        assertThat(
            send(
                subject,
                sendBody(recipientRef = groupToken, recipientUserIds = listOf("not-a-uuid")),
            ).bodyAsText(),
        ).contains("invalid_private_routing")
        // Tekrarli uye: fanout maliyetini dusuk gostermek icin kullanilabilirdi.
        val duplicated = UUID.randomUUID().toString()
        assertThat(
            send(
                subject,
                sendBody(recipientRef = groupToken, recipientUserIds = listOf(duplicated, duplicated)),
            ).bodyAsText(),
        ).contains("invalid_private_routing")
    }

    @Test
    fun `a group larger than the fanout ceiling is refused`() = bot {
        val subject = registerClient()
        val groupToken = "group:" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32) { 4 })
        val members = (1..257).map { UUID.randomUUID().toString() }

        val response = send(subject, sendBody(recipientRef = groupToken, recipientUserIds = members))

        assertThat(response.bodyAsText()).contains("invalid_private_routing")
    }

    @Test
    fun `the idempotency key header is mandatory`() = bot {
        val subject = registerClient()

        val response = send(subject, idempotencyKey = null)

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
        assertThat(response.bodyAsText()).contains("X-Idempotency-Key")
    }

    // ---------------- Allow-list ----------------

    @Test
    fun `an empty allow list denies every recipient`() = bot {
        // Fail-closed: bos liste "her seye izinli" degil, "hicbir seye
        // izinli degil" demektir.
        val subject = registerClient(allowList = emptyList())

        val response = send(subject)

        assertThat(response.status).isEqualTo(HttpStatusCode.Forbidden)
    }

    @Test
    fun `an allow listed recipient passes the allow list`() = bot {
        val subject = registerClient(allowList = listOf(recipient))

        val response = send(subject)

        assertThat(response.status).isNotEqualTo(HttpStatusCode.Forbidden)
    }

    @Test
    fun `a recipient outside the allow list is refused`() = bot {
        val subject = registerClient(allowList = listOf("user:${UUID.randomUUID()}"))

        val response = send(subject, sendBody(recipientRef = "user:${UUID.randomUUID()}"))

        assertThat(response.status).isEqualTo(HttpStatusCode.Forbidden)
        assertThat(response.bodyAsText()).contains("recipient_not_allowed")
    }

    @Test
    fun `a group token alone does not authorize its members`() = bot {
        val groupToken = "group:" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32) { 5 })
        val allowedMember = UUID.randomUUID().toString()
        val subject = registerClient(allowList = listOf(groupToken, "user:$allowedMember"))
        val stranger = UUID.randomUUID().toString()

        val response = send(
            subject,
            sendBody(recipientRef = groupToken, recipientUserIds = listOf(allowedMember, stranger)),
        )

        // Izinli bir grup tokenini bilen client istedigi UUID'ye
        // gonderebilseydi allow-list anlamsiz olurdu.
        assertThat(response.status).isEqualTo(HttpStatusCode.Forbidden)
        assertThat(response.bodyAsText()).contains("recipient_not_allowed")
    }

    // ---------------- Rate limit ve idempotency ----------------

    @Test
    fun `the hourly ceiling produces a 429 with a retry hint`() = bot {
        val subject = registerClient(
            allowList = listOf(recipient),
            ratePerHour = 2,
            perRecipientPerDay = 1000,
        )

        repeat(2) { send(subject) }
        val response = send(subject)

        assertThat(response.status).isEqualTo(HttpStatusCode.TooManyRequests)
        assertThat(response.bodyAsText()).contains("client_per_hour")
        assertThat(response.headers["Retry-After"]).isNotNull()
    }

    @Test
    fun `a repeated idempotency key does not start a second send`() = bot {
        val subject = registerClient(allowList = listOf(recipient))
        val key = UUID.randomUUID().toString()

        send(subject, idempotencyKey = key)
        val second = send(subject, idempotencyKey = key)

        // Rezervasyon birakilmadiysa Conflict, birakildiysa yeniden islenir;
        // hicbir kosulda ikinci bir 202 uretilmemelidir.
        assertThat(second.status).isNotEqualTo(HttpStatusCode.Accepted)
    }

    // ---------------- Acil durdurma ----------------

    @Test
    fun `the emergency stop refuses every send`() = bot {
        val subject = registerClient()
        EmergencyStopFlag.set()
        try {
            val response = send(subject)

            assertThat(response.status).isEqualTo(HttpStatusCode.ServiceUnavailable)
            assertThat(response.bodyAsText()).contains("emergency_stop")
        } finally {
            EmergencyStopFlag.clear()
        }
    }

    @Test
    fun `sending works again after the emergency stop is cleared`() = bot {
        val subject = registerClient()
        EmergencyStopFlag.set()
        EmergencyStopFlag.clear()

        val response = send(subject)

        assertThat(response.status).isNotEqualTo(HttpStatusCode.ServiceUnavailable)
    }

    companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
    }
}
