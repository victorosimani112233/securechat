package com.securechat.contacts

/**
 * Kullanici girisindeki telefon numaralarini normalize eder.
 * Cesitli formatlari destekler: "5551234567", "05551234567", "905551234567", "+905551234567".
 * Sonuc olarak yalnizca rakamlardan olusan userId formatinda doner (ornegin "905551234567").
 *
 * Bu sinif libphonenumber bagimliligi olmadan calisan hafif bir yardimcidir.
 * ContentResolver'dan gelen numaralar icin ContactsProvider.normalizePhoneNumber() kullanilir.
 */
object PhoneNumberNormalizer {

    /**
     * Kullanicinin girdigi telefon numarasini userId formatina normalize eder.
     * Tum ozel karakterleri (+, bosluk, tire, parantez) kaldirir ve
     * Turkiye numarasi formatina gore duzeltme yapar.
     *
     * @param input Kullanicinin girdigi ham telefon numarasi
     * @return Yalnizca rakamlardan olusan normalize edilmis numara (ornegin "905551234567")
     */
    fun normalizeToUserId(input: String): String {
        // +, bosluk, tire, parantez gibi karakterleri kaldir
        val digits = input.replace(Regex("[^0-9]"), "")

        return when {
            // "05551234567" -> "905551234567" (bastaki 0'i atla, 90 on eki ekle)
            digits.startsWith("05") && digits.length == 11 -> "90${digits.substring(1)}"
            // "5551234567" -> "905551234567" (Turk cep numarasi: 5 ile baslar, 10 hane)
            digits.startsWith("5") && digits.length == 10 -> "90$digits"
            // Zaten "905551234567" veya baska ulke formatinda
            else -> digits
        }
    }

    /**
     * Telefon numarasini gosterim formatina cevirir.
     * Ornegin: "905551234567" -> "+90 555 123 45 67"
     *
     * @param userId Normalize edilmis userId (yalnizca rakam)
     * @return Okunabilir telefon numarasi formati
     */
    fun formatForDisplay(userId: String): String {
        // Turkiye numarasi: 90XXXXXXXXXX (12 hane)
        if (userId.length == 12 && userId.startsWith("90")) {
            val areaCode = userId.substring(2, 5)
            val part1 = userId.substring(5, 8)
            val part2 = userId.substring(8, 10)
            val part3 = userId.substring(10, 12)
            return "+90 $areaCode $part1 $part2 $part3"
        }
        // Diger formatlar: basina + ekle
        return "+$userId"
    }
}
