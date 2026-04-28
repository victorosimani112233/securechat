package com.securechat.contacts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * UserDiscoveryService icin unit testleri.
 * Hash uretimi ve normalizasyon tutarliligi dogrulanir.
 */
class UserDiscoveryServiceTest {

    @Test
    fun `hashPhoneNumber uretilen hash deterministik olmali`() {
        val phone = "+905551234567"
        val hash1 = UserDiscoveryService.hashPhoneNumber(phone)
        val hash2 = UserDiscoveryService.hashPhoneNumber(phone)
        assertEquals(hash1, hash2)
    }

    @Test
    fun `hashPhoneNumber sonucu 64 karakter hex string olmali`() {
        val hash = UserDiscoveryService.hashPhoneNumber("+905551234567")
        assertEquals(64, hash.length)
        assertTrue("Hash yalnizca hex karakterler icermeli", hash.matches(Regex("[0-9a-f]{64}")))
    }

    @Test
    fun `hashPhoneNumber farkli numaralar farkli hash uretmeli`() {
        val hash1 = UserDiscoveryService.hashPhoneNumber("+905551234567")
        val hash2 = UserDiscoveryService.hashPhoneNumber("+905559876543")
        assertNotEquals(hash1, hash2)
    }

    @Test
    fun `hashPhoneNumber bos string icin de gecerli hash uretmeli`() {
        val hash = UserDiscoveryService.hashPhoneNumber("")
        assertEquals(64, hash.length)
        assertTrue(hash.matches(Regex("[0-9a-f]{64}")))
    }

    @Test
    fun `hashPhoneNumber normalizeDigits ile tutarli olmali`() {
        // Farkli Turk telefon formatlari ayni hash'i uretmeli
        val hash1 = UserDiscoveryService.hashPhoneNumber("+905551234567")
        val hash2 = UserDiscoveryService.hashPhoneNumber("05551234567")
        val hash3 = UserDiscoveryService.hashPhoneNumber("5551234567")
        val hash4 = UserDiscoveryService.hashPhoneNumber("905551234567")
        assertEquals("Uluslararasi ve yerel format ayni hash uretmeli", hash1, hash2)
        assertEquals("10 haneli ve 11 haneli ayni hash uretmeli", hash1, hash3)
        assertEquals("90 prefiksli de ayni olmali", hash1, hash4)
    }

    @Test
    fun `hashPhoneNumber kayit ve kesif ayni hash uretmeli`() {
        // Kayit: PhoneVerificationScreen "+905551234567" gonderir
        // Kesif: Rehberde "05551234567" veya "+90 555 123 45 67" olabilir
        val registrationHash = UserDiscoveryService.hashPhoneNumber("+905551234567")
        val discoveryHash1 = UserDiscoveryService.hashPhoneNumber("05551234567")
        val discoveryHash2 = UserDiscoveryService.hashPhoneNumber("+90 555 123 45 67")
        assertEquals("Kayit ve kesif hash'leri uyusmali", registrationHash, discoveryHash1)
        assertEquals("Bosluklu format da ayni hash uretmeli", registrationHash, discoveryHash2)
    }
}
