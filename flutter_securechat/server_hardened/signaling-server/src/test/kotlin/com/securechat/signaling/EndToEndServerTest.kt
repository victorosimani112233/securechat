package com.securechat.signaling

import ch.qos.logback.classic.Level
import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.client.plugins.websocket.WebSockets as ClientWebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.client.statement.readBytes
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Uctan uca sunucu senaryolari.
 *
 * Gercek Ktor motoru, gercek PostgreSQL ve gercek Redis ile production
 * modulunun kendisi (`signalingModule`) kosulur. Buradaki testler tek tek
 * fonksiyonlari degil, bir istemcinin gordugu davranisi dogrular: kimlik
 * dogrulamasi, operator yuzeylerinin kapaliligi, govde tavanlari, rehber
 * kotasi ve WebSocket yonlendirmesi.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class EndToEndServerTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_e2e")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private lateinit var connectionManager: ConnectionManager
    private lateinit var userRegistry: UserRegistry
    private lateinit var fcmTokenStore: FcmTokenStore
    private lateinit var fcmPushSender: FcmPushSender
    private val attachmentStore = AttachmentStore(
        java.nio.file.Files.createTempDirectory("e2e-attachments"),
        ttlMillis = 60 * 60 * 1000L,
    )

    private val metricsToken = "test-only-metrics-bearer-token-32-characters"
    private val json = Json { ignoreUnknownKeys = true }

    /** Kayitli bir hesap ve gecerli access token'i. */
    private lateinit var alice: String
    private lateinit var aliceToken: String
    private lateinit var bob: String
    private lateinit var bobToken: String

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; e2e atlandi")
        postgres.start()
        redis.start()

        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)

        ServerPrivacy.initialize()
        PurposeSeparatedSecrets.validate()
        PrivateDirectory.initialize()
        MetricsAccess.initialize()
        AuthService.initialize()
        CredentialState.initialize()

        fcmTokenStore = FcmTokenStore()
        fcmPushSender = FcmPushSender(fcmTokenStore)
        connectionManager = ConnectionManager(fcmPushSender)
        userRegistry = UserRegistry()
        // WebSocket, retention saglikli degilse hic acilmaz.
        PrivacyRetentionWorker.runOnce()

        alice = UUID.randomUUID().toString()
        bob = UUID.randomUUID().toString()
        userRegistry.registerUser(alice)
        userRegistry.registerUser(bob)
        aliceToken = AuthService.issueToken(alice)
        bobToken = AuthService.issueToken(bob)
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { RedisManager.close() }
        runCatching { Database.close() }
        redis.stop()
        postgres.stop()
    }

    /** Yeni kayitli bir hesap ve access token'i. */
    private fun newAccount(): Pair<String, String> {
        val userId = UUID.randomUUID().toString()
        userRegistry.registerUser(userId)
        return userId to AuthService.issueToken(userId)
    }

    private fun sha256Hex(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun ApplicationTestBuilder.configureServer() {
        application {
            signalingModule(connectionManager, userRegistry, fcmTokenStore, fcmPushSender, attachmentStore)
        }
    }

    private fun e2e(block: suspend ApplicationTestBuilder.() -> Unit) = testApplication {
        configureServer()
        block()
    }

    @Test
    fun `authenticated push registration retains a hint on same token refresh`() = e2e {
        val (user, accessToken) = newAccount()
        val deviceToken = "synthetic-fcm-token-for-hint-route-test"
        val key = ByteArray(32) { (it + 1).toByte() }
        val encodedKey = Base64.getUrlEncoder().withoutPadding().encodeToString(key)
        try {
            TestLogCapture("HttpRoutes", "FcmTokenStore").use { logs ->
                val initial = client.post("/api/v1/fcm/register") {
                    header("Authorization", "Bearer $accessToken")
                    header("Content-Type", "application/json")
                    setBody("""{"userId":"$user","fcmToken":"$deviceToken","pushHintKey":"$encodedKey"}""")
                }
                assertEquals(HttpStatusCode.OK, initial.status)
                assertArrayEquals(key, fcmTokenStore.getPushHintKey(user))

                val refresh = client.post("/api/v1/fcm/register") {
                    header("Authorization", "Bearer $accessToken")
                    header("Content-Type", "application/json")
                    setBody("""{"userId":"$user","fcmToken":"$deviceToken"}""")
                }
                assertEquals(HttpStatusCode.OK, refresh.status)
                assertArrayEquals(key, fcmTokenStore.getPushHintKey(user))
                assertArrayEquals(key, FcmTokenStore().getPushHintKey(user))
                assertEquals(
                    listOf(
                        Level.INFO to "[API] FCM kayit istegi; hint_key_field=present",
                        Level.INFO to "[FCM] Token kaydedildi; hint_key=received",
                        Level.INFO to "[API] FCM kayit istegi; hint_key_field=absent",
                        Level.INFO to "[FCM] Token kaydedildi; hint_key=preserved",
                    ),
                    logs.events.filter {
                        it.message == "[API] FCM kayit istegi; hint_key_field={}" ||
                            it.message == "[FCM] Token kaydedildi; hint_key={}"
                    }.map { it.level to it.formattedMessage },
                )
                logs.assertNoSecrets(user, accessToken, deviceToken, encodedKey)
            }
        } finally {
            fcmTokenStore.removeToken(user)
        }
    }

    @Test
    fun `push registration diagnostics require authentication and matching user id`() = e2e {
        val (user, accessToken) = newAccount()
        val (otherUser, _) = newAccount()
        val deviceToken = "synthetic-fcm-token-for-rejected-route-test"
        val encodedKey = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { 9 })
        TestLogCapture("HttpRoutes", "FcmTokenStore").use { logs ->
            for ((bearer, target, status) in listOf(
                Triple(null, user, HttpStatusCode.Unauthorized),
                Triple("invalid-bearer-for-fcm-log-test", user, HttpStatusCode.Unauthorized),
                Triple(accessToken, otherUser, HttpStatusCode.Forbidden),
            )) {
                val response = client.post("/api/v1/fcm/register") {
                    if (bearer != null) header("Authorization", "Bearer $bearer")
                    header("Content-Type", "application/json")
                    setBody("""{"userId":"$target","fcmToken":"$deviceToken","pushHintKey":"$encodedKey"}""")
                }
                assertEquals(status, response.status)
            }
            assertNull(fcmTokenStore.getToken(user))
            assertNull(fcmTokenStore.getToken(otherUser))
            assertTrue(logs.events.none {
                it.formattedMessage.startsWith("[API] FCM") || it.loggerName == "FcmTokenStore"
            }, "Rejected requests must not produce FCM registration diagnostics")
            logs.assertNoSecrets(user, otherUser, accessToken, deviceToken, encodedKey)
        }
    }

    // ---------------- HTTP: kimlik dogrulamasi ve operator yuzeyleri ----------------

    @Test
    fun `the directory config is public because it carries no secret`() = e2e {
        val response = client.get("/api/v1/directory/config")

        assertEquals(HttpStatusCode.OK, response.status)
        val body = json.parseToJsonElement(response.bodyAsText()) as JsonObject
        assertEquals(PrivateDirectory.oprf.keyId, body["keyId"]?.jsonPrimitive?.content)
        // Ozel anahtar materyali hicbir bicimde donmez.
        assertFalse(response.bodyAsText().contains("privateExponent"))
    }

    @Test
    fun `an unauthenticated snapshot request is refused`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/directory/snapshot").status)
    }

    @Test
    fun `a forged bearer token is refused`() = e2e {
        val response = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer not-a-real-token")
        }

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `metrics requires the operator bearer token`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.get("/metrics").status)
        assertEquals(
            HttpStatusCode.Unauthorized,
            client.get("/metrics") { header("Authorization", "Bearer wrong") }.status,
        )

        val allowed = client.get("/metrics") { header("Authorization", "Bearer $metricsToken") }

        assertEquals(HttpStatusCode.OK, allowed.status)
        assertTrue(allowed.bodyAsText().contains("securechat_"))
        // Metrics yuzeyi hicbir hesap kimligi tasimamalidir.
        assertFalse(allowed.bodyAsText().contains(alice))
    }

    @Test
    fun `the snapshot is padded to a bucket and hides the real account count`() = e2e {
        val response = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer $aliceToken")
        }

        assertEquals(HttpStatusCode.OK, response.status)
        val body = json.parseToJsonElement(response.bodyAsText()) as JsonObject
        val entries = body["entries"]!!.jsonArray

        // Iki gercek hesap var; yanit kova boyutunda olmali.
        assertEquals(DirectorySnapshotCache.PADDING_BUCKET, entries.size)
        val labels = entries.map { (it as JsonObject)["label"]!!.jsonPrimitive.content }
        assertEquals(entries.size, labels.toSet().size, "etiket carpismasi")
        // Ham hesap kimligi hicbir kayitta gorunmez.
        assertFalse(response.bodyAsText().contains(alice))
        assertFalse(response.bodyAsText().contains(bob))
    }

    @Test
    fun `an encrypted attachment is uploaded once and fetched by another account`() = e2e {
        val ciphertext = ByteArray(300_000) { (it * 7 % 256).toByte() }
        val upload = client.post("/api/v1/attachments") {
            header("Authorization", "Bearer $aliceToken")
            setBody(ciphertext)
        }
        assertEquals(HttpStatusCode.Created, upload.status)
        val body = json.parseToJsonElement(upload.bodyAsText()) as JsonObject
        val id = body["id"]!!.jsonPrimitive.content
        assertEquals(43, id.length)

        val download = client.get("/api/v1/attachments/$id") {
            header("Authorization", "Bearer $bobToken")
        }
        assertEquals(HttpStatusCode.OK, download.status)
        assertEquals("no-store", download.headers[HttpHeaders.CacheControl])
        assertTrue(ciphertext.contentEquals(download.readBytes()))
    }

    @Test
    fun `attachments require an account and an existing id`() = e2e {
        assertEquals(
            HttpStatusCode.Unauthorized,
            client.post("/api/v1/attachments") { setBody(ByteArray(10)) }.status,
        )
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/attachments/${"a".repeat(43)}").status)
        assertEquals(
            HttpStatusCode.NotFound,
            client.get("/api/v1/attachments/${"a".repeat(43)}") {
                header("Authorization", "Bearer $aliceToken")
            }.status,
        )
        assertEquals(
            HttpStatusCode.NotFound,
            client.get("/api/v1/attachments/not-an-id") {
                header("Authorization", "Bearer $aliceToken")
            }.status,
        )
    }

    @Test
    fun `an unchanged snapshot is answered with 304 even after a rebuild`() = e2e {
        val first = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer $aliceToken")
        }
        assertEquals(HttpStatusCode.OK, first.status)
        val etag = first.headers[HttpHeaders.ETag]
        assertTrue(etag != null && etag.startsWith("\"") && etag.endsWith("\""))

        // Yeniden kurulus kayitlari yeni nonce ile muhurler; anlam ayni
        // oldugu icin ETag degismez ve istemci elindekini kullanir.
        DirectorySnapshotCache.invalidate()
        val again = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer $aliceToken")
            header(HttpHeaders.IfNoneMatch, etag!!)
        }
        assertEquals(HttpStatusCode.NotModified, again.status)
        assertEquals(etag, again.headers[HttpHeaders.ETag])
        assertEquals("", again.bodyAsText())

        val stale = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer $aliceToken")
            header(HttpHeaders.IfNoneMatch, "\"eski\"")
        }
        assertEquals(HttpStatusCode.OK, stale.status)
    }

    @Test
    fun `an oversized body is refused before it is parsed`() = e2e {
        val response = client.post("/api/v1/otp/request") {
            header("Content-Type", "application/json")
            setBody("""{"email":"${"a".repeat(64 * 1024)}@example.com"}""")
        }

        assertEquals(HttpStatusCode.PayloadTooLarge, response.status)
    }

    @Test
    fun `a malformed json body is a client error rather than a crash`() = e2e {
        val response = client.post("/api/v1/otp/request") {
            header("Content-Type", "application/json")
            setBody("{not json")
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `the ice configuration only offers tls relays`() = e2e {
        val response = client.get("/api/v1/ice/config") {
            header("Authorization", "Bearer $aliceToken")
        }

        assertEquals(HttpStatusCode.OK, response.status)
        val body = response.bodyAsText()
        assertTrue(body.contains("turns:"), body)
        assertFalse(body.contains("\"turn:"), body)
    }

    // ---------------- WebSocket ----------------

    /**
     * Baglantinin gercekten kabul edilip edilmedigi.
     *
     * "Cerceve gelmedi" tek basina ret kaniti degildir: kabul edilmis fakat
     * bosta duran bir soket de cerceve gondermez. Kabul edilen baglanti
     * kullaniciyi cevrimici yapar, olcut budur.
     */
    private suspend fun awaitOnline(userId: String, timeoutMillis: Long = 3_000): Boolean =
        withTimeoutOrNull(timeoutMillis) {
            while (!connectionManager.isOnline(userId)) kotlinx.coroutines.delay(20)
            true
        } ?: false

    private suspend fun ApplicationTestBuilder.wsClient() =
        createClient { install(ClientWebSockets) }

    @Test
    fun `a websocket without a credential is refused`() = e2e {
        val user = UUID.randomUUID().toString()
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$user")

        assertFalse(awaitOnline(user), "kimliksiz baglanti kabul edildi")
        runCatching { session.close() }
    }

    @Test
    fun `a credential in the query string is refused even when a valid header exists`() = e2e {
        val (user, token) = newAccount()
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$user&token=$token") {
            header("Authorization", "Bearer $token")
        }

        // Query token proxy/access loglarina duser; gecerli bir header olsa
        // bile fail-closed reddedilir.
        assertFalse(awaitOnline(user), "query string credential kabul edildi")
        runCatching { session.close() }
    }

    @Test
    fun `a token belonging to another account cannot claim this user id`() = e2e {
        val victim = newAccount().first
        val attackerToken = newAccount().second
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$victim") {
            header("Authorization", "Bearer $attackerToken")
        }

        assertFalse(awaitOnline(victim), "baska hesabin token'i kabul edildi")
        runCatching { session.close() }
    }

    @Test
    fun `an expired or forged websocket credential is refused`() = e2e {
        val user = UUID.randomUUID().toString()
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$user") {
            header("Authorization", "Bearer not.a.real.token")
        }

        assertFalse(awaitOnline(user))
        runCatching { session.close() }
    }

    @Test
    fun `an authenticated socket connects and appears online`() = e2e {
        val (user, token) = newAccount()
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$user") {
            header("Authorization", "Bearer $token")
        }

        assertTrue(awaitOnline(user, timeoutMillis = 5_000))
        session.close()
    }

    @Test
    fun `a message is routed to the recipient socket`() = e2e {
        val client = wsClient()
        val senderSession = client.webSocketSession("/ws?userId=$alice") {
            header("Authorization", "Bearer $aliceToken")
        }
        val recipientSession = client.webSocketSession("/ws?userId=$bob") {
            header("Authorization", "Bearer $bobToken")
        }
        withTimeoutOrNull(5_000) {
            while (!connectionManager.isOnline(bob)) kotlinx.coroutines.delay(25)
        }

        val messageId = UUID.randomUUID().toString()
        senderSession.send(
            Frame.Text(
                """{"type":"encrypted_message","senderId":"$alice",""" +
                    """"recipientId":"$bob","messageId":"$messageId","ciphertext":"AAAA"}""",
            ),
        )

        val delivered = withTimeoutOrNull(10_000) {
            var found: String? = null
            while (found == null) {
                val frame = recipientSession.incoming.receiveCatching().getOrNull() ?: break
                val text = (frame as? Frame.Text)?.readText() ?: continue
                if (text.contains(messageId)) found = text
            }
            found
        }

        assertNotNull(delivered)
        assertTrue(delivered!!.contains(""""senderId":"$alice""""), delivered)
        senderSession.close()
        recipientSession.close()
    }

    @Test
    fun `a spoofed sender id is overridden by the authenticated identity`() = e2e {
        val client = wsClient()
        val senderSession = client.webSocketSession("/ws?userId=$alice") {
            header("Authorization", "Bearer $aliceToken")
        }
        val recipientSession = client.webSocketSession("/ws?userId=$bob") {
            header("Authorization", "Bearer $bobToken")
        }
        withTimeoutOrNull(5_000) {
            while (!connectionManager.isOnline(bob)) kotlinx.coroutines.delay(25)
        }

        val messageId = UUID.randomUUID().toString()
        val victim = UUID.randomUUID().toString()
        senderSession.send(
            Frame.Text(
                """{"type":"encrypted_message","senderId":"$victim",""" +
                    """"recipientId":"$bob","messageId":"$messageId","ciphertext":"AAAA"}""",
            ),
        )

        val delivered = withTimeoutOrNull(10_000) {
            var found: String? = null
            while (found == null) {
                val frame = recipientSession.incoming.receiveCatching().getOrNull() ?: break
                val text = (frame as? Frame.Text)?.readText() ?: continue
                if (text.contains(messageId)) found = text
            }
            found
        }

        assertNotNull(delivered)
        // Istemcinin iddia ettigi gonderen degil, token'daki kimlik gecerlidir.
        assertTrue(delivered!!.contains(alice), delivered)
        assertFalse(delivered.contains(victim), delivered)
        senderSession.close()
        recipientSession.close()
    }

    @Test
    // Sealed Sender mimarisi kaldirildi; bu guard BILEREK duruyor. Eski bir
    // istemci hala SEALED:v1: zarfi gonderirse cerceve tasinmamali.
    fun `sealed sender ciphertext is never accepted on an identified websocket`() = e2e {
        val (sender, senderToken) = newAccount()
        val (recipient, recipientToken) = newAccount()
        val webSocketClient = wsClient()
        val senderSession = webSocketClient.webSocketSession("/ws?userId=$sender") {
            header("Authorization", "Bearer $senderToken")
        }
        val recipientSession = webSocketClient.webSocketSession("/ws?userId=$recipient") {
            header("Authorization", "Bearer $recipientToken")
        }
        assertTrue(awaitOnline(sender, timeoutMillis = 5_000))
        assertTrue(awaitOnline(recipient, timeoutMillis = 5_000))

        senderSession.send(
            Frame.Text(
                """{"type":"encrypted_message","senderId":"$sender","recipientId":"$recipient","envelope":"SEALED:v1:AAAA","deliveryId":"${"Z".repeat(43)}"}""",
            ),
        )

        val leaked = withTimeoutOrNull(750) {
            recipientSession.incoming.receiveCatching().getOrNull()
        }
        assertNull(leaked)
        senderSession.close()
        recipientSession.close()
    }

    @Test
    fun `an oversized frame closes the socket instead of being processed`() = e2e {
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$alice") {
            header("Authorization", "Bearer $aliceToken")
        }
        withTimeoutOrNull(5_000) {
            while (!connectionManager.isOnline(alice)) kotlinx.coroutines.delay(25)
        }

        // 256 KB tavaninin uzerinde tek cerceve.
        val huge = "x".repeat(300 * 1024)
        runCatching {
            session.send(
                Frame.Text("""{"type":"encrypted_message","recipientId":"$bob","ciphertext":"$huge"}"""),
            )
        }

        val closed = withTimeoutOrNull(10_000) {
            while (connectionManager.isOnline(alice)) kotlinx.coroutines.delay(25)
            true
        }
        assertEquals(true, closed)
        runCatching { session.close() }
    }

    // ---------------- Operator yuzeyleri ----------------

    @Test
    fun `liveness is public but carries no dependency detail`() = e2e {
        val response = client.get("/health")

        assertEquals(HttpStatusCode.OK, response.status)
        val body = response.bodyAsText()
        // Anonim bir istemciye stack'in ic yapisi verilmez.
        assertFalse(body.contains("redis", ignoreCase = true), body)
        assertFalse(body.contains("database", ignoreCase = true), body)
        assertFalse(body.contains("uptime", ignoreCase = true), body)
    }

    @Test
    fun `readiness detail is operator only`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.get("/ready").status)

        val allowed = client.get("/ready") { header("Authorization", "Bearer $metricsToken") }

        assertEquals(HttpStatusCode.OK, allowed.status)
        assertTrue(allowed.bodyAsText().contains("redis"))
    }

    @Test
    fun `the artefact identity is operator only`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/version").status)

        val allowed = client.get("/api/v1/version") { header("Authorization", "Bearer $metricsToken") }

        assertEquals(HttpStatusCode.OK, allowed.status)
        assertTrue(allowed.bodyAsText().contains("migrationTarget"))
    }

    // ---------------- Rehber kotasi ve dogrulama ----------------

    @Test
    fun `an exhausted directory quota is refused with a retry hint`() = e2e {
        val heavyUser = UUID.randomUUID().toString()
        userRegistry.registerUser(heavyUser)
        val token = AuthService.issueToken(heavyUser)
        // Gunluk kotayi dogrudan tuket; her batch 256 RSA ozel islemi
        // oldugu icin kotayi HTTP uzerinden doldurmak gereksiz yavas olurdu.
        repeat(DirectoryQuota.DAILY_CANDIDATE_LIMIT / PrivateDirectoryOprf.AUTHENTICATED_BATCH_SIZE) {
            DirectoryQuota.tryConsume(heavyUser, PrivateDirectoryOprf.AUTHENTICATED_BATCH_SIZE)
        }

        val response = client.post("/api/v1/directory/evaluate") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody("""{"keyId":"${PrivateDirectory.oprf.keyId}","blinded":[]}""")
        }

        assertEquals(HttpStatusCode.TooManyRequests, response.status)
        assertTrue(response.bodyAsText().contains("directory_quota_exhausted"))
        assertEquals("3600", response.headers["Retry-After"])
    }

    @Test
    fun `a directory batch of the wrong size is refused`() = e2e {
        val response = client.post("/api/v1/directory/evaluate") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody("""{"keyId":"${PrivateDirectory.oprf.keyId}","blinded":["AAAA"]}""")
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `a stale directory key id is a conflict rather than a silent mismatch`() = e2e {
        val response = client.post("/api/v1/directory/evaluate") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody("""{"keyId":"an-old-key-id","blinded":[]}""")
        }

        assertEquals(HttpStatusCode.Conflict, response.status)
    }

    @Test
    fun `an unknown field in a directory body is refused`() = e2e {
        val response = client.post("/api/v1/directory/evaluate") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody("""{"keyId":"x","blinded":[],"extra":"surprise"}""")
        }

        // Rehber govdeleri strict parse edilir; bilinmeyen alan sessizce
        // yutulmaz.
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    // ---------------- Prekey yetkisi ----------------

    @Test
    fun `a prekey upload with too many one time keys is refused`() = e2e {
        clearRateLimits()
        val response = uploadOlmBundle(aliceToken, otpkCount = MAX_ONE_TIME_PREKEYS + 1)

        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertTrue(response.bodyAsText().contains("invalid_prekey_material"))
    }

    @Test
    fun `libsignal uploads and the refresh route are retired`() = e2e {
        // libsignal (v1) prekey yuzeyi 2026-10-23'te kaldirildi (V31). Eski
        // govde Olm kimligi tasimadigi icin reddedilir; refresh yolu yoktur.
        clearRateLimits()
        val (_, token) = newAccount()
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(33) { 5 })
        val sig = java.util.Base64.getEncoder().encodeToString(ByteArray(64) { 6 })
        val legacy = client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"identityPublicKey":"$key","registrationId":555,"signedPreKeyId":1,""" +
                    """"signedPreKey":"$key","signedPreKeySignature":"$sig",""" +
                    """"oneTimePreKeys":[{"keyId":1,"publicKey":"$key"}]}""",
            )
        }
        assertEquals(HttpStatusCode.BadRequest, legacy.status)
        assertTrue(legacy.bodyAsText().contains("invalid_prekey_material"))

        val refresh = client.post("/api/v1/prekeys/refresh") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody("""[{"keyId":1,"publicKey":"$key"}]""")
        }
        assertEquals(HttpStatusCode.NotFound, refresh.status)
    }

    @Test
    fun `a prekey upload without a credential is refused`() = e2e {
        val response = client.post("/api/v1/prekeys/upload") {
            header("Content-Type", "application/json")
            setBody("""{"olmIdentityKey":"AA","olmSigningKey":"AA","olmOneTimeKeys":[]}""")
        }

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `the retired sfu room endpoint no longer exists`() = e2e {
        val response = client.get("/api/v1/sfu/room/${UUID.randomUUID()}") {
            header("Authorization", "Bearer $aliceToken")
        }

        // Janus SFU 2026-10-14'te kaldirildi.
        assertEquals(HttpStatusCode.NotFound, response.status)
    }

    @Test
    fun `fcm unregister cannot target another account`() = e2e {
        val response = client.post("/api/v1/fcm/unregister") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody("""{"userId":"$bob","token":"whatever"}""")
        }

        // Body'deki userId token'in sub'undan farkli: istek reddedilir,
        // kurbanin push kaydina dokunulmaz.
        assertEquals(HttpStatusCode.Forbidden, response.status)
        assertNull(fcmTokenStore.getToken(bob))
    }

    @Test
    fun `fcm unregister works for the account that owns the token`() = e2e {
        val response = client.post("/api/v1/fcm/unregister") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody("""{"userId":"$alice","token":"whatever"}""")
        }

        assertEquals(HttpStatusCode.OK, response.status)
    }

    @Test
    fun `a message to an unknown recipient is dropped without creating a queue`() = e2e {
        val (sender, senderToken) = newAccount()
        val strangerId = UUID.randomUUID().toString()
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$sender") {
            header("Authorization", "Bearer $senderToken")
        }
        assertTrue(awaitOnline(sender, timeoutMillis = 5_000))

        session.send(
            Frame.Text(
                """{"type":"encrypted_message","recipientId":"$strangerId",""" +
                    """"messageId":"${UUID.randomUUID()}","ciphertext":"AAAA"}""",
            ),
        )
        kotlinx.coroutines.delay(500)

        // Uydurulmus bir UUID icin kalici offline kuyruk anahtari olusmamali.
        val queued = RedisManager.use { jedis ->
            jedis.zcard(ServerPrivacy.queueKey("delivery", strangerId))
        } ?: 0L
        assertEquals(0L, queued)
        session.close()
    }

    @Test
    fun `a message for an offline account is queued and delivered on reconnect`() = e2e {
        val (sender, senderToken) = newAccount()
        val (receiver, receiverToken) = newAccount()
        val client = wsClient()
        val senderSession = client.webSocketSession("/ws?userId=$sender") {
            header("Authorization", "Bearer $senderToken")
        }
        assertTrue(awaitOnline(sender, timeoutMillis = 5_000))

        val messageId = UUID.randomUUID().toString()
        senderSession.send(
            Frame.Text(
                """{"type":"encrypted_message","recipientId":"$receiver",""" +
                    """"messageId":"$messageId","ciphertext":"AAAA"}""",
            ),
        )
        kotlinx.coroutines.delay(500)

        // Alici simdi baglaniyor; kuyruk teslim edilmeli.
        val receiverSession = client.webSocketSession("/ws?userId=$receiver") {
            header("Authorization", "Bearer $receiverToken")
        }
        val delivered = withTimeoutOrNull(10_000) {
            var found: String? = null
            while (found == null) {
                val frame = receiverSession.incoming.receiveCatching().getOrNull() ?: break
                val text = (frame as? Frame.Text)?.readText() ?: continue
                if (text.contains(messageId)) found = text
            }
            found
        }

        assertNotNull(delivered)
        assertTrue(delivered!!.contains(sender), delivered)
        val deliveryToken = json.parseToJsonElement(delivered).jsonObject["deliveryToken"]
            ?.jsonPrimitive?.content
        assertNotNull(deliveryToken)
        assertEquals(
            1L,
            RedisManager.use { jedis ->
                jedis.zcard(ServerPrivacy.queueKey("delivery", receiver))
            },
            "socket send ACK yerine gecmemeli",
        )

        // ACK kaybolursa yeni socket ayni opak teslim tokeniyla ayni
        // ciphertext'i tekrar almali; kayit socket send sonrasinda silinmez.
        val retrySession = client.webSocketSession("/ws?userId=$receiver") {
            header("Authorization", "Bearer $receiverToken")
        }
        val retried = withTimeoutOrNull(10_000) {
            var found: String? = null
            while (found == null) {
                val frame = retrySession.incoming.receiveCatching().getOrNull() ?: break
                val text = (frame as? Frame.Text)?.readText() ?: continue
                if (text.contains(messageId)) found = text
            }
            found
        }
        assertNotNull(retried)
        assertEquals(
            deliveryToken,
            json.parseToJsonElement(retried!!).jsonObject["deliveryToken"]
                ?.jsonPrimitive?.content,
        )
        retrySession.send(
            Frame.Text(
                """{"type":"delivery_transport_ack","recipientId":"server","deliveryToken":"$deliveryToken"}""",
            ),
        )
        val removed = withTimeoutOrNull(5_000) {
            while (RedisManager.use { jedis ->
                    jedis.zcard(ServerPrivacy.queueKey("delivery", receiver))
                } != 0L
            ) {
                kotlinx.coroutines.delay(25)
            }
            true
        } ?: false
        assertTrue(removed, "recipient ACK kuyruk kaydini silmedi")
        senderSession.close()
        receiverSession.close()
        retrySession.close()
    }

    @Test
    fun `the offline queue stores ciphertext rather than the message json`() = e2e {
        val (sender, senderToken) = newAccount()
        val receiver = newAccount().first
        val client = wsClient()
        val session = client.webSocketSession("/ws?userId=$sender") {
            header("Authorization", "Bearer $senderToken")
        }
        assertTrue(awaitOnline(sender, timeoutMillis = 5_000))

        val marker = "MARKER-${UUID.randomUUID()}"
        session.send(
            Frame.Text(
                """{"type":"encrypted_message","recipientId":"$receiver",""" +
                    """"messageId":"${UUID.randomUUID()}","ciphertext":"$marker"}""",
            ),
        )
        kotlinx.coroutines.delay(500)

        val stored = RedisManager.use { jedis ->
            val tokens = jedis.zrange(ServerPrivacy.queueKey("delivery", receiver), 0, -1)
                ?: emptySet()
            if (tokens.isEmpty()) emptyList() else jedis.mget(
                *tokens.map {
                    ServerPrivacy.queueItemKey("delivery", receiver, it)
                }.toTypedArray()
            ).filterNotNull()
        } ?: emptyList()
        assertTrue(stored.isNotEmpty(), "mesaj kuyruga girmedi")
        // Kuyruk muhurludur: ne alici kimligi ne de mesaj govdesi duz durur.
        for (entry in stored) {
            assertFalse(entry.contains(marker), entry.take(120))
            assertFalse(entry.contains(receiver), entry.take(120))
        }
        session.close()
    }

    @Test
    fun `the latest version endpoint returns a typed body`() = e2e {
        val response = client.get("/api/v1/latest-version")

        // Karisik tipli `mapOf(...)` yaniti calisma zamaninda serialize
        // edilemez ve endpoint 500 dondururdu.
        assertEquals(HttpStatusCode.OK, response.status)
        val body = json.parseToJsonElement(response.bodyAsText()) as JsonObject
        assertTrue(body["versionCode"]?.jsonPrimitive?.content?.toIntOrNull() != null)
        assertTrue(body.containsKey("mandatory"))
    }

    // ---------------- Kimlik yasam dongusu ----------------

    @Test
    fun `logout revokes every token of the account`() = e2e {
        val (user, token) = newAccount()
        assertEquals(
            HttpStatusCode.OK,
            client.get("/api/v1/directory/snapshot") {
                header("Authorization", "Bearer $token")
            }.status,
        )

        val logout = client.post("/api/v1/auth/logout") {
            header("Authorization", "Bearer $token")
        }

        assertEquals(HttpStatusCode.OK, logout.status)
        // Iptal PostgreSQL'de tutulur; Redis restart'i geri getiremez.
        assertEquals(
            HttpStatusCode.Unauthorized,
            client.get("/api/v1/directory/snapshot") {
                header("Authorization", "Bearer $token")
            }.status,
        )
    }

    @Test
    fun `logout without a credential is refused`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.post("/api/v1/auth/logout").status)
    }

    @Test
    fun `a refresh token rotates and the old one stops working`() = e2e {
        val (user, _) = newAccount()
        val refresh = AuthService.issueRefreshToken(user)

        val first = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$refresh"}""")
        }
        assertEquals(HttpStatusCode.OK, first.status)

        // Ilk yanit kaybolmus olabilir (QA 2026-10-12 R1): kisa pencerede
        // ayni token bir kez daha kabul edilir.
        val lostResponseRetry = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$refresh"}""")
        }
        assertEquals(HttpStatusCode.OK, lostResponseRetry.status)

        // Ucuncu kullanim: calinmis bir refresh token sonsuza kadar gecerli
        // olamaz.
        val replay = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$refresh"}""")
        }
        assertEquals(HttpStatusCode.Unauthorized, replay.status)
    }

    @Test
    fun `an old refresh token is refused once its successor has been used`() = e2e {
        val (user, _) = newAccount()
        val refresh = AuthService.issueRefreshToken(user)

        val first = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$refresh"}""")
        }
        assertEquals(HttpStatusCode.OK, first.status)
        val successor = Regex("\"refreshToken\"\\s*:\\s*\"([^\"]+)\"")
            .find(first.bodyAsText())!!.groupValues[1]
        val second = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$successor"}""")
        }
        assertEquals(HttpStatusCode.OK, second.status)

        // Istemci yeni token'i aldi ve kullandi; yanit kaybi yok, eski
        // token'in tekrar gelmesi yeniden kullanimdir.
        val replay = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$refresh"}""")
        }
        assertEquals(HttpStatusCode.Unauthorized, replay.status)
    }

    @Test
    fun `a forged refresh token is refused`() = e2e {
        val response = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"not.a.token"}""")
        }

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `an access token cannot be used as a refresh token`() = e2e {
        val (_, access) = newAccount()

        val response = client.post("/api/v1/auth/refresh") {
            header("Content-Type", "application/json")
            setBody("""{"refreshToken":"$access"}""")
        }

        // Token turleri ayrilmazsa kisa omurlu bir access token'dan
        // sinirsiz yenileme uretilebilirdi.
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `account deletion is idempotent and ends the credential`() = e2e {
        val (user, token) = newAccount()

        val first = client.post("/api/v1/account/delete") {
            header("Authorization", "Bearer $token")
        }
        assertEquals(HttpStatusCode.OK, first.status)
        assertTrue(first.bodyAsText().contains("deleted"))

        // Kalici kayit gittigi anda hesap authenticate edilemez.
        val second = client.post("/api/v1/account/delete") {
            header("Authorization", "Bearer $token")
        }
        assertEquals(HttpStatusCode.Unauthorized, second.status)
        assertFalse(userRegistry.exists(user))
    }

    @Test
    fun `deleting without a credential is refused`() = e2e {
        assertEquals(HttpStatusCode.Unauthorized, client.post("/api/v1/account/delete").status)
    }

    // ---------------- Anahtar dagitimi ----------------

    @Test
    fun `the served bundle carries only the Olm shape`() = e2e {
        // Kullanici token'iyla acik: tek prekey yolu bu ve peer bundle'i
        // cekemeyen istemci oturum kuramaz. libsignal alanlari V31 ile
        // kalkti; yanitta eski kimlik yuzeyi bulunmamali.
        clearRateLimits()
        val (owner, ownerToken) = newAccount()
        val (_, peerToken) = newAccount()
        assertEquals(HttpStatusCode.OK, uploadOlmBundle(ownerToken).status)

        val fetched = client.get("/api/v1/users/$owner/prekeys") {
            header("Authorization", "Bearer $peerToken")
        }

        assertEquals(HttpStatusCode.OK, fetched.status)
        val body = Json.parseToJsonElement(fetched.bodyAsText()).jsonObject
        for (field in listOf("identityPublicKey", "registrationId", "signedPreKey", "oneTimePreKey")) {
            assertFalse(body.containsKey(field), "$field hala servis ediliyor")
        }
        assertTrue(body.containsKey("identityKey"))
        assertTrue(body.containsKey("oneTimeKey"))
    }

    @Test
    fun `fetching a bundle requires a credential`() = e2e {
        val (owner, _) = newAccount()

        assertEquals(
            HttpStatusCode.Unauthorized,
            client.get("/api/v1/users/$owner/prekeys").status,
        )
    }

    @Test
    fun `the bundle route accepts a user token`() = e2e {
        // Bu test eskiden 403 bekliyordu: route `requireServicePrincipal`
        // ardindaydi ve kullanici token'ini kabul etmiyordu. Tek prekey
        // yolu haline gelince o davranis bir istemcinin peer bundle'i
        // cekmesini, dolayisiyla oturum kurmasini tumuyle imkansiz kilardi.
        //
        // Kabul etmenin bedeli, cagiranin hedefin anahtari olup olmadigini
        // ogrenebilmesi. Bu bedel kacinilmaz: bundle cekebilen her yol bunu
        // soyler. Siniri rate limit kuruyor (asagida ayri test), erisimi
        // tumuyle kapatmak degil.
        val (owner, ownerToken) = newAccount()
        val (_, peerToken) = newAccount()
        uploadOlmBundle(ownerToken)

        val response = client.get("/api/v1/users/$owner/prekeys") {
            header("Authorization", "Bearer $peerToken")
        }

        assertEquals(HttpStatusCode.OK, response.status)
    }

    @Test
    fun `bundle request for a non-UUID id is rejected before the database`() = e2e {
        // QA 2026-10-13 T7: istemci yerel sistem mesajinin gondericisi
        // "SYSTEM" icin bundle istedi; sunucu Postgres hatasiyla 500 donuyordu.
        clearRateLimits()
        val (_, token) = newAccount()
        val response = client.get("/api/v1/users/SYSTEM/prekeys") {
            header("Authorization", "Bearer $token")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `publishing Olm keys twice succeeds the second time`() = e2e {
        // Istemci her on plana gecisde `publishIfNeeded()` cagiriyor. Ilk
        // yayindan sonraki her cagri ayni kimligi, bos bir anahtar listesi
        // ve fallback'siz bir govde gonderir (anahtarlar yayinlanmis
        // isaretlendigi ve fallback donus penceresi dolmadigi icin).
        // Bu yolun basarisiz olmasi, istemciyi sonu gelmeyen bir yeniden
        // deneme dongusune sokar.
        clearRateLimits()
        val (_, token) = newAccount()
        val encoder = java.util.Base64.getEncoder()
        val identity = encoder.encodeToString(ByteArray(32) { 5 })
        val signing = encoder.encodeToString(ByteArray(32) { 6 })

        uploadOlmBundle(token)

        // Ikinci yayin: yalniz kimlik, anahtar yok, fallback yok.
        val second = client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"olmIdentityKey":"$identity","olmSigningKey":"$signing",""" +
                    """"olmOneTimeKeys":[]}""",
            )
        }

        assertEquals(HttpStatusCode.OK, second.status, second.bodyAsText())
    }

    @Test
    fun `re-sending the identical Olm bundle is accepted`() = e2e {
        // Ag kopan bir istemci ayni govdeyi aynen tekrarlar; bu idempotent
        // olmak zorunda.
        clearRateLimits()
        val (_, token) = newAccount()

        uploadOlmBundle(token)
        uploadOlmBundle(token)

        val status = client.get("/api/v1/prekeys/status") {
            header("Authorization", "Bearer $token")
        }
        assertEquals(HttpStatusCode.OK, status.status)
    }

    @Test
    fun `the bundle response carries the protocol version on the wire`() = e2e {
        // `protocolVersion` alanina varsayilan deger verildiginde
        // kotlinx.serialization onu JSON'a HIC yazmiyordu (`encodeDefaults`
        // varsayilan olarak false). Istemci surum alanini goremeyince
        // bundle'i reddediyor ve mesaj gonderilemiyordu. Alanin kabloda
        // gercekten bulundugu dogrulanmali; tip imzasina bakmak yetmez.
        clearRateLimits()
        val (owner, ownerToken) = newAccount()
        val (_, peerToken) = newAccount()
        uploadOlmBundle(ownerToken)

        val response = client.get("/api/v1/users/$owner/prekeys") {
            header("Authorization", "Bearer $peerToken")
        }

        assertEquals(HttpStatusCode.OK, response.status)
        val body = Json.parseToJsonElement(response.bodyAsText()).jsonObject
        assertTrue(body.containsKey("protocolVersion"), response.bodyAsText())
        assertEquals(
            OLM_BUNDLE_PROTOCOL_VERSION,
            body["protocolVersion"]!!.jsonPrimitive.int,
        )
        // Olm alanlari da kabloda olmali.
        for (field in listOf("identityKey", "signingKey")) {
            assertTrue(body.containsKey(field), "$field eksik: ${response.bodyAsText()}")
        }
    }

    @Test
    fun `an account without any bundle has none to hand out`() = e2e {
        val (owner, _) = newAccount()
        val (_, peerToken) = newAccount()

        val response = client.get("/api/v1/users/$owner/prekeys") {
            header("Authorization", "Bearer $peerToken")
        }

        assertEquals(HttpStatusCode.NotFound, response.status)
    }

    @Test
    fun `the own directory token can be refreshed by the account itself`() = e2e {
        val (user, token) = newAccount()
        val phoneHash = java.security.MessageDigest.getInstance("SHA-256")
            .digest("+905550001122".toByteArray())
            .joinToString("") { "%02x".format(it) }

        val response = client.post("/api/v1/users/directory-token") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"directoryToken":"${PrivateDirectory.oprf.tokenForPhoneHash(phoneHash)}"}""",
            )
        }

        assertEquals(HttpStatusCode.OK, response.status)
        assertTrue(response.bodyAsText().contains("keyId"))
    }

    @Test
    fun `a malformed directory token is refused`() = e2e {
        val (_, token) = newAccount()

        val response = client.post("/api/v1/users/directory-token") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody("""{"directoryToken":"not-a-token"}""")
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    // ---------------- Kayit ----------------

    /** IP rate limitleri testler arasinda paylasilir; kasitli olarak sifirlanir. */
    private fun clearRateLimits() {
        RedisManager.use { jedis ->
            val keys = jedis.keys("ratelimit_v2:*")
            if (keys.isNotEmpty()) jedis.del(*keys.toTypedArray())
        }
    }

    private fun phoneHash(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun registerBody(
        userId: String = UUID.randomUUID().toString(),
        token: String?,
    ): String {
        val tokenField = if (token == null) "" else ""","registrationToken":"$token""""
        return """{"userId":"$userId"$tokenField}"""
    }

    @Test
    fun `registration without a grant is refused`() = e2e {
        clearRateLimits()
        val response = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(registerBody(token = null))
        }

        // E-posta OTP'si olmadan hesap acilamaz; test ortamina ozel bir
        // bypass da yoktur.
        assertEquals(HttpStatusCode.Forbidden, response.status)
    }

    @Test
    fun `registration with a forged grant is refused`() = e2e {
        clearRateLimits()
        val response = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(registerBody(token = "not.a.grant"))
        }

        assertEquals(HttpStatusCode.Forbidden, response.status)
    }

    @Test
    fun `a valid grant creates the account exactly once`() = e2e {
        clearRateLimits()
        val grant = AuthService.issueRegistrationToken()
        val userId = UUID.randomUUID().toString()
        val body = registerBody(userId = userId, token = grant)

        val first = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(body)
        }
        assertEquals(HttpStatusCode.OK, first.status)
        assertTrue(first.bodyAsText().contains(userId))
        assertTrue(userRegistry.exists(userId))

        // Ayni grant ikinci kez kullanilamaz.
        val replay = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(registerBody(token = grant))
        }
        assertEquals(HttpStatusCode.Forbidden, replay.status)
    }

    @Test
    fun `device reauth endpoints issue a challenge and refuse a bad proof`() = e2e {
        clearRateLimits()
        val challenge = client.post("/api/v1/auth/device/challenge") {
            header("Content-Type", "application/json")
            setBody("{}")
        }
        assertEquals(HttpStatusCode.OK, challenge.status)
        assertEquals("no-store", challenge.headers["Cache-Control"])
        val body = challenge.bodyAsText()
        assertTrue(body.contains("\"challengeId\"") && body.contains("\"nonce\""))

        val challengeId = Regex("\"challengeId\":\"([^\"]+)\"").find(body)!!.groupValues[1]
        val rejected = client.post("/api/v1/auth/device/verify") {
            header("Content-Type", "application/json")
            setBody("""{"challengeId":"$challengeId","refreshToken":"not.a.token","signature":"AAAA"}""")
        }
        assertEquals(HttpStatusCode.Unauthorized, rejected.status)
        assertFalse(rejected.bodyAsText().contains("accessToken"))
    }

    @Test
    fun `registration binds the verified email only when the user asks`() = e2e {
        clearRateLimits()
        val email = "e2e-${UUID.randomUUID()}@example.com"

        val declined = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(
                """{"userId":"${UUID.randomUUID()}","registrationToken":"${AuthService.issueRegistrationToken(email)}"}""",
            )
        }
        assertEquals(HttpStatusCode.OK, declined.status)
        // Varsayilan degerler yazilmaz; eksik alan "bagli degil" demektir.
        assertFalse(declined.bodyAsText().contains("\"recoveryEmailBound\":true"))

        val accepted = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(
                """{"userId":"${UUID.randomUUID()}","registrationToken":"${AuthService.issueRegistrationToken(email)}","bindRecoveryEmail":true}""",
            )
        }
        assertEquals(HttpStatusCode.OK, accepted.status)
        assertTrue(accepted.bodyAsText().contains("\"recoveryEmailBound\":true"))
    }

    @Test
    fun `the registration endpoint refuses deterministic phone hashes`() = e2e {
        clearRateLimits()
        val grant = AuthService.issueRegistrationToken()
        val response = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(
                """{"userId":"${UUID.randomUUID()}","phoneHash":"${phoneHash("+905559998877")}","registrationToken":"$grant"}""",
            )
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertFalse(response.bodyAsText().contains("accessToken"))
    }

    @Test
    fun `a malformed registration is refused`() = e2e {
        clearRateLimits()
        val grant = AuthService.issueRegistrationToken()

        val response = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody("""{"userId":"not-a-uuid","registrationToken":"$grant"}""")
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `the issued credentials work immediately`() = e2e {
        clearRateLimits()
        val grant = AuthService.issueRegistrationToken()
        val userId = UUID.randomUUID().toString()

        val registered = client.post("/api/v1/users/register") {
            header("Content-Type", "application/json")
            setBody(registerBody(userId = userId, token = grant))
        }
        val body = json.parseToJsonElement(registered.bodyAsText()) as JsonObject
        val accessToken = body["accessToken"]!!.jsonPrimitive.content

        val authorized = client.get("/api/v1/directory/snapshot") {
            header("Authorization", "Bearer $accessToken")
        }

        assertEquals(HttpStatusCode.OK, authorized.status)
    }

    @Test
    fun `registration is rate limited per address`() = e2e {
        clearRateLimits()

        val statuses = (1..7).map {
            client.post("/api/v1/users/register") {
                header("Content-Type", "application/json")
                setBody(registerBody(token = AuthService.issueRegistrationToken()))
            }.status
        }

        // Sinirsiz kayit, hesap ciftligi kurmayi ucuzlastirirdi.
        assertTrue(statuses.contains(HttpStatusCode.TooManyRequests), statuses.toString())
    }

    // ---------------- Guvenlik basliklari (harici tarama bulgusu) ----------------

    @Test
    fun `every response carries the security headers`() = e2e {
        val response = client.get("/health")

        assertEquals("nosniff", response.headers["X-Content-Type-Options"])
        assertEquals("DENY", response.headers["X-Frame-Options"])
        assertEquals("no-referrer", response.headers["Referrer-Policy"])
        assertEquals("no-store", response.headers["Cache-Control"])
        assertTrue(
            response.headers["Content-Security-Policy"]?.contains("frame-ancestors 'none'") == true,
            response.headers["Content-Security-Policy"],
        )
    }

    @Test
    fun `an unauthorized response also carries the security headers`() = e2e {
        // Basliklar isleyiciden once eklenir; 401 yolu da korunmalidir.
        val response = client.get("/api/v1/directory/snapshot")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertEquals("nosniff", response.headers["X-Content-Type-Options"])
        assertEquals("no-store", response.headers["Cache-Control"])
    }

    @Test
    fun `a sensitive credential response is marked no-store`() = e2e {
        val (_, token) = newAccount()

        // TURN kimlik bilgileri ara proxy'lerde onbelleklenmemeli.
        val response = client.get("/api/v1/ice/config") {
            header("Authorization", "Bearer $token")
        }

        assertEquals("no-store", response.headers["Cache-Control"])
    }

    // ---------------- Prekey rate limit + validation (whitebox bulgu) ----------------

    private suspend fun ApplicationTestBuilder.uploadOlmBundle(
        token: String,
        otpkCount: Int = 5,
        firstKeyId: Int = 1,
    ): HttpResponse {
        val encoder = java.util.Base64.getEncoder()
        val identity = encoder.encodeToString(ByteArray(32) { 5 })
        val signing = encoder.encodeToString(ByteArray(32) { 6 })
        val fallback = encoder.encodeToString(ByteArray(32) { 8 })
        val signature = encoder.encodeToString(ByteArray(64) { 7 })
        val otpks = (firstKeyId until firstKeyId + otpkCount).joinToString(",") {
            """{"keyId":"k$it","publicKey":"$identity"}"""
        }
        return client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"olmIdentityKey":"$identity","olmSigningKey":"$signing",""" +
                    """"olmOneTimeKeys":[$otpks],"olmFallbackKey":"$fallback",""" +
                    """"olmFallbackKeySignature":"$signature"}""",
            )
        }
    }

    @Test
    fun `a different Olm identity is answered with identity_recovery_required`() = e2e {
        // QA 2026-10-13 T5 madde 3: istemci kimlik sapmasini genel 400'den
        // ayirt edemiyor ve kullaniciya hicbir sey soyleyemiyordu.
        clearRateLimits()
        val (_, token) = newAccount()
        uploadOlmBundle(token)
        val encoder = java.util.Base64.getEncoder()
        val other = encoder.encodeToString(ByteArray(32) { 9 })
        val signing = encoder.encodeToString(ByteArray(32) { 6 })
        val response = client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"olmIdentityKey":"$other","olmSigningKey":"$signing",""" +
                    """"olmOneTimeKeys":[]}""",
            )
        }
        assertEquals(HttpStatusCode.Conflict, response.status)
        assertTrue(response.bodyAsText().contains("identity_recovery_required"))
    }

    @Test
    fun `abuse report route accepts a valid report and guards admin access`() = e2e {
        // Store-readiness devri: servis ve DB testleri vardi, route seviyesi
        // (kimlik, govde siniri, ret kodlari, admin gizliligi) sinanmiyordu.
        clearRateLimits()
        val (reporter, token) = newAccount()
        val (target, _) = newAccount()
        fun body(targets: String) =
            """{"kind":"user","targetUserIds":[$targets],"reason":"spam"}"""

        val anonymous = client.post("/api/v1/reports") {
            header("Content-Type", "application/json")
            setBody(body("\"$target\""))
        }
        assertEquals(HttpStatusCode.Unauthorized, anonymous.status)

        val accepted = client.post("/api/v1/reports") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(body("\"$target\""))
        }
        assertEquals(HttpStatusCode.Accepted, accepted.status)

        val self = client.post("/api/v1/reports") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(body("\"$reporter\""))
        }
        assertEquals(HttpStatusCode.BadRequest, self.status)

        val unknownField = client.post("/api/v1/reports") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"kind":"user","targetUserIds":["$target"],"reason":"spam",""" +
                    """"content":"mesaj metni"}""",
            )
        }
        assertEquals(HttpStatusCode.BadRequest, unknownField.status)

        // Admin ucu kullanici token'iyla varligini bile acik etmez.
        val admin = client.get("/api/v1/admin/reports") {
            header("Authorization", "Bearer $token")
        }
        assertEquals(HttpStatusCode.NotFound, admin.status)
    }

    @Test
    fun `prekey fetch is rate limited per caller`() = e2e {
        clearRateLimits()
        val (owner, ownerToken) = newAccount()
        val (_, fetcherToken) = newAccount()
        uploadOlmBundle(ownerToken, otpkCount = 5)

        // 120/saat sinir; ustunde 429 gelmeli, aksi halde havuz bosaltilabilir.
        var got429 = false
        for (i in 1..140) {
            val r = client.get("/api/v1/users/$owner/prekeys") {
                header("Authorization", "Bearer $fetcherToken")
            }
            if (r.status == HttpStatusCode.TooManyRequests) { got429 = true; break }
        }
        assertTrue(got429, "prekey fetch sinirsiz")
    }

    @Test
    fun `prekey writes are rate limited`() = e2e {
        clearRateLimits()
        val (_, token) = newAccount()

        var got429 = false
        for (i in 1..40) {
            val r = uploadOlmBundle(token, otpkCount = 1, firstKeyId = i)
            if (r.status == HttpStatusCode.TooManyRequests) { got429 = true; break }
        }
        assertTrue(got429, "prekey yazma sinirsiz")
    }

    @Test
    fun `the stored one-time prekey pool is capped per account`() = e2e {
        clearRateLimits()
        val (_, token) = newAccount()
        // Tek istekte MAX_ONE_TIME_PREKEYS sinirini asamayiz; 100'luk
        // yuklemelerle havuz tavanini zorla.
        var poolFull = false
        for (batch in 0 until 12) {
            val r = uploadOlmBundle(token, otpkCount = 100, firstKeyId = batch * 100 + 1)
            if (r.status == HttpStatusCode.Conflict) {
                assertTrue(r.bodyAsText().contains("prekey_pool_full"))
                poolFull = true
                break
            }
        }
        assertTrue(poolFull, "havuz tavani yok")
    }

    // ---------------- auth/refresh rate limit + ek basliklar (deep-scan bulgu) ----------------

    @Test
    fun `auth refresh is rate limited per address`() = e2e {
        clearRateLimits()

        // Onceden hic 429 donmuyordu; simdi IP basina sinir var.
        var got429 = false
        for (i in 1..40) {
            val r = client.post("/api/v1/auth/refresh") {
                header("Content-Type", "application/json")
                setBody("""{"refreshToken":"bogus-$i"}""")
            }
            if (r.status == HttpStatusCode.TooManyRequests) { got429 = true; break }
        }
        assertTrue(got429, "auth/refresh sinirsiz")
    }

    @Test
    fun `responses carry the supplementary isolation headers`() = e2e {
        val response = client.get("/health")

        assertEquals("same-origin", response.headers["Cross-Origin-Opener-Policy"])
        assertEquals("require-corp", response.headers["Cross-Origin-Embedder-Policy"])
        assertEquals("same-origin", response.headers["Cross-Origin-Resource-Policy"])
        assertEquals("none", response.headers["X-Permitted-Cross-Domain-Policies"])
        assertTrue(response.headers["Permissions-Policy"]?.contains("camera=()") == true)
    }
}
