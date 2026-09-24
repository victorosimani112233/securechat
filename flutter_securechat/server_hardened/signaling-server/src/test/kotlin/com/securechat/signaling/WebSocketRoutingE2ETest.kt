package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.client.plugins.websocket.WebSockets as ClientWebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.client.request.header
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import io.ktor.websocket.Frame
import io.ktor.websocket.WebSocketSession
import io.ktor.websocket.close
import io.ktor.websocket.readText
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
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
 * WebSocket mesaj yonlendiricisinin dallari, gercek motorla.
 *
 * Yonlendirici istemcinin gonderdigi her cerceve turunu ayri ayri ele alir;
 * her dal bir yetki ya da gizlilik karari icerir. Burada her dal bir
 * istemcinin gordugu bicimde surulur: kabul edilen, sessizce dusurulen ve
 * baglantiyi kapatan yollar.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class WebSocketRoutingE2ETest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_ws_e2e")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private lateinit var connectionManager: ConnectionManager
    private lateinit var userRegistry: UserRegistry
    private lateinit var fcmTokenStore: FcmTokenStore
    private lateinit var fcmPushSender: FcmPushSender
    private val json = Json { ignoreUnknownKeys = true }

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; WS e2e atlandi")
        postgres.start()
        redis.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        ServerPrivacy.initialize()
        PrivateDirectory.initialize()
        MetricsAccess.initialize()
        AuthService.initialize()
        CredentialState.initialize()
        fcmTokenStore = FcmTokenStore()
        fcmPushSender = FcmPushSender(fcmTokenStore)
        connectionManager = ConnectionManager(fcmPushSender)
        userRegistry = UserRegistry()
        PrivacyRetentionWorker.runOnce()
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { RedisManager.close() }
        runCatching { Database.close() }
        redis.stop()
        postgres.stop()
    }

    private fun sha256Hex(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun newAccount(): Pair<String, String> {
        val userId = UUID.randomUUID().toString()
        userRegistry.registerUser(userId)
        return userId to AuthService.issueToken(userId)
    }

    /** 43 karakterlik opak grup token'i; sunucu grup uyeligini bilmez. */
    private fun groupToken(): String =
        "group-" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(24) { (it * 7).toByte() })
            .let { it }
            .let { Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { b -> (b + it.length).toByte() }) }

    private fun opaqueGroupId(): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })

    private fun e2e(block: suspend ApplicationTestBuilder.() -> Unit) = testApplication {
        application { signalingModule(connectionManager, userRegistry, fcmTokenStore, fcmPushSender) }
        block()
    }

    private suspend fun ApplicationTestBuilder.connect(
        userId: String,
        token: String,
    ): WebSocketSession {
        val session = createClient { install(ClientWebSockets) }
            .webSocketSession("/ws?userId=$userId") { header("Authorization", "Bearer $token") }
        withTimeoutOrNull(5_000) {
            while (!connectionManager.isOnline(userId)) delay(20)
        }
        return session
    }

    /** Belirli bir metni tasiyan ilk cerceve; yoksa null. */
    private suspend fun WebSocketSession.awaitFrame(
        marker: String,
        timeoutMillis: Long = 4_000,
    ): String? = withTimeoutOrNull(timeoutMillis) {
        var found: String? = null
        while (found == null) {
            val frame = incoming.receiveCatching().getOrNull() ?: break
            val text = (frame as? Frame.Text)?.readText() ?: continue
            if (text.contains(marker)) found = text
        }
        found
    }

    // ---------------- Presence ----------------

    @Test
    fun `presence subscribe to an unknown account is refused`() = e2e {
        val (user, token) = newAccount()
        val session = connect(user, token)
        val before = connectionManager.subscriptionCount(user)

        session.send(
            Frame.Text(
                """{"type":"presence_subscribe","recipientId":"${UUID.randomUUID()}"}""",
            ),
        )
        delay(400)

        // Uydurulmus bir hedef icin kalici harita girdisi olusmamali.
        assertEquals(before, connectionManager.subscriptionCount(user))
        session.close()
    }

    @Test
    fun `presence subscribe and unsubscribe move the subscription count`() = e2e {
        val (watcher, watcherToken) = newAccount()
        val (target, _) = newAccount()
        val session = connect(watcher, watcherToken)

        session.send(Frame.Text("""{"type":"presence_subscribe","recipientId":"$target"}"""))
        withTimeoutOrNull(4_000) {
            while (connectionManager.subscriptionCount(watcher) == 0) delay(20)
        }
        assertEquals(1, connectionManager.subscriptionCount(watcher))

        session.send(Frame.Text("""{"type":"presence_unsubscribe","recipientId":"$target"}"""))
        withTimeoutOrNull(4_000) {
            while (connectionManager.subscriptionCount(watcher) > 0) delay(20)
        }
        assertEquals(0, connectionManager.subscriptionCount(watcher))
        session.close()
    }

    @Test
    fun `a presence update marks the account online`() = e2e {
        val (user, token) = newAccount()
        val session = connect(user, token)

        session.send(Frame.Text("""{"type":"presence_update","isOnline":true}"""))
        delay(300)

        assertTrue(connectionManager.isOnline(user))
        session.close()
    }

    // ---------------- Fail-closed gizlilik dallari ----------------

    @Test
    fun `legacy plaintext chat control frames are dropped`() = e2e {
        val (sender, senderToken) = newAccount()
        val (receiver, receiverToken) = newAccount()
        val senderSession = connect(sender, senderToken)
        val receiverSession = connect(receiver, receiverToken)

        for (type in PLAINTEXT_CHAT_CONTROL_TYPES) {
            val marker = "MARK-$type"
            senderSession.send(
                Frame.Text("""{"type":"$type","recipientId":"$receiver","messageId":"$marker"}"""),
            )
        }

        // Bunlar sosyal grafigi ve davranis zaman cizelgesini acar; hardened
        // istemci ayni bilgiyi sifreli zarf icinde tasir.
        assertNull(receiverSession.awaitFrame("MARK-", timeoutMillis = 1_500))
        senderSession.close()
        receiverSession.close()
    }

    @Test
    fun `a server only frame type cannot be injected by a client`() = e2e {
        val (sender, senderToken) = newAccount()
        val (receiver, receiverToken) = newAccount()
        val senderSession = connect(sender, senderToken)
        val receiverSession = connect(receiver, receiverToken)

        senderSession.send(
            Frame.Text(
                """{"type":"$SERVICE_MESSAGE_ACK_TYPE","recipientId":"$receiver",""" +
                    """"messageId":"FAKE-ACK"}""",
            ),
        )

        // Sahte bir ACK botun in-flight kaydini erken sildirebilirdi.
        assertNull(receiverSession.awaitFrame("FAKE-ACK", timeoutMillis = 1_500))
        senderSession.close()
        receiverSession.close()
    }

    @Test
    fun `sentinel recipients are never routed`() = e2e {
        val (sender, senderToken) = newAccount()
        val session = connect(sender, senderToken)

        for (sentinel in listOf("SYSTEM", "server", "broadcast")) {
            session.send(
                Frame.Text(
                    """{"type":"encrypted_message","recipientId":"$sentinel",""" +
                        """"messageId":"${UUID.randomUUID()}","ciphertext":"AAAA"}""",
                ),
            )
        }
        delay(500)

        // Bunlar protokol yer tutuculari; kalici kuyruk anahtari uretmemeli.
        for (sentinel in listOf("SYSTEM", "server", "broadcast")) {
            val queued = RedisManager.use { jedis ->
                jedis.zcard(ServerPrivacy.queueKey("message", sentinel))
            } ?: 0L
            assertEquals(0L, queued, sentinel)
        }
        assertTrue(connectionManager.isOnline(sender))
        session.close()
    }

    @Test
    fun `a frame that is not json does not kill the session`() = e2e {
        val (user, token) = newAccount()
        val session = connect(user, token)

        session.send(Frame.Text("not json at all"))
        delay(400)

        // Bozuk girdi baglantiyi dusurmemeli; aksi halde tek bozuk cerceve
        // hizmet engeline donusurdu.
        assertTrue(connectionManager.isOnline(user))
        session.close()
    }

    // ---------------- Grup aramasi ----------------

    @Test
    fun `a group call invite with a malformed routing packet is refused`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val session = connect(caller, callerToken)
        val validGroup = opaqueGroupId()

        val rejected = listOf(
            """{"type":"group_call_invite","groupId":"short","callId":"c1","callType":"VOICE","recipientId":"$callee"}""",
            """{"type":"group_call_invite","groupId":"$validGroup","callId":"","callType":"VOICE","recipientId":"$callee"}""",
            """{"type":"group_call_invite","groupId":"$validGroup","callId":"c1","callType":"HOLOGRAM","recipientId":"$callee"}""",
            // Kendine davet: katilimci listesini sisirmek icin kullanilabilirdi.
            """{"type":"group_call_invite","groupId":"$validGroup","callId":"c1","callType":"VOICE","recipientId":"$caller"}""",
            """{"type":"group_call_invite","groupId":"$validGroup","callId":"c1","callType":"VOICE","recipientId":"not-a-uuid"}""",
        )
        for (frame in rejected) session.send(Frame.Text(frame))
        delay(600)

        assertNull(GroupCallSessionStore.get(validGroup))
        session.close()
    }

    @Test
    fun `a valid group call invite starts an ephemeral session`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val session = connect(caller, callerToken)
        val group = opaqueGroupId()
        val callId = UUID.randomUUID().toString()

        session.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"$callId",""" +
                    """"callType":"VOICE","recipientId":"$callee","mediaE2ee":true}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        val active = GroupCallSessionStore.get(group)
        assertNotNull(active)
        assertEquals(caller, active!!.coordinatorId)
        assertEquals(setOf(caller, callee), active.participants.toSet())
        // Koordinatorun invite'i alicinin yetenegi yerine gecemez. Alici
        // authenticated group_call_join_request ile ayrica onaylamalidir.
        assertEquals(setOf(caller), active.mediaE2eeParticipants)
        assertEquals(setOf(caller), active.joinedParticipants)
        assertTrue(active.mediaEndToEndEncrypted)
        assertEquals("MESH", active.mode)
        session.close()
        GroupCallSessionStore.end(group)
    }

    @Test
    fun `socket route reserves eight voice and video invitations before joins`() = e2e {
        for (type in listOf("VOICE", "VIDEO")) {
            val (caller, token) = newAccount()
            val targets = (1..8).map { newAccount().first }
            val socket = connect(caller, token)
            val group = opaqueGroupId()
            val callId = UUID.randomUUID().toString()
            try {
                for (target in targets) {
                    socket.send(Frame.Text("""{"type":"group_call_invite","recipientId":"$target","groupId":"$group","callId":"$callId","callType":"$type","mediaE2ee":true}"""))
                }
                val error = json.parseToJsonElement(requireNotNull(socket.awaitFrame("group_call_error"))).jsonObject
                assertEquals("CAPACITY_REACHED", error["code"]?.jsonPrimitive?.content)
                assertEquals(callId, error["callId"]?.jsonPrimitive?.content)
                val active = requireNotNull(GroupCallSessionStore.get(group))
                assertEquals(8, active.participants.size)
                assertEquals(setOf(caller), active.joinedParticipants)
                assertEquals("MESH", active.mode)
            } finally {
                GroupCallSessionStore.end(group)
                socket.close()
            }
        }
    }

    @Test
    fun `an invite from another coordinator into a live call is refused`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val (attacker, attackerToken) = newAccount()
        val group = opaqueGroupId()
        val callId = UUID.randomUUID().toString()
        val callerSession = connect(caller, callerToken)
        callerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"$callId",""" +
                    """"callType":"VOICE","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        val attackerSession = connect(attacker, attackerToken)
        attackerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"$callId",""" +
                    """"callType":"VOICE","recipientId":"${UUID.randomUUID()}"}""",
            ),
        )
        delay(500)

        // Baglam uyusmazligi: baska bir koordinator aktif aramaya uye ekleyemez.
        assertEquals(setOf(caller, callee), GroupCallSessionStore.get(group)!!.participants.toSet())
        callerSession.close()
        attackerSession.close()
        GroupCallSessionStore.end(group)
    }

    @Test
    fun `a status query from a non participant reveals nothing`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val (stranger, strangerToken) = newAccount()
        val group = opaqueGroupId()
        val callerSession = connect(caller, callerToken)
        callerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"${UUID.randomUUID()}",""" +
                    """"callType":"VOICE","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        val strangerSession = connect(stranger, strangerToken)
        strangerSession.send(Frame.Text("""{"type":"group_call_status_query","groupId":"$group"}"""))
        val response = strangerSession.awaitFrame("group_call_status_response", 2_500)

        // Yanit gelse bile aktif arama bilgisi tasimamali.
        if (response != null) {
            val body = json.parseToJsonElement(response) as JsonObject
            assertEquals("false", body["isActive"]?.jsonPrimitive?.content)
        }
        callerSession.close()
        strangerSession.close()
        GroupCallSessionStore.end(group)
    }

    @Test
    fun `a participant status query returns the live call`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val group = opaqueGroupId()
        val callId = UUID.randomUUID().toString()
        val session = connect(caller, callerToken)
        session.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"$callId",""" +
                    """"callType":"VIDEO","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        session.send(Frame.Text("""{"type":"group_call_status_query","groupId":"$group"}"""))
        val response = session.awaitFrame("group_call_status_response", 4_000)

        assertNotNull(response)
        val body = json.parseToJsonElement(response!!) as JsonObject
        assertEquals("true", body["isActive"]?.jsonPrimitive?.content)
        assertEquals(callId, body["callId"]?.jsonPrimitive?.content)
        session.close()
        GroupCallSessionStore.end(group)
    }

    @Test
    fun `a malformed group id in a status query is refused`() = e2e {
        val (user, token) = newAccount()
        val session = connect(user, token)

        session.send(Frame.Text("""{"type":"group_call_status_query","groupId":"nope"}"""))

        assertNull(session.awaitFrame("group_call_status_response", 1_500))
        session.close()
    }

    @Test
    fun `a join request from outside the call is refused`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val (stranger, strangerToken) = newAccount()
        val group = opaqueGroupId()
        val callerSession = connect(caller, callerToken)
        callerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"${UUID.randomUUID()}",""" +
                    """"callType":"VOICE","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        val strangerSession = connect(stranger, strangerToken)
        strangerSession.send(
            Frame.Text(
                """{"type":"group_call_join_request","groupId":"$group","recipientId":"$caller"}""",
            ),
        )
        delay(500)

        // Cagriya davet edilmemis bir hesap kendini ekleyememeli.
        assertFalse(stranger in GroupCallSessionStore.get(group)!!.participants)
        callerSession.close()
        strangerSession.close()
        GroupCallSessionStore.end(group)
    }

    // ---------------- Kota ----------------

    @Test
    fun `file transfer chunks are charged against the byte quota`() = e2e {
        val (sender, senderToken) = newAccount()
        val (receiver, _) = newAccount()
        val session = connect(sender, senderToken)

        // 5 MB/dk kotasi: 128 KB'lik chunk'lardan 40'tan fazlasi gecmemeli.
        val chunk = "A".repeat(120 * 1024)
        repeat(60) {
            session.send(
                Frame.Text(
                    """{"type":"file_transfer","recipientId":"$receiver",""" +
                        """"messageId":"${UUID.randomUUID()}","ciphertext":"$chunk"}""",
                ),
            )
        }
        delay(1_500)

        val queued = RedisManager.use { jedis ->
            jedis.zcard(ServerPrivacy.queueKey("file", receiver))
        } ?: 0L
        assertTrue(queued in 1..45, "kuyruga giren chunk sayisi: $queued")
        runCatching { session.close() }
    }

    // ---------------- Cagri sonlandirma ----------------

    @Test
    fun `a hangup from a participant notifies the others and ends a two party call`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, calleeToken) = newAccount()
        val group = opaqueGroupId()
        val callId = UUID.randomUUID().toString()
        val callerSession = connect(caller, callerToken)
        val calleeSession = connect(callee, calleeToken)
        callerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"$callId",""" +
                    """"callType":"VOICE","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        callerSession.send(
            Frame.Text(
                """{"type":"call_control","action":"HANGUP","recipientId":"server",""" +
                    """"groupId":"$group"}""",
            ),
        )

        val left = calleeSession.awaitFrame("group_call_member_left", 5_000)
        assertNotNull(left)
        assertTrue(left!!.contains(caller), left)
        // Iki kisilik bir aramada bir taraf cikinca arama biter.
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) != null) delay(20) }
        assertNull(GroupCallSessionStore.get(group))
        callerSession.close()
        calleeSession.close()
    }

    @Test
    fun `a hangup from outside the call is refused`() = e2e {
        val (caller, callerToken) = newAccount()
        val (callee, _) = newAccount()
        val (stranger, strangerToken) = newAccount()
        val group = opaqueGroupId()
        val callerSession = connect(caller, callerToken)
        callerSession.send(
            Frame.Text(
                """{"type":"group_call_invite","groupId":"$group","callId":"${UUID.randomUUID()}",""" +
                    """"callType":"VOICE","recipientId":"$callee"}""",
            ),
        )
        withTimeoutOrNull(4_000) { while (GroupCallSessionStore.get(group) == null) delay(20) }

        val strangerSession = connect(stranger, strangerToken)
        strangerSession.send(
            Frame.Text(
                """{"type":"call_control","action":"HANGUP","recipientId":"server",""" +
                    """"groupId":"$group"}""",
            ),
        )
        delay(600)

        // Yabanci bir hesap baskasinin aramasini sonlandiramaz.
        assertNotNull(GroupCallSessionStore.get(group))
        callerSession.close()
        strangerSession.close()
        GroupCallSessionStore.end(group)
    }

    // ---------------- Reddedilen eski protokoller ----------------

    @Test
    fun `linkable group frames are refused`() = e2e {
        val (sender, senderToken) = newAccount()
        val (receiver, receiverToken) = newAccount()
        val senderSession = connect(sender, senderToken)
        val receiverSession = connect(receiver, receiverToken)

        // Bunlar tek cerceve icinde tam uye listesini ya da kalici grup
        // dizinini aciga cikariyordu.
        senderSession.send(
            Frame.Text("""{"type":"group_directory_sync_v2","recipientId":"$receiver","marker":"SYNC-X"}"""),
        )
        senderSession.send(
            Frame.Text("""{"type":"group_notification","recipientId":"$receiver","marker":"NOTIF-X"}"""),
        )
        senderSession.send(
            Frame.Text("""{"type":"group_message_fanout","recipientId":"$receiver","marker":"FANOUT-X"}"""),
        )

        assertNull(receiverSession.awaitFrame("-X", timeoutMillis = 1_500))
        senderSession.close()
        receiverSession.close()
    }

    @Test
    fun `a frame without a recipient is dropped`() = e2e {
        val (sender, senderToken) = newAccount()
        val session = connect(sender, senderToken)

        session.send(Frame.Text("""{"type":"encrypted_message","ciphertext":"AAAA"}"""))
        delay(400)

        assertTrue(connectionManager.isOnline(sender))
        session.close()
    }

    // ---------------- Admin sifreli log ----------------

    @Test
    fun `an admin encrypted log with a malformed shape is dropped`() = e2e {
        val (sender, senderToken) = newAccount()
        val (admin, adminToken) = newAccount()
        val senderSession = connect(sender, senderToken)
        val adminSession = connect(admin, adminToken)
        val group = opaqueGroupId()

        // eventType yanlis, payload sayisi yanlis ve groupId eksik olanlar.
        senderSession.send(
            Frame.Text(
                """{"type":"admin_encrypted_log","groupId":"$group","eventType":"OTHER",""" +
                    """"adminPayloads":{"$admin":"AAAA"},"marker":"ADM-1"}""",
            ),
        )
        senderSession.send(
            Frame.Text(
                """{"type":"admin_encrypted_log","eventType":"PRIVATE_EVENT",""" +
                    """"adminPayloads":{"$admin":"AAAA"},"marker":"ADM-2"}""",
            ),
        )
        senderSession.send(
            Frame.Text(
                """{"type":"admin_encrypted_log","groupId":"$group","eventType":"PRIVATE_EVENT",""" +
                    """"adminPayloads":{},"marker":"ADM-3"}""",
            ),
        )

        assertNull(adminSession.awaitFrame("ADM-", timeoutMillis = 1_500))
        senderSession.close()
        adminSession.close()
    }

    @Test
    fun `a well formed admin encrypted log reaches only its addressed admin`() = e2e {
        val (sender, senderToken) = newAccount()
        val (admin, adminToken) = newAccount()
        val (bystander, bystanderToken) = newAccount()
        val senderSession = connect(sender, senderToken)
        val adminSession = connect(admin, adminToken)
        val bystanderSession = connect(bystander, bystanderToken)
        val group = opaqueGroupId()
        val marker = "ADMLOG-${UUID.randomUUID()}"

        senderSession.send(
            Frame.Text(
                """{"type":"admin_encrypted_log","groupId":"$group","eventType":"PRIVATE_EVENT",""" +
                    """"adminPayloads":{"$admin":"$marker"}}""",
            ),
        )

        // Sunucu icerigi goremez, yalniz adreslenmis admin'e iletir.
        assertNotNull(adminSession.awaitFrame(marker, 5_000))
        assertNull(bystanderSession.awaitFrame(marker, 1_000))
        senderSession.close()
        adminSession.close()
        bystanderSession.close()
    }
}
