package com.securechat.contacts

import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Telefon numarasini AES-256-GCM ile sifreleme/cozme yardimcisi.
 *
 * Sunucuda saklanmak uzere telefon numarasi sifrelenip gonderilir.
 * Sunucu anahtari bilmediginden plaintext numarayi ASLA goremez.
 * Bilinmeyen UUID'den mesaj geldiginde sifreli numara cekilip istemcide cozulur.
 *
 * IV (12 byte) ciphertext'in basina eklenir: [IV (12)][ciphertext+tag]
 * Sonuc Base64 URL-safe olarak encode edilir.
 */
object PhoneEncryptor {

    // Uygulama icine gomulu 256-bit anahtar (32 byte)
    // Production'da bu deger obfuscation ile korunmali
    private val KEY_BYTES = byteArrayOf(
        0x5A, 0x1E, 0x3C.toByte(), 0x7F, 0x2B, 0x9D.toByte(), 0x4E, 0x6A,
        0x8F.toByte(), 0x0D, 0x3B, 0x7C, 0x1A, 0x5E, 0x9F.toByte(), 0x2C,
        0x4D, 0x6B, 0x8E.toByte(), 0x0F, 0x3A, 0x7D, 0x1B, 0x5F,
        0x9E.toByte(), 0x2D, 0x4C, 0x6F, 0x8A.toByte(), 0x0E, 0x3D, 0x7E
    )

    private const val AES_GCM = "AES/GCM/NoPadding"
    private const val IV_SIZE = 12
    private const val TAG_SIZE = 128

    private val secretKey = SecretKeySpec(KEY_BYTES, "AES")

    /**
     * Telefon numarasini AES-256-GCM ile sifreler.
     * @param phoneNumber Plaintext telefon numarasi
     * @return Base64 URL-safe encoded "[IV][ciphertext+tag]"
     */
    fun encrypt(phoneNumber: String): String {
        val cipher = Cipher.getInstance(AES_GCM)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv // otomatik random IV
        val cipherText = cipher.doFinal(phoneNumber.toByteArray(Charsets.UTF_8))
        // IV + ciphertext birlestir
        val combined = ByteArray(iv.size + cipherText.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(cipherText, 0, combined, iv.size, cipherText.size)
        return Base64.encodeToString(combined, Base64.URL_SAFE or Base64.NO_WRAP)
    }

    /**
     * AES-256-GCM ile sifreli telefon numarasini cozer.
     * @param encryptedPhone Base64 URL-safe encoded sifreli veri
     * @return Plaintext telefon numarasi, cozulemezse null
     */
    fun decrypt(encryptedPhone: String): String? {
        return try {
            val combined = Base64.decode(encryptedPhone, Base64.URL_SAFE or Base64.NO_WRAP)
            if (combined.size < IV_SIZE + 1) return null
            val iv = combined.copyOfRange(0, IV_SIZE)
            val cipherText = combined.copyOfRange(IV_SIZE, combined.size)
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(TAG_SIZE, iv))
            String(cipher.doFinal(cipherText), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
}
