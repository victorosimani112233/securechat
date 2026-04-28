package com.securechat.contacts

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * PhoneNumberNormalizer icin unit testleri.
 * Cesitli kullanici girisi formatlarinin userId formatina dogru donusturulmesini dogrular.
 */
class PhoneNumberNormalizerTest {

    // --- normalizeToUserId: Turkiye cep numaralari ---

    @Test
    fun `5 ile baslayan 10 haneli numara 90 on eki alir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("5551234567")
        assertEquals("905551234567", result)
    }

    @Test
    fun `05 ile baslayan 11 haneli numara 9 on eki alir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("05551234567")
        assertEquals("905551234567", result)
    }

    @Test
    fun `90 ile baslayan numara degistirilmez`() {
        val result = PhoneNumberNormalizer.normalizeDigits("905551234567")
        assertEquals("905551234567", result)
    }

    @Test
    fun `+90 ile baslayan numara + isareti kaldirilir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+905551234567")
        assertEquals("905551234567", result)
    }

    // --- normalizeToUserId: bosluk ve tire iceren formatlar ---

    @Test
    fun `bosluklu numara normalize edilir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("555 123 45 67")
        assertEquals("905551234567", result)
    }

    @Test
    fun `tireli numara normalize edilir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("555-123-45-67")
        assertEquals("905551234567", result)
    }

    @Test
    fun `parantez ve bosluklu numara normalize edilir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+90 (555) 123 45 67")
        assertEquals("905551234567", result)
    }

    @Test
    fun `tire ve bosluklu numara normalize edilir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("0555-123-45-67")
        assertEquals("905551234567", result)
    }

    // --- normalizeToUserId: uluslararasi numaralar ---

    @Test
    fun `ABD numarasi oldugu gibi kalir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+12025551234")
        assertEquals("12025551234", result)
    }

    @Test
    fun `Almanya numarasi oldugu gibi kalir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+4915112345678")
        assertEquals("4915112345678", result)
    }

    @Test
    fun `Ingiltere numarasi oldugu gibi kalir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+447911123456")
        assertEquals("447911123456", result)
    }

    // --- normalizeToUserId: sinir durumlari ---

    @Test
    fun `bos string bos doner`() {
        val result = PhoneNumberNormalizer.normalizeDigits("")
        assertEquals("", result)
    }

    @Test
    fun `yalnizca + isareti bos doner`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+")
        assertEquals("", result)
    }

    @Test
    fun `yalnizca bosluklar bos doner`() {
        val result = PhoneNumberNormalizer.normalizeDigits("   ")
        assertEquals("", result)
    }

    @Test
    fun `5 ile baslayan ancak 10 haneden kisa numara oldugu gibi kalir`() {
        // 9 hane - Turk cep numarasi formati degil
        val result = PhoneNumberNormalizer.normalizeDigits("555123456")
        assertEquals("555123456", result)
    }

    @Test
    fun `05 ile baslayan ancak 11 haneden kisa numara oldugu gibi kalir`() {
        // 10 hane - Turk formati icin eksik
        val result = PhoneNumberNormalizer.normalizeDigits("0555123456")
        assertEquals("0555123456", result)
    }

    @Test
    fun `karmasik ozel karakter icerenler temizlenir`() {
        val result = PhoneNumberNormalizer.normalizeDigits("+90 (555) 123-45-67")
        assertEquals("905551234567", result)
    }

    // --- formatForDisplay ---

    @Test
    fun `Turkiye numarasi okunabilir formata cevirilir`() {
        val result = PhoneNumberNormalizer.formatForDisplay("905551234567")
        assertEquals("+90 555 123 45 67", result)
    }

    @Test
    fun `diger ulke numarasi basina + eklenir`() {
        val result = PhoneNumberNormalizer.formatForDisplay("12025551234")
        assertEquals("+12025551234", result)
    }

    @Test
    fun `kisa numara basina + eklenir`() {
        val result = PhoneNumberNormalizer.formatForDisplay("5551234567")
        assertEquals("+5551234567", result)
    }

    // --- E2E: kullanici giris akisi senaryolari ---

    @Test
    fun `senaryo - kullanici sadece cep numarasini yazar`() {
        // Kullanici: "5551234567" -> userId: "905551234567"
        val input = "5551234567"
        val normalized = PhoneNumberNormalizer.normalizeDigits(input)
        assertEquals("905551234567", normalized)
        // Gosterim: "+90 555 123 45 67"
        val display = PhoneNumberNormalizer.formatForDisplay(normalized)
        assertEquals("+90 555 123 45 67", display)
    }

    @Test
    fun `senaryo - kullanici basinda sifir ile yazar`() {
        // Kullanici: "05551234567" -> userId: "905551234567"
        val input = "05551234567"
        val normalized = PhoneNumberNormalizer.normalizeDigits(input)
        assertEquals("905551234567", normalized)
    }

    @Test
    fun `senaryo - kullanici tam uluslararasi format kullanir`() {
        // Kullanici: "+905551234567" -> userId: "905551234567"
        val input = "+905551234567"
        val normalized = PhoneNumberNormalizer.normalizeDigits(input)
        assertEquals("905551234567", normalized)
    }

    @Test
    fun `senaryo - kullanici ulke kodunu + olmadan yazar`() {
        // Kullanici: "905551234567" -> userId: "905551234567"
        val input = "905551234567"
        val normalized = PhoneNumberNormalizer.normalizeDigits(input)
        assertEquals("905551234567", normalized)
    }
}
