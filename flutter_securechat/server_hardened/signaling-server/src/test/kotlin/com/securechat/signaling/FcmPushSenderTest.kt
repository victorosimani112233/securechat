package com.securechat.signaling

import ch.qos.logback.classic.Level
import com.google.api.client.json.gson.GsonFactory
import com.google.firebase.messaging.AndroidConfig
import com.google.firebase.messaging.Message
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Push kapisi ve baslatma sagligi.
 *
 * Uc ayri bulgu burada dogrulanir:
 *  - baslatma hatasi yutuluyordu, sistem push hic calismazken saglikli
 *    gorunuyordu (P1-10);
 *  - zamanlama haritalari ham UUID tutuyor ve hic temizlenmiyordu (P2-10);
 *  - arama sinyalleri normal mesajlarla ayni sayaci paylasirsa cagri
 *    push'u bloklanabiliyordu.
 */
class FcmPushSenderTest {

    @Test
    fun `aggregate diagnostics distinguish missing registration and keyless or hinted acceptance`() = runBlocking {
        fun count(stage: PushDiagnosticStage) = Metrics.registry
            .get("securechat_fcm_diagnostic_total").tag("stage", stage.label).counter().count()
        val before = PushDiagnosticStage.entries.associateWith(::count)
        var registration: FcmTokenStore.DeviceRegistration? = null
        val push = FcmPushSender.forDeliveryTest({ registration }, {})
        assertFalse(push.sendWakeUpPush("synthetic-diagnostic-recipient", "sdp_offer"))
        registration = FcmTokenStore.DeviceRegistration("synthetic-diagnostic-token", null)
        assertTrue(push.sendWakeUpPush("synthetic-diagnostic-recipient", "sdp_offer"))
        assertFalse(push.sendWakeUpPush("synthetic-diagnostic-recipient", "sdp_offer"))
        registration = FcmTokenStore.DeviceRegistration("synthetic-diagnostic-token", ByteArray(32) { 7 })
        assertTrue(push.sendWakeUpPush("synthetic-other-recipient", "sdp_offer"))

        for (stage in listOf(
            PushDiagnosticStage.REGISTRATION_UNAVAILABLE,
            PushDiagnosticStage.HINT_MISSING,
            PushDiagnosticStage.ACCEPTED_KEYLESS,
            PushDiagnosticStage.RATE_LIMITED,
            PushDiagnosticStage.ACCEPTED_HINTED,
        )) {
            assertEquals(before.getValue(stage) + 1, count(stage), stage.label)
        }
        val diagnosticMeters = Metrics.registry.meters.filter {
            it.id.name == "securechat_fcm_diagnostic_total"
        }
        assertEquals(PushDiagnosticStage.entries.size, diagnosticMeters.size)
        assertEquals(PushDiagnosticStage.entries.map { it.label }.toSet(), diagnosticMeters.map {
            assertEquals(listOf("stage"), it.id.tags.map { tag -> tag.key })
            it.id.getTag("stage")
        }.toSet())
        assertTrue(diagnosticMeters.none { it.id.toString().contains("synthetic-") })
    }

    @Test
    fun `concurrent offers consume only one rate slot`() {
        val push = sender()
        val workers = Executors.newFixedThreadPool(16)
        val ready = CountDownLatch(16)
        val start = CountDownLatch(1)
        try {
            val results = (1..16).map {
                workers.submit<Boolean> {
                    ready.countDown()
                    check(start.await(10, TimeUnit.SECONDS))
                    push.allowPush("synthetic-recipient", "sdp_offer", base)
                }
            }
            assertTrue(ready.await(10, TimeUnit.SECONDS))
            start.countDown()
            assertEquals(1, results.count { it.get(10, TimeUnit.SECONDS) })
        } finally {
            start.countDown()
            workers.shutdownNow()
        }
    }

    @Test
    fun `missing registration must not suppress a push immediately after registration`() = runBlocking {
        val key = ByteArray(32) { (it + 1).toByte() }
        var registration: FcmTokenStore.DeviceRegistration? = null
        val captured = mutableListOf<Message>()
        val push = FcmPushSender.forDeliveryTest({ registration }, { captured.add(it) })

        assertFalse(push.sendWakeUpPush("synthetic-recipient", "sdp_offer"))
        registration = FcmTokenStore.DeviceRegistration("synthetic-fcm-token-for-retry-test", key)
        assertTrue(push.sendWakeUpPush("synthetic-recipient", "sdp_offer"))
        assertEquals(1, captured.size)
        val data = Json.parseToJsonElement(
            GsonFactory.getDefaultInstance().toString(captured.single()),
        ).jsonObject.getValue("data").jsonObject
        assertEquals('c', PushHintCipher().open(key, data.getValue("k").jsonPrimitive.content))
    }

    @Test
    fun `lookup failures are reported without leaking secrets or blocking a later registration`() = runBlocking {
        val secret = "private-token-and-key-must-not-be-logged"
        var failing = true
        var sends = 0
        val push = FcmPushSender.forDeliveryTest(
            {
                if (failing) throw IllegalStateException(secret)
                FcmTokenStore.DeviceRegistration("synthetic-fcm-token-for-lookup-test", ByteArray(32) { 7 })
            },
            { sends++ },
        )
        TestLogCapture("FcmPushSender").use { logs ->
            assertFalse(push.sendWakeUpPush("synthetic-recipient", "sdp_offer"))
            assertTrue(logs.events.any {
                it.formattedMessage == "[FCM] Wake skipped; reason=registration_lookup_failed; error=IllegalStateException"
            })
            logs.assertNoSecrets(secret, "synthetic-recipient")
        }
        failing = false
        assertTrue(push.sendWakeUpPush("synthetic-recipient", "sdp_offer"))
        assertEquals(1, sends)
    }

    /** Gercekci epoch tabani; kapi "hic push gonderilmedi"yi 0 olarak okur. */
    private val base = 1_800_000_000_000L

    private fun sender(path: String? = null) =
        FcmPushSender.forGateTest(serviceAccountPath = path)

    @Test
    fun `the actual Firebase payload carries only generic type and encrypted call hint`() = runBlocking {
        val key = ByteArray(32) { (it + 1).toByte() }
        for (type in listOf("sdp_offer", "group_call_invite")) {
            var captured: Message? = null
            var lookups = 0
            val push = FcmPushSender.forDeliveryTest(
                registrationLookup = {
                    lookups++
                    FcmTokenStore.DeviceRegistration("synthetic-fcm-token-for-payload-test", key)
                },
                messageSender = { captured = it },
            )

            assertTrue(push.sendWakeUpPush("synthetic-recipient", type))
            assertEquals(1, lookups, "Token and key must come from one registration snapshot")
            val payload = Json.parseToJsonElement(
                GsonFactory.getDefaultInstance().toString(captured!!),
            ).jsonObject
            val data = payload.getValue("data").jsonObject
            assertEquals(setOf("type", "k"), data.keys)
            assertEquals("securechat_wake_v2", data.getValue("type").jsonPrimitive.content)
            val hint = data.getValue("k").jsonPrimitive.content
            assertEquals(PushHintCipher.WIRE_LENGTH, hint.length)
            assertEquals('c', PushHintCipher().open(key, hint))
            assertFalse(payload.containsKey("notification"))
            val android = payload.getValue("android").jsonObject
            assertEquals("high", android.getValue("priority").jsonPrimitive.content)
            assertEquals("30s", android.getValue("ttl").jsonPrimitive.content)
        }
    }

    @Test
    fun `non-call wakes also include k whenever the registration has a key`() = runBlocking {
        val key = ByteArray(32) { (it + 1).toByte() }
        for (type in listOf("encrypted_message", "call_control")) {
            var captured: Message? = null
            val push = FcmPushSender.forDeliveryTest(
                { FcmTokenStore.DeviceRegistration("synthetic-fcm-token-for-payload-test", key) },
                { captured = it },
            )
            assertTrue(push.sendWakeUpPush("synthetic-recipient", type))
            val data = Json.parseToJsonElement(
                GsonFactory.getDefaultInstance().toString(captured!!),
            ).jsonObject.getValue("data").jsonObject
            assertEquals(setOf("type", "k"), data.keys)
            assertEquals('m', PushHintCipher().open(key, data.getValue("k").jsonPrimitive.content))
        }
    }

    @Test
    fun `legacy registrations omit k but encryption errors never send a hintless fallback`() = runBlocking {
        val user = "synthetic-recipient"
        val token = "synthetic-fcm-token-for-payload-test"
        val missingKeyWarning = "[FCM] Ipucu anahtari bulunamadi \u2014 push tursuz gidecek"
        var captured: Message? = null
        TestLogCapture("FcmPushSender").use { logs ->
            val legacy = FcmPushSender.forDeliveryTest(
                { FcmTokenStore.DeviceRegistration(token, null) },
                {
                    assertEquals(listOf(Level.WARN to missingKeyWarning), logs.events.map { event ->
                        event.level to event.formattedMessage
                    })
                    captured = it
                },
            )
            assertTrue(legacy.sendWakeUpPush(user, "sdp_offer"))
            val data = Json.parseToJsonElement(
                GsonFactory.getDefaultInstance().toString(captured!!),
            ).jsonObject.getValue("data").jsonObject
            assertEquals(setOf("type"), data.keys)
            assertEquals(
                listOf(
                    Level.WARN to missingKeyWarning,
                    Level.INFO to "[FCM] Generic wake push gonderildi; hint=false",
                ),
                logs.events.map { it.level to it.formattedMessage },
            )
            logs.assertNoSecrets(user, token, "sdp_offer")
        }

        captured = null
        val invalidKey = ByteArray(31) { (it + 1).toByte() }
        TestLogCapture("FcmPushSender").use { logs ->
            val invalid = FcmPushSender.forDeliveryTest(
                { FcmTokenStore.DeviceRegistration(token, invalidKey) },
                { captured = it },
            )
            assertFalse(invalid.sendWakeUpPush(user, "sdp_offer"))
            assertNull(captured)
            assertEquals(
                listOf(Level.INFO to "[FCM] Push gonderilemedi: IllegalArgumentException"),
                logs.events.map { it.level to it.formattedMessage },
            )
            logs.assertNoSecrets(user, token, Base64.getEncoder().encodeToString(invalidKey))
        }
    }

    @Test
    fun `hint added is logged before transport and never implies successful delivery`() = runBlocking {
        val user = "synthetic-recipient-for-log-test"
        val token = "synthetic-fcm-token-for-log-test"
        val key = ByteArray(32) { (it + 1).toByte() }
        val hintAdded = Level.INFO to "[FCM] Sifreli tur ipucu eklendi"
        for (transportFails in listOf(false, true)) {
            TestLogCapture("FcmPushSender").use { logs ->
                var encryptedHint: String? = null
                var sends = 0
                val push = FcmPushSender.forDeliveryTest(
                    { FcmTokenStore.DeviceRegistration(token, key) },
                    { message ->
                        sends++
                        encryptedHint = Json.parseToJsonElement(
                            GsonFactory.getDefaultInstance().toString(message),
                        ).jsonObject.getValue("data").jsonObject.getValue("k").jsonPrimitive.content
                        assertEquals(listOf(hintAdded), logs.events.map { it.level to it.formattedMessage })
                        if (transportFails) {
                            throw IllegalStateException("$user $token ${Base64.getEncoder().encodeToString(key)} $encryptedHint")
                        }
                    },
                )

                assertEquals(!transportFails, push.sendWakeUpPush(user, "sdp_offer"))
                assertEquals(1, sends)
                assertNotNull(encryptedHint)
                assertEquals(
                    listOf(
                        hintAdded,
                        Level.INFO to if (transportFails) {
                            "[FCM] Push gonderilemedi: IllegalStateException"
                        } else {
                            "[FCM] Generic wake push gonderildi; hint=true"
                        },
                    ),
                    logs.events.map { it.level to it.formattedMessage },
                )
                logs.assertNoSecrets(
                    user, token, encryptedHint!!, "sdp_offer", key.contentToString(),
                    Base64.getEncoder().encodeToString(key),
                    Base64.getUrlEncoder().withoutPadding().encodeToString(key),
                )
            }
        }
    }

    @Test
    fun `an unconfigured sender is not operational and reports no error`() {
        val push = sender(path = null)

        assertFalse(push.isOperational)
        // Yapilandirilmamis olmak bir hata degildir; hata alani yalniz
        // gercek bir baslatma basarisizligini gostermelidir.
        assertNull(push.initializationError)
    }

    @Test
    fun `a failed initialization is surfaced instead of being swallowed`() {
        val push = sender(path = "/nonexistent/firebase-service-account.json")

        assertFalse(push.isOperational)
        // Onceki davranista hata yutuluyor ve health yalniz env path'inin
        // varligina bakip "enabled" diyordu.
        assertNotNull(push.initializationError)
    }

    @Test
    fun `transient signals never produce a push`() {
        val push = sender()
        val user = "123e4567-e89b-42d3-a456-426614174000"

        for (type in listOf("typing_indicator", "presence_update", "audio_data", "video_data")) {
            assertFalse(push.allowPush(user, type, now = base + 1_000L), type)
        }
    }

    @Test
    fun `ice candidate and sdp answer do not burn the call rate limit`() {
        val push = sender()
        val user = "123e4567-e89b-42d3-a456-426614174001"

        // Bunlar SDP Offer'den once cikabilir; kendi push'larini gonderselerdi
        // asil "incoming_call" push'u rate-limit'e takilirdi.
        assertFalse(push.allowPush(user, "ice_candidate", now = base + 1_000L))
        assertFalse(push.allowPush(user, "sdp_answer", now = base + 1_000L))
        assertTrue(push.allowPush(user, "sdp_offer", now = base + 1_000L))
    }

    @Test
    fun `the same recipient is rate limited inside the window`() {
        val push = sender()
        val user = "123e4567-e89b-42d3-a456-426614174002"

        assertTrue(push.allowPush(user, "encrypted_message", now = base + 10_000L))
        assertFalse(push.allowPush(user, "encrypted_message", now = base + 12_000L))
        assertTrue(push.allowPush(user, "encrypted_message", now = base + 13_001L))
    }

    @Test
    fun `call signals and normal messages use separate counters`() {
        val push = sender()
        val user = "123e4567-e89b-42d3-a456-426614174003"

        assertTrue(push.allowPush(user, "encrypted_message", now = base + 10_000L))
        // Ayni pencerede gelen cagri sinyali bloklanmamali.
        assertTrue(push.allowPush(user, "sdp_offer", now = base + 10_100L))
        assertFalse(push.allowPush(user, "sdp_offer", now = base + 10_200L))
    }

    @Test
    fun `call control wake cannot consume the next incoming call hint window`() {
        val push = sender()
        val user = "synthetic-recipient"

        assertTrue(push.allowPush(user, "call_control", now = base))
        assertTrue(push.allowPush(user, "sdp_offer", now = base + 100))
        assertFalse(push.allowPush(user, "call_control", now = base + 200))
        assertFalse(push.allowPush(user, "group_call_invite", now = base + 200))
    }

    @Test
    fun `message wake survives until the encrypted queue expires`() {
        assertEquals(
            900_000L,
            FcmPushSender.androidTtlMillis(
                isCallSignal = false,
                offlineQueueTtlSeconds = 900,
            ),
        )
        assertEquals(
            30_000L,
            FcmPushSender.androidTtlMillis(
                isCallSignal = true,
                offlineQueueTtlSeconds = 900,
            ),
        )
    }

    @Test
    fun `all incoming call wake types use high Android priority`() {
        assertEquals(
            AndroidConfig.Priority.HIGH,
            FcmPushSender.androidPriorityFor("sdp_offer"),
        )
        assertEquals(
            AndroidConfig.Priority.HIGH,
            FcmPushSender.androidPriorityFor("group_call_invite"),
        )
    }

    @Test
    fun `different recipients do not share a counter`() {
        val push = sender()

        assertTrue(push.allowPush("123e4567-e89b-42d3-a456-426614174004", "encrypted_message", base + 10_000L))
        assertTrue(push.allowPush("123e4567-e89b-42d3-a456-426614174005", "encrypted_message", base + 10_000L))
    }

    @Test
    fun `the timing map stores a blind index rather than the raw account id`() {
        val push = sender()
        val user = "123e4567-e89b-42d3-a456-426614174006"

        assertTrue(push.allowPush(user, "encrypted_message", now = base + 10_000L))

        // Haritanin ham UUID tutmadigini, ayni kullanicinin blind index'iyle
        // ikinci cagrinin ayni girdiye dustugunu dogrular: farkli bir anahtar
        // kullanilsaydi rate limit hic uygulanmazdi.
        assertFalse(push.allowPush(user, "encrypted_message", now = base + 11_000L))
        assertEquals(1, push.rateMapSizes().first)
    }

    @Test
    fun `expired entries are pruned so the map does not grow forever`() {
        val push = sender()
        var now = base
        repeat(50) { index ->
            now += 4_000L
            push.allowPush("user-$index", "encrypted_message", now)
        }
        assertEquals(50, push.rateMapSizes().first)

        // Budama araligi ve yas esigi gectiginde eski girdiler dusmeli.
        now += 11 * 60_000L
        push.allowPush("late-comer", "encrypted_message", now)

        assertEquals(1, push.rateMapSizes().first)
    }
}
