package com.securechat.signaling

import com.google.api.client.json.gson.GsonFactory
import com.google.firebase.messaging.Message
import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.util.Base64
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
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

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PushRegistrationDeliveryIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_push_registration_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)
    private lateinit var registry: UserRegistry
    private var databaseInitialized = false
    private var redisInitialized = false
    private val hintKey = ByteArray(32) { (it + 1).toByte() }
    private val encodedKey = Base64.getUrlEncoder().withoutPadding().encodeToString(hintKey)
    private val originalToken = "synthetic-fcm-token-for-registration-delivery-original"
    private val replacementToken = "synthetic-fcm-token-for-registration-delivery-replacement"

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker required")
        postgres.start()
        redis.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        databaseInitialized = true
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        redisInitialized = true
        ServerPrivacy.initialize()
        PurposeSeparatedSecrets.validate()
        SealedSenderCertificateIssuer.initialize()
        PrivateDirectory.initialize()
        MetricsAccess.initialize()
        AuthService.initialize()
        CredentialState.initialize()
        registry = UserRegistry()
        PrivacyRetentionWorker.runOnce()
    }

    @AfterAll
    fun tearDown() {
        try {
            if (redisInitialized) RedisManager.close()
        } finally {
            try {
                if (databaseInitialized) Database.close()
            } finally {
                try {
                    if (redis.isRunning) redis.stop()
                } finally {
                    if (postgres.isRunning) postgres.stop()
                }
            }
        }
    }

    @Test
    fun `HTTP registration delivers encrypted call hints across refresh and reload but not token replacement`() =
        testApplication {
            val store = FcmTokenStore()
            val user = UUID.randomUUID().toString()
            registry.registerUser(user)
            val accessToken = AuthService.issueToken(user)
            val captured = mutableListOf<Message>()
            val push = FcmPushSender.forDeliveryTest(store::getRegistration) { captured.add(it) }
            val manager = ConnectionManager(push)
            application { signalingModule(manager, registry, store, push) }

            TestLogCapture("HttpRoutes", "FcmTokenStore", "FcmPushSender").use { logs ->
                try {
                    val unauthorized = client.post("/api/v1/fcm/register") {
                        header("Content-Type", "application/json")
                        setBody(registrationBody(user, originalToken, encodedKey))
                    }
                    assertEquals(HttpStatusCode.Unauthorized, unauthorized.status)
                    assertNull(store.getRegistration(user))
                    assertNull(FcmTokenStore().getRegistration(user))

                    register(user, accessToken, originalToken, encodedKey, expectedHint = true)
                    assertEncryptedRow(user)
                    assertTrue(push.sendWakeUpPush(user, "sdp_offer"))
                    assertEquals(1, captured.size)
                    assertCallPayload(captured.single(), originalToken, expectedHint = true, logs)

                    register(user, accessToken, originalToken, expectedHint = true)
                    assertEncryptedRow(user)
                    assertArrayEquals(hintKey, store.getPushHintKey(user))
                    assertDelivery(store, user, originalToken, expectedHint = true, logs)

                    val reloaded = FcmTokenStore()
                    assertArrayEquals(hintKey, reloaded.getPushHintKey(user))
                    assertDelivery(reloaded, user, originalToken, expectedHint = true, logs)

                    register(user, accessToken, replacementToken, expectedHint = false)
                    assertEncryptedRow(user)
                    assertNull(store.getPushHintKey(user))
                    assertDelivery(store, user, replacementToken, expectedHint = false, logs)

                    val replacedReload = FcmTokenStore()
                    assertNull(replacedReload.getPushHintKey(user))
                    assertDelivery(replacedReload, user, replacementToken, expectedHint = false, logs)
                } finally {
                    store.removeToken(user)
                    assertTrue(logs.events.any { it.loggerName == "HttpRoutes" })
                    assertTrue(logs.events.any { it.loggerName == "FcmTokenStore" })
                    assertTrue(logs.events.any { it.loggerName == "FcmPushSender" })
                    logs.assertNoSecrets(
                        user, accessToken, originalToken, replacementToken, encodedKey,
                        hintKey.contentToString(), Base64.getEncoder().encodeToString(hintKey),
                    )
                }
            }
        }

    private fun registrationBody(user: String, token: String, key: String? = null): String =
        buildJsonObject {
            put("userId", user)
            put("fcmToken", token)
            if (key != null) put("pushHintKey", key)
        }.toString()

    private suspend fun ApplicationTestBuilder.register(
        user: String,
        accessToken: String,
        token: String,
        key: String? = null,
        expectedHint: Boolean,
    ) {
        val response = client.post("/api/v1/fcm/register") {
            header("Authorization", "Bearer $accessToken")
            header("Content-Type", "application/json")
            setBody(registrationBody(user, token, key))
        }
        assertEquals(HttpStatusCode.OK, response.status)
        val body = Json.parseToJsonElement(response.bodyAsText()).jsonObject
        assertEquals(setOf("status", "pushHintRegistered", "pushContract"), body.keys)
        assertEquals("ok", body.getValue("status").jsonPrimitive.content)
        assertEquals(expectedHint, body.getValue("pushHintRegistered").jsonPrimitive.boolean)
        assertEquals("encrypted-hint-v1", body.getValue("pushContract").jsonPrimitive.content)
    }

    private fun assertEncryptedRow(user: String) {
        Database.getConnection().use { connection ->
            connection.prepareStatement("SELECT user_index, token FROM fcm_tokens WHERE user_index = ?").use {
                statement ->
                val index = ServerPrivacy.blindIndex("push-user", user)
                statement.setString(1, index)
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertEquals(index, rows.getString("user_index"))
                    assertEquals(43, index.length)
                    val ciphertext = rows.getString("token")
                    assertTrue(ciphertext.startsWith("v5:"))
                    for (secret in listOf(user, originalToken, replacementToken, encodedKey)) {
                        assertFalse((index + ciphertext).contains(secret))
                    }
                    assertFalse(rows.next())
                }
            }
        }
    }

    private suspend fun assertDelivery(
        store: FcmTokenStore,
        user: String,
        token: String,
        expectedHint: Boolean,
        logs: TestLogCapture,
    ) {
        // Fresh senders isolate registration behavior from the per-recipient rate gate.
        val captured = mutableListOf<Message>()
        val sender = FcmPushSender.forDeliveryTest(store::getRegistration) { captured.add(it) }
        assertTrue(sender.sendWakeUpPush(user, "sdp_offer"))
        assertEquals(1, captured.size)
        assertCallPayload(captured.single(), token, expectedHint, logs)
    }

    private fun assertCallPayload(message: Message, token: String, expectedHint: Boolean, logs: TestLogCapture) {
        val payload: JsonObject = Json.parseToJsonElement(GsonFactory.getDefaultInstance().toString(message))
            .jsonObject
        assertEquals(token, payload.getValue("token").jsonPrimitive.content)
        assertFalse(payload.containsKey("notification"))
        val data = payload.getValue("data").jsonObject
        assertEquals(if (expectedHint) setOf("type", "k") else setOf("type"), data.keys)
        assertEquals("securechat_wake_v2", data.getValue("type").jsonPrimitive.content)
        if (expectedHint) {
            val hint = data.getValue("k").jsonPrimitive.content
            assertEquals(PushHintCipher.WIRE_LENGTH, hint.length)
            assertEquals('c', PushHintCipher().open(hintKey, hint))
            logs.assertNoSecrets(hint)
        } else {
            assertNull(data["k"])
        }
        val android = payload.getValue("android").jsonObject
        assertEquals("high", android.getValue("priority").jsonPrimitive.content)
        assertEquals("30s", android.getValue("ttl").jsonPrimitive.content)
    }
}
