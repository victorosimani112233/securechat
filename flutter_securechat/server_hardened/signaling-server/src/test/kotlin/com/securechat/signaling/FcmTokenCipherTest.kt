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
    fun `v4 envelopes are randomized authenticated and blind-index bound`() {
        val cipher = FcmTokenCipher(key)
        val first = cipher.seal(firstIndex, token)
        val second = cipher.seal(firstIndex, token)

        assertTrue(first.startsWith("v4:"))
        assertNotEquals(first, second)
        assertFalse(first.contains(token))
        assertEquals(token, cipher.openV4(firstIndex, first))
        assertNull(cipher.openV4(secondIndex, first))

        val tampered = first.dropLast(1) + if (first.last() == 'A') "B" else "A"
        assertNull(cipher.openV4(firstIndex, tampered))
    }

    @Test
    fun `invalid or reused keys fail closed`() {
        assertThrows(IllegalArgumentException::class.java) {
            FcmTokenCipher(ByteArray(31), SecureRandom())
        }
        assertNull(FcmTokenCipher(key).openV4(firstIndex, "plaintext-token"))
        assertNull(FcmTokenCipher(ByteArray(32) { 7 }).openV4(
            firstIndex,
            FcmTokenCipher(key).seal(firstIndex, token),
        ))
    }
}
