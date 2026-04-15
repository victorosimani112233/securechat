package com.securechat.contacts

import android.content.Context
import android.telephony.TelephonyManager
import com.google.i18n.phonenumbers.PhoneNumberUtil
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * Telefon numarasi normalizasyonu icin unit testleri.
 * Cesitli formatlardaki numaralarin E.164 formatina donusturulmesini dogrular.
 */
class PhoneNumberNormalizationTest {

    private lateinit var context: Context
    private lateinit var telephonyManager: TelephonyManager
    private lateinit var provider: ContactsProvider
    private val phoneNumberUtil = PhoneNumberUtil.getInstance()

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        telephonyManager = mockk(relaxed = true)
        every { context.getSystemService(Context.TELEPHONY_SERVICE) } returns telephonyManager
        every { telephonyManager.simCountryIso } returns "tr"
        provider = ContactsProvider(context, phoneNumberUtil)
    }

    // --- Turkiye numaralari ---

    @Test
    fun `uluslararasi formattaki TR numarasi normalize edilir`() {
        val result = provider.normalizePhoneNumber("+905551234567")
        assertEquals("+905551234567", result)
    }

    @Test
    fun `sifirli yerel TR numarasi normalize edilir`() {
        val result = provider.normalizePhoneNumber("05551234567")
        assertEquals("+905551234567", result)
    }

    @Test
    fun `bosluklu TR numarasi normalize edilir`() {
        val result = provider.normalizePhoneNumber("+90 555 123 45 67")
        assertEquals("+905551234567", result)
    }

    @Test
    fun `tireli TR numarasi normalize edilir`() {
        val result = provider.normalizePhoneNumber("+90-555-123-45-67")
        assertEquals("+905551234567", result)
    }

    @Test
    fun `parantezli TR numarasi normalize edilir`() {
        val result = provider.normalizePhoneNumber("+90 (555) 123 45 67")
        assertEquals("+905551234567", result)
    }

    // --- Uluslararasi numaralar ---

    @Test
    fun `ABD numarasi E164 formatina normalize edilir`() {
        val result = provider.normalizePhoneNumber("+12025551234")
        assertEquals("+12025551234", result)
    }

    @Test
    fun `Almanya numarasi E164 formatina normalize edilir`() {
        val result = provider.normalizePhoneNumber("+4915112345678")
        assertEquals("+4915112345678", result)
    }

    @Test
    fun `Ingiltere numarasi E164 formatina normalize edilir`() {
        val result = provider.normalizePhoneNumber("+447911123456")
        assertEquals("+447911123456", result)
    }

    // --- Gecersiz numaralar ---

    @Test
    fun `cok kisa numara null doner`() {
        val result = provider.normalizePhoneNumber("123")
        assertNull(result)
    }

    @Test
    fun `bos string null doner`() {
        val result = provider.normalizePhoneNumber("")
        assertNull(result)
    }

    @Test
    fun `harf iceren string null doner`() {
        val result = provider.normalizePhoneNumber("abc")
        assertNull(result)
    }

    @Test
    fun `gecersiz uzunluktaki numara null doner`() {
        val result = provider.normalizePhoneNumber("+9055512345")
        assertNull(result)
    }

    // --- Varsayilan ulke kodu ---

    @Test
    fun `getDefaultCountryCode SIM bilgisi varsa SIM ulkesini doner`() {
        every { telephonyManager.simCountryIso } returns "de"
        assertEquals("DE", provider.getDefaultCountryCode())
    }

    @Test
    fun `getDefaultCountryCode SIM bilgisi yoksa TR doner`() {
        every { telephonyManager.simCountryIso } returns null
        assertEquals("TR", provider.getDefaultCountryCode())
    }

    @Test
    fun `getDefaultCountryCode hata durumunda TR doner`() {
        every { context.getSystemService(Context.TELEPHONY_SERVICE) } throws RuntimeException("Service unavailable")
        assertEquals("TR", provider.getDefaultCountryCode())
    }
}
