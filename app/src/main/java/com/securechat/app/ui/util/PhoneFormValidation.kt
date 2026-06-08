package com.securechat.app.ui.util

/**
 * Telefon dogrulama / kayit formu icin saf validasyon kurallari.
 *
 * UI'dan bagimsiz — sadece String girdi, ValidationResult cikti. Bu sayede
 * unit test edilebilir ve PhoneVerificationScreen, OtpVerificationScreen
 * gibi farkli ekranlarda yeniden kullanilabilir.
 *
 * Best practice gerekce:
 *   - Composable icinde kosulu hata yazmak yerine validation katmaninda toplama
 *   - Tek bir kaynak gercek (formun gecerliligi) → CTA enable, isError,
 *     supportingText hepsi ayni karardan turetilir.
 */
object PhoneFormValidation {

    /** Maks isim uzunlugu — DB ve UI'da reasonable sinir. */
    const val MAX_NAME_LENGTH = 50

    /** Min isim uzunlugu — placeholder "A" yi geri cevir. */
    const val MIN_NAME_LENGTH = 2

    /** TR telefon yerel kismi tam uzunlugu (5XX XXX XX XX -> 10 rakam). */
    const val PHONE_LOCAL_LENGTH = 10

    /** Ulke kodu min/max — +1, +90, +993 gibi 1-4 hane. */
    const val COUNTRY_CODE_MIN_DIGITS = 1
    const val COUNTRY_CODE_MAX_DIGITS = 4

    /**
     * Isim validasyonu.
     *
     * Kurallar:
     *  - Bos olamaz (trim sonrasi).
     *  - En az MIN_NAME_LENGTH karakter (trim sonrasi).
     *  - En fazla MAX_NAME_LENGTH karakter.
     *  - Sadece harf, bosluk, tire, kesme isareti (cogu isim icin yeterli).
     */
    fun validateName(input: String): NameError? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return NameError.Empty
        if (trimmed.length < MIN_NAME_LENGTH) return NameError.TooShort
        if (input.length > MAX_NAME_LENGTH) return NameError.TooLong
        // Harf (Unicode L) + bosluk + tire + kesme. Sayilar ve sembol reddedilir.
        val nameRegex = Regex("^[\\p{L}\\s'\\-]+$")
        if (!nameRegex.matches(trimmed)) return NameError.InvalidChars
        return null
    }

    /**
     * Ulke kodu validasyonu. "+90", "+1", "+993" gibi.
     */
    fun validateCountryCode(input: String): CountryCodeError? {
        if (input.isEmpty()) return CountryCodeError.Empty
        if (!input.startsWith("+")) return CountryCodeError.MissingPlus
        val digits = input.removePrefix("+")
        if (digits.isEmpty()) return CountryCodeError.Empty
        if (!digits.all { it.isDigit() }) return CountryCodeError.NonDigit
        if (digits.length < COUNTRY_CODE_MIN_DIGITS) return CountryCodeError.TooShort
        if (digits.length > COUNTRY_CODE_MAX_DIGITS) return CountryCodeError.TooLong
        return null
    }

    /**
     * Telefon yerel kismi validasyonu. 10 hane bekliyoruz (Turkiye varsayim).
     * Input zaten OutlinedTextField onChange'inde sadece digit filtrelendigi icin
     * non-digit gelmeyecektir, yine de defansif kontrol var.
     */
    fun validatePhone(input: String): PhoneError? {
        if (input.isEmpty()) return PhoneError.Empty
        if (!input.all { it.isDigit() }) return PhoneError.NonDigit
        if (input.length < PHONE_LOCAL_LENGTH) return PhoneError.TooShort
        if (input.length > PHONE_LOCAL_LENGTH) return PhoneError.TooLong
        // TR cep telefonlari 5 ile basliyor — yumusak kontrol, hata vermez sadece
        // CTA'yi blocklamayiz. Bu kurali ekstra istenirse buraya eklenir.
        return null
    }

    /**
     * Formun tamaminin gecerli olup olmadigi. CTA enable kararinda kullanilir.
     */
    fun isFormValid(name: String, countryCode: String, phone: String): Boolean =
        validateName(name) == null &&
            validateCountryCode(countryCode) == null &&
            validatePhone(phone) == null

    sealed class NameError {
        object Empty : NameError()
        object TooShort : NameError()
        object TooLong : NameError()
        object InvalidChars : NameError()
    }

    sealed class CountryCodeError {
        object Empty : CountryCodeError()
        object MissingPlus : CountryCodeError()
        object NonDigit : CountryCodeError()
        object TooShort : CountryCodeError()
        object TooLong : CountryCodeError()
    }

    sealed class PhoneError {
        object Empty : PhoneError()
        object NonDigit : PhoneError()
        object TooShort : PhoneError()
        object TooLong : PhoneError()
    }
}
