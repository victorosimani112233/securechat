package com.securechat.signaling

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID

/**
 * Presence aboneliginin sinirlari.
 *
 * Onceki davranista bir kullanici sinirsiz sayida hedefe abone olabiliyordu
 * ve abonelik haritalari process omru boyunca yalniz buyuyordu. Hedefin
 * gercek bir hesap olup olmadigi da hic kontrol edilmiyordu.
 */
class PresenceSubscriptionTest {

    private val manager = ConnectionManager()

    @Test
    fun `a subscriber stops at the configured ceiling`() = runBlocking {
        val subscriber = UUID.randomUUID().toString()
        var accepted = 0
        // Tavan asilana kadar kabul, sonrasinda ret.
        repeat(MAX_EXPECTED + 5) { index ->
            if (manager.subscribePresence(subscriber, "target-$index")) accepted++
        }
        assertTrue(accepted == MAX_EXPECTED, "beklenen tavan $MAX_EXPECTED, kabul $accepted")
    }

    @Test
    fun `unsubscribing frees a slot`() = runBlocking {
        val subscriber = UUID.randomUUID().toString()
        repeat(MAX_EXPECTED) { index ->
            assertTrue(manager.subscribePresence(subscriber, "slot-$index"))
        }
        assertFalse(manager.subscribePresence(subscriber, "overflow"))

        manager.unsubscribePresence(subscriber, "slot-0")
        assertTrue(manager.subscribePresence(subscriber, "overflow"))
    }

    @Test
    fun `unsubscribing an unknown target is a no-op`() = runBlocking {
        val subscriber = UUID.randomUUID().toString()
        manager.unsubscribePresence(subscriber, "never-subscribed")
        // Bos hedef anahtari birakilmadigi icin sonraki abonelik yer bulur.
        assertTrue(manager.subscribePresence(subscriber, "target"))
    }

    @Test
    fun `separate subscribers keep independent budgets`() = runBlocking {
        val first = UUID.randomUUID().toString()
        val second = UUID.randomUUID().toString()
        repeat(MAX_EXPECTED) { index ->
            assertTrue(manager.subscribePresence(first, "shared-$index"))
        }
        assertFalse(manager.subscribePresence(first, "shared-extra"))
        // Bir kullanicinin tavani digerini etkilememeli.
        assertTrue(manager.subscribePresence(second, "shared-0"))
    }

    private companion object {
        const val MAX_EXPECTED = 512
    }
}
