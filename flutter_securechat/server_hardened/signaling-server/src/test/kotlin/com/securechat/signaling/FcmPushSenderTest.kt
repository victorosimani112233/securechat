package com.securechat.signaling

import com.google.firebase.messaging.AndroidConfig
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

    /** Gercekci epoch tabani; kapi "hic push gonderilmedi"yi 0 olarak okur. */
    private val base = 1_800_000_000_000L

    private fun sender(path: String? = null) =
        FcmPushSender.forGateTest(serviceAccountPath = path)

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
