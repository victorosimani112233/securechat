package com.securechat.app.ui.util

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * PhoneFormValidation icin pure-function birim testler.
 *
 * Compose'a deginmedigimiz icin instrumentation gerekmez, klasik JVM testi.
 * Bu testler ileride OtpVerificationScreen ve EmailOtpScreen icin de
 * referans olarak kullanilabilir.
 */
class PhoneFormValidationTest {

    // ---- validateName ----

    @Test
    fun `validateName - bos string Empty`() {
        assertThat(PhoneFormValidation.validateName(""))
            .isEqualTo(PhoneFormValidation.NameError.Empty)
    }

    @Test
    fun `validateName - sadece bosluk Empty`() {
        assertThat(PhoneFormValidation.validateName("   "))
            .isEqualTo(PhoneFormValidation.NameError.Empty)
    }

    @Test
    fun `validateName - tek harf TooShort`() {
        assertThat(PhoneFormValidation.validateName("A"))
            .isEqualTo(PhoneFormValidation.NameError.TooShort)
    }

    @Test
    fun `validateName - normal isim valid`() {
        assertThat(PhoneFormValidation.validateName("Ahmet Yilmaz")).isNull()
    }

    @Test
    fun `validateName - Turkce karakterler valid`() {
        assertThat(PhoneFormValidation.validateName("Şeyma Öztürk")).isNull()
    }

    @Test
    fun `validateName - kesme isareti ve tire valid`() {
        assertThat(PhoneFormValidation.validateName("D'Angelo")).isNull()
        assertThat(PhoneFormValidation.validateName("Mary-Jane")).isNull()
    }

    @Test
    fun `validateName - sayi InvalidChars`() {
        assertThat(PhoneFormValidation.validateName("Ahmet123"))
            .isEqualTo(PhoneFormValidation.NameError.InvalidChars)
    }

    @Test
    fun `validateName - sembol InvalidChars`() {
        assertThat(PhoneFormValidation.validateName("Ahmet@Yilmaz"))
            .isEqualTo(PhoneFormValidation.NameError.InvalidChars)
    }

    @Test
    fun `validateName - 51 karakter TooLong`() {
        val longName = "A".repeat(51)
        assertThat(PhoneFormValidation.validateName(longName))
            .isEqualTo(PhoneFormValidation.NameError.TooLong)
    }

    @Test
    fun `validateName - 50 karakter sinirda valid`() {
        val maxName = "A".repeat(50)
        assertThat(PhoneFormValidation.validateName(maxName)).isNull()
    }

    @Test
    fun `validateName - trim sonrasi 2 karakter valid`() {
        assertThat(PhoneFormValidation.validateName("  Ay  ")).isNull()
    }

    // ---- validateCountryCode ----

    @Test
    fun `validateCountryCode - bos Empty`() {
        assertThat(PhoneFormValidation.validateCountryCode(""))
            .isEqualTo(PhoneFormValidation.CountryCodeError.Empty)
    }

    @Test
    fun `validateCountryCode - plus eksik MissingPlus`() {
        assertThat(PhoneFormValidation.validateCountryCode("90"))
            .isEqualTo(PhoneFormValidation.CountryCodeError.MissingPlus)
    }

    @Test
    fun `validateCountryCode - sadece plus Empty`() {
        assertThat(PhoneFormValidation.validateCountryCode("+"))
            .isEqualTo(PhoneFormValidation.CountryCodeError.Empty)
    }

    @Test
    fun `validateCountryCode - non-digit NonDigit`() {
        assertThat(PhoneFormValidation.validateCountryCode("+9A"))
            .isEqualTo(PhoneFormValidation.CountryCodeError.NonDigit)
    }

    @Test
    fun `validateCountryCode - tek hane valid`() {
        assertThat(PhoneFormValidation.validateCountryCode("+1")).isNull()
    }

    @Test
    fun `validateCountryCode - TR kodu valid`() {
        assertThat(PhoneFormValidation.validateCountryCode("+90")).isNull()
    }

    @Test
    fun `validateCountryCode - 4 hane valid`() {
        assertThat(PhoneFormValidation.validateCountryCode("+1234")).isNull()
    }

    @Test
    fun `validateCountryCode - 5 hane TooLong`() {
        assertThat(PhoneFormValidation.validateCountryCode("+12345"))
            .isEqualTo(PhoneFormValidation.CountryCodeError.TooLong)
    }

    // ---- validatePhone ----

    @Test
    fun `validatePhone - bos Empty`() {
        assertThat(PhoneFormValidation.validatePhone(""))
            .isEqualTo(PhoneFormValidation.PhoneError.Empty)
    }

    @Test
    fun `validatePhone - 9 hane TooShort`() {
        assertThat(PhoneFormValidation.validatePhone("555555555"))
            .isEqualTo(PhoneFormValidation.PhoneError.TooShort)
    }

    @Test
    fun `validatePhone - 10 hane valid`() {
        assertThat(PhoneFormValidation.validatePhone("5551234567")).isNull()
    }

    @Test
    fun `validatePhone - 11 hane TooLong`() {
        assertThat(PhoneFormValidation.validatePhone("55512345678"))
            .isEqualTo(PhoneFormValidation.PhoneError.TooLong)
    }

    @Test
    fun `validatePhone - non-digit NonDigit`() {
        assertThat(PhoneFormValidation.validatePhone("555ABC1234"))
            .isEqualTo(PhoneFormValidation.PhoneError.NonDigit)
    }

    // ---- isFormValid ----

    @Test
    fun `isFormValid - tum alanlar dogru true`() {
        assertThat(
            PhoneFormValidation.isFormValid(
                name = "Ahmet Yilmaz",
                countryCode = "+90",
                phone = "5551234567"
            )
        ).isTrue()
    }

    @Test
    fun `isFormValid - isim bos false`() {
        assertThat(
            PhoneFormValidation.isFormValid(
                name = "",
                countryCode = "+90",
                phone = "5551234567"
            )
        ).isFalse()
    }

    @Test
    fun `isFormValid - telefon eksik hane false`() {
        assertThat(
            PhoneFormValidation.isFormValid(
                name = "Ahmet",
                countryCode = "+90",
                phone = "555123"
            )
        ).isFalse()
    }

    @Test
    fun `isFormValid - country code bozuk false`() {
        assertThat(
            PhoneFormValidation.isFormValid(
                name = "Ahmet",
                countryCode = "90",
                phone = "5551234567"
            )
        ).isFalse()
    }
}
