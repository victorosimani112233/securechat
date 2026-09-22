package com.securechat.signaling

import com.google.api.client.json.gson.GsonFactory
import com.google.firebase.messaging.Message
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
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class BackgroundCallDeliveryIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_background_call_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)
    private lateinit var registry: UserRegistry
    private lateinit var store: FcmTokenStore
    private val hintKey = ByteArray(32) { (it + 1).toByte() }
    private var started = false

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker required")
        postgres.start()
        redis.start()
        started = true
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        ServerPrivacy.initialize()
        PrivateDirectory.initialize()
        MetricsAccess.initialize()
        AuthService.initialize()
        CredentialState.initialize()
        store = FcmTokenStore()
        registry = UserRegistry()
        PrivacyRetentionWorker.runOnce()
    }

    @AfterAll
    fun tearDown() {
        if (!started) return
        RedisManager.close()
        Database.close()
        redis.stop()
        postgres.stop()
    }

    private fun account(): Pair<String, String> {
        val user = UUID.randomUUID().toString()
        registry.registerUser(user)
        store.registerToken(
            user,
            "synthetic-fcm-token-for-background-test",
            Base64.getUrlEncoder().withoutPadding().encodeToString(hintKey),
        )
        return user to AuthService.issueToken(user)
    }

    private fun scenario(
        block: suspend ApplicationTestBuilder.(ConnectionManager, Channel<Message>) -> Unit,
    ) = testApplication {
        val pushes = Channel<Message>(Channel.UNLIMITED)
        val push = FcmPushSender.forDeliveryTest(store::getRegistration) { pushes.trySend(it) }
        val manager = ConnectionManager(push)
        application { signalingModule(manager, registry, store, push) }
        block(manager, pushes)
    }

    private suspend fun ApplicationTestBuilder.connect(
        account: Pair<String, String>,
        capability: String? = null,
    ): WebSocketSession = createClient { install(ClientWebSockets) }
        .webSocketSession("/ws?userId=${account.first}") {
            header("Authorization", "Bearer ${account.second}")
            if (capability != null) header(CALL_CAPABILITY_HEADER, capability)
        }

    private suspend fun awaitOnline(manager: ConnectionManager, user: String) {
        withTimeout(5_000) { while (!manager.isOnline(user)) delay(10) }
    }

    private fun queue(user: String): List<String> = RedisManager.use { jedis ->
        jedis.zrange(ServerPrivacy.queueKey("message", user), 0, -1)
            .map { ServerPrivacy.openQueue(user, it) }
    }

    private fun signal(type: String, sender: String, recipient: String, timestamp: Long = System.currentTimeMillis()) =
        """{"type":"$type","senderId":"$sender","recipientId":"$recipient","timestamp":$timestamp}"""

    private suspend fun WebSocketSession.nextText(): String = withTimeout(5_000) {
        var text: String? = null
        while (text == null) text = (incoming.receive() as? Frame.Text)?.readText()
        text
    }

    @Test
    fun `message-only drain retains all call frames for a default capable reconnect`() = scenario { manager, _ ->
        val recipient = account()
        val caller = account()
        for (type in MessageTypes.REQUIRES_CALL_HANDLER) {
            manager.routeMessage(recipient.first, signal(type, caller.first, recipient.first))
        }
        val background = connect(recipient, "false")
        awaitOnline(manager, recipient.first)
        assertNull(withTimeoutOrNull(200) { background.incoming.receive() })
        assertEquals(MessageTypes.REQUIRES_CALL_HANDLER.size, queue(recipient.first).size)

        val foreground = connect(recipient)
        val delivered = buildSet {
            repeat(MessageTypes.REQUIRES_CALL_HANDLER.size) {
                add(MessageTypes.extract(foreground.nextText()))
            }
        }
        assertEquals(MessageTypes.REQUIRES_CALL_HANDLER, delivered)
        withTimeout(5_000) { while (queue(recipient.first).isNotEmpty()) delay(10) }
        foreground.close()
        background.close()
    }

    @Test
    fun `an offer while message-only socket is online is queued and pushes an encrypted call hint`() = scenario { manager, pushes ->
        val recipient = account()
        val caller = account()
        val background = connect(recipient, "false")
        awaitOnline(manager, recipient.first)
        manager.routeMessage(recipient.first, signal("sdp_offer", caller.first, recipient.first))

        val message = withTimeout(5_000) { pushes.receive() }
        val data = Json.parseToJsonElement(GsonFactory.getDefaultInstance().toString(message))
            .jsonObject.getValue("data").jsonObject
        assertEquals(setOf("type", "k"), data.keys)
        assertEquals('c', PushHintCipher().open(hintKey, data.getValue("k").jsonPrimitive.content))
        assertEquals(1, queue(recipient.first).size)
        assertNull(withTimeoutOrNull(200) { background.incoming.receive() })

        manager.routeMessage(recipient.first, signal("encrypted_message", caller.first, recipient.first))
        assertEquals("encrypted_message", MessageTypes.extract(background.nextText()))
        assertEquals(1, queue(recipient.first).size)
        background.close()
    }

    @Test
    fun `message-only connection cannot evict a capable socket or suppress its call delivery`() = scenario { manager, pushes ->
        val recipient = account()
        val caller = account()
        val foreground = connect(recipient, "true")
        awaitOnline(manager, recipient.first)
        val original = manager.connections()[recipient.first]
        val background = connect(recipient, "false")
        withTimeout(5_000) { background.incoming.receiveCatching() }
        assertSame(original, manager.connections()[recipient.first])

        manager.routeMessage(recipient.first, signal("sdp_offer", caller.first, recipient.first))
        assertEquals("sdp_offer", MessageTypes.extract(foreground.nextText()))
        assertTrue(queue(recipient.first).isEmpty())
        assertNull(withTimeoutOrNull(200) { pushes.receive() })
        foreground.close()
        background.close()
    }

    @Test
    fun `stale offer is dropped and background disconnect does not clear active call state`() = scenario { manager, _ ->
        val recipient = account()
        val caller = account()
        manager.setActiveCallSession(caller.first, recipient.first)
        manager.routeMessage(
            recipient.first,
            signal("sdp_offer", caller.first, recipient.first, System.currentTimeMillis() - 31_000),
        )
        val background = connect(recipient, "false")
        awaitOnline(manager, recipient.first)
        withTimeout(5_000) { while (queue(recipient.first).isNotEmpty()) delay(10) }
        assertNull(withTimeoutOrNull(200) { background.incoming.receive() })
        background.close()
        withTimeout(5_000) { while (manager.isOnline(recipient.first)) delay(10) }
        assertTrue(manager.hasActiveCallSession(caller.first, recipient.first))
    }

    @Test
    fun `background disconnect leaves group call participation untouched`() = scenario { manager, _ ->
        val recipient = account()
        val peer = account()
        val group = UUID.randomUUID().toString()
        GroupCallSessionStore.start(
            group, UUID.randomUUID().toString(), recipient.first, "VOICE",
            listOf(recipient.first, peer.first), "MESH",
        )
        try {
            val before = GroupCallSessionStore.get(group)
            val background = connect(recipient, "false")
            awaitOnline(manager, recipient.first)
            background.close()
            withTimeout(5_000) { while (manager.isOnline(recipient.first)) delay(10) }
            assertEquals(before, GroupCallSessionStore.get(group))
        } finally {
            GroupCallSessionStore.end(group)
        }
    }

    @Test
    fun `hangup purges pending setup before a capable socket can replay it`() = scenario { manager, _ ->
        val recipient = account()
        val caller = account()
        val background = connect(recipient, "false")
        awaitOnline(manager, recipient.first)
        for (type in listOf("sdp_offer", "ice_candidate", "sdp_answer")) {
            manager.routeMessage(recipient.first, signal(type, caller.first, recipient.first))
        }
        manager.setActiveCallSession(caller.first, recipient.first)
        val callerSocket = connect(caller)
        callerSocket.send(Frame.Text(
            """{"type":"call_control","action":"HANGUP","recipientId":"${recipient.first}","timestamp":${System.currentTimeMillis()}}""",
        ))
        withTimeout(5_000) {
            while (queue(recipient.first).map(MessageTypes::extract) != listOf("call_control")) delay(10)
        }
        assertFalse(manager.hasActiveCallSession(caller.first, recipient.first))
        val foreground = connect(recipient)
        assertEquals("call_control", MessageTypes.extract(foreground.nextText()))
        assertNull(withTimeoutOrNull(200) { foreground.incoming.receive() })
        foreground.close()
        background.close()
        callerSocket.close()
    }

    @Test
    fun `invalid capability is rejected without registering a socket`() = scenario { manager, _ ->
        val recipient = account()
        val rejected = connect(recipient, "invalid")
        withTimeout(5_000) { rejected.incoming.receiveCatching() }
        assertFalse(manager.isOnline(recipient.first))
        rejected.close()
    }
}
