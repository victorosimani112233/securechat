package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.client.plugins.websocket.WebSockets as ClientWebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import java.util.UUID
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
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
        application { signalingModule(connectionManager, userRegistry, fcmTokenStore, fcmPushSender) }
    }

    private fun e2e(block: suspend ApplicationTestBuilder.() -> Unit) = testApplication {
        configureServer()
        block()
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

    // ---------------- Prekey ve SFU yetkisi ----------------

    @Test
    fun `a prekey upload with too many one time keys is refused`() = e2e {
        val entries = (1..MAX_ONE_TIME_PREKEYS + 1).joinToString(",") {
            """{"keyId":$it,"publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"""
        }
        val response = client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $aliceToken")
            header("Content-Type", "application/json")
            setBody(
                """{"identityPublicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",""" +
                    """"registrationId":1234,"signedPreKeyId":1,""" +
                    """"signedPreKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",""" +
                    """"signedPreKeySignature":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",""" +
                    """"oneTimePreKeys":[$entries]}""",
            )
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertTrue(response.bodyAsText().contains("invalid_prekey_material"))
    }

    @Test
    fun `a prekey upload without a credential is refused`() = e2e {
        val response = client.post("/api/v1/prekeys/upload") {
            header("Content-Type", "application/json")
            setBody("""{"identityPublicKey":"AA","registrationId":1,"signedPreKeyId":1,""" +
                """"signedPreKey":"AA","signedPreKeySignature":"AA","oneTimePreKeys":[]}""")
        }

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `sfu room details need an active call membership not just a credential`() = e2e {
        val response = client.get("/api/v1/sfu/room/${UUID.randomUUID()}") {
            header("Authorization", "Bearer $aliceToken")
        }

        // Kimlik dogrulamasi tek basina yetki degildir.
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
            jedis.zcard(ServerPrivacy.queueKey("message", strangerId))
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
        senderSession.close()
        receiverSession.close()
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
            jedis.zrange(ServerPrivacy.queueKey("message", receiver), 0, -1)
        } ?: emptySet()
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

        // Ayni token'in ikinci kullanimi: calinmis bir refresh token
        // sonsuza kadar gecerli olamaz.
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
    fun `a bundle can be uploaded and fetched by another account`() = e2e {
        val (owner, ownerToken) = newAccount()
        val (peer, peerToken) = newAccount()
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(33) { 5 })
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(64) { 6 })

        val upload = client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $ownerToken")
            header("Content-Type", "application/json")
            setBody(
                """{"identityPublicKey":"$key","registrationId":777,"signedPreKeyId":3,""" +
                    """"signedPreKey":"$key","signedPreKeySignature":"$signature",""" +
                    """"oneTimePreKeys":[{"keyId":1,"publicKey":"$key"}]}""",
            )
        }
        assertEquals(HttpStatusCode.OK, upload.status)

        val fetched = client.get("/api/v1/users/$owner/prekeys") {
            header("Authorization", "Bearer $peerToken")
        }

        assertEquals(HttpStatusCode.OK, fetched.status)
        val body = json.parseToJsonElement(fetched.bodyAsText()) as JsonObject
        assertTrue(fetched.bodyAsText().contains("777"))
        assertTrue(body.isNotEmpty())
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
    fun `an account without a bundle has none to hand out`() = e2e {
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

    private suspend fun ApplicationTestBuilder.uploadBundle(token: String, otpkCount: Int = 5) {
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(33) { 5 })
        val sig = java.util.Base64.getEncoder().encodeToString(ByteArray(64) { 6 })
        val otpks = (1..otpkCount).joinToString(",") { """{"keyId":$it,"publicKey":"$key"}""" }
        client.post("/api/v1/prekeys/upload") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody(
                """{"identityPublicKey":"$key","registrationId":555,"signedPreKeyId":1,""" +
                    """"signedPreKey":"$key","signedPreKeySignature":"$sig",""" +
                    """"oneTimePreKeys":[$otpks]}""",
            )
        }
    }

    @Test
    fun `prekey fetch is rate limited per caller`() = e2e {
        clearRateLimits()
        val (owner, ownerToken) = newAccount()
        val (_, fetcherToken) = newAccount()
        uploadBundle(ownerToken, otpkCount = 5)

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
    fun `prekey refresh validates key material`() = e2e {
        clearRateLimits()
        val (_, token) = newAccount()

        // Tekrarli keyId ve bozuk anahtar reddedilmeli (refresh onceden atliyordu).
        val dup = client.post("/api/v1/prekeys/refresh") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody("""[{"keyId":1,"publicKey":"AAAA"},{"keyId":1,"publicKey":"AAAA"}]""")
        }
        assertEquals(HttpStatusCode.BadRequest, dup.status)

        val badKey = client.post("/api/v1/prekeys/refresh") {
            header("Authorization", "Bearer $token")
            header("Content-Type", "application/json")
            setBody("""[{"keyId":2,"publicKey":"!!!not-base64!!!"}]""")
        }
        assertEquals(HttpStatusCode.BadRequest, badKey.status)
    }

    @Test
    fun `prekey writes are rate limited`() = e2e {
        clearRateLimits()
        val (_, token) = newAccount()
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(33) { 7 })

        var got429 = false
        for (i in 1..40) {
            val r = client.post("/api/v1/prekeys/refresh") {
                header("Authorization", "Bearer $token")
                header("Content-Type", "application/json")
                setBody("""[{"keyId":$i,"publicKey":"$key"}]""")
            }
            if (r.status == HttpStatusCode.TooManyRequests) { got429 = true; break }
        }
        assertTrue(got429, "prekey yazma sinirsiz")
    }

    @Test
    fun `the stored one-time prekey pool is capped per account`() = e2e {
        clearRateLimits()
        val (_, token) = newAccount()
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(33) { 8 })
        // Tavanin uzerinde tek batch: Conflict donmeli.
        val over = (1..MAX_STORED_ONE_TIME_PREKEYS + 1).joinToString(",") {
            """{"keyId":$it,"publicKey":"$key"}"""
        }
        // Once gecerli sayida (MAX_ONE_TIME_PREKEYS) yukle, sonra tavani zorla.
        // Tek istekte MAX_ONE_TIME_PREKEYS sinirini asamayiz; birden fazla refresh ile doldur.
        var poolFull = false
        for (batch in 0 until 12) {
            val start = batch * 100 + 1
            val entries = (start until start + 100).joinToString(",") {
                """{"keyId":$it,"publicKey":"$key"}"""
            }
            val r = client.post("/api/v1/prekeys/refresh") {
                header("Authorization", "Bearer $token")
                header("Content-Type", "application/json")
                setBody("[$entries]")
            }
            if (r.status == HttpStatusCode.Conflict) { poolFull = true; break }
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
