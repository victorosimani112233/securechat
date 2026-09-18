package com.securechat.signaling

import java.security.SecureRandom
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FcmTokenCipherTest {
    private val key = ByteArray(32) { (it + 31).toByte() }
    private val firstIndex = "A".repeat(43)
    private val secondIndex = "B".repeat(43)
    private val token = "fcm_registration_token:test-device-0123456789"

    @Test
    fun `v5 envelopes are versioned randomized and blind-index bound`() {
        val cipher = FcmTokenCipher(key)
        val first = cipher.seal(firstIndex, token)
        val second = cipher.seal(firstIndex, token)

        assertTrue(first.startsWith("v5:"))
        assertNotEquals(first, second)
        assertFalse(first.contains(token))
        assertEquals(token, cipher.open(firstIndex, first))
        assertNull(cipher.open(secondIndex, first))

        val tampered = first.dropLast(1) + if (first.last() == 'A') "B" else "A"
        assertNull(cipher.open(firstIndex, tampered))
    }

    @Test
    fun `v4 envelope remains decryptable and is marked for migration`() {
        val cipher = FcmTokenCipher(key)
        val legacy = cipher.sealLegacyV4(firstIndex, token)

        assertEquals(token, cipher.open(firstIndex, legacy))
        assertTrue(cipher.needsMigration(legacy))
        assertFalse(cipher.needsMigration(cipher.seal(firstIndex, token)))
    }

    @Test
    fun `nonce budget fails closed before another seal`() {
        val cipher = FcmTokenCipher(key, nonceBudget = 2)
        cipher.seal(firstIndex, token)
        cipher.seal(firstIndex, token)

        assertThrows(IllegalStateException::class.java) {
            cipher.seal(firstIndex, token)
        }
    }

    @Test
    fun `invalid or reused keys fail closed`() {
        assertThrows(IllegalArgumentException::class.java) {
            FcmTokenCipher(ByteArray(31), SecureRandom())
        }
        assertNull(FcmTokenCipher(key).open(firstIndex, "plaintext-token"))
        assertNull(FcmTokenCipher(ByteArray(32) { 7 }).open(
            firstIndex,
            FcmTokenCipher(key).seal(firstIndex, token),
        ))
    }
}
