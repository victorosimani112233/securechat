package com.securechat.signaling

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Janus kontrol kanali.
 *
 * Uc bulgu burada dogrulanir: oda kimligi tahmin edilebilir olmamali,
 * gonderim hatasi bekleyen istek kaydi birakmamali (harita aksi halde yalniz
 * buyur), ve baglanti koptugunda bekleyen istekler sonsuza kadar askida
 * kalmayip hata ile dusmeli.
 */
class JanusOrchestratorTest {

    /**
     * QA 2026-10-12 Bulgu 8a: canli sunucuda SFU kapali ve Janus sirlari yok.
     * Sirlar sinif baslaticisinda okundugu icin `hasActiveRoom` bile
     * NoClassDefFoundError atiyor, grup HANGUP'inin bitis yayini gitmiyordu.
     */
    @Test
    fun `missing secrets do not break room lookups but init still fails closed`() {
        val original = JanusOrchestrator.secretEnvironment
        JanusOrchestrator.secretEnvironment = { emptyMap() }
        JanusOrchestrator.resetSecretsForTest()
        try {
            assertFalse(JanusOrchestrator.hasActiveRoom("group-without-room"))
            assertNull(JanusOrchestrator.getRoomInfo("group-without-room"))
            runBlocking { JanusOrchestrator.destroyVideoRoom("group-without-room") }
            // SFU acik sunucu sirsiz baslamamali (H6).
            assertThrows(IllegalStateException::class.java) { JanusOrchestrator.init() }
        } finally {
            JanusOrchestrator.secretEnvironment = original
            JanusOrchestrator.resetSecretsForTest()
        }
    }

    @Test
    fun `room ids are unpredictable and inside the positive 62 bit range`() {
        val ids = (1..2_000).map { JanusOrchestrator.nextRoomId() }

        assertEquals(ids.size, ids.toSet().size, "carpisma uretildi")
        assertTrue(ids.all { it > 0 }, "sifir veya negatif oda kimligi")
        assertTrue(ids.all { it <= 0x3FFF_FFFF_FFFF_FFFFL })
        // Artan bir sayac olsaydi ardisik degerler bir fark verirdi.
        val deltas = ids.zipWithNext { a, b -> b - a }.toSet()
        assertTrue(deltas.size > 1_000, "degerler ardisik gorunuyor")
    }

    @Test
    fun `a send failure does not leak a pending request entry`() = runBlocking {
        val before = JanusOrchestrator.pendingRequestCount()
        val message = buildJsonObject {
            put("janus", "keepalive")
            put("transaction", "txn_test_send_failure")
        }

        // WebSocket bagli degil: gonderim hemen hata verir.
        assertThrows(IllegalStateException::class.java) {
            runBlocking { JanusOrchestrator.sendAndWait(message, timeoutMs = 100) }
        }

        assertEquals(before, JanusOrchestrator.pendingRequestCount())
    }

    @Test
    fun `a message without a transaction is rejected before anything is registered`() = runBlocking {
        val before = JanusOrchestrator.pendingRequestCount()

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                JanusOrchestrator.sendAndWait(buildJsonObject { put("janus", "keepalive") })
            }
        }

        assertEquals(before, JanusOrchestrator.pendingRequestCount())
    }

    @Test
    fun `failing pending requests empties the map`() {
        JanusOrchestrator.failPendingRequests()

        assertEquals(0, JanusOrchestrator.pendingRequestCount())
    }
}
