package com.securechat.app.backup

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM sifreleme yardimcisi.
 * Kullanici sifresinden PBKDF2 ile anahtar turetir, veriyi AES-GCM ile sifreler.
 *
 * Dosya formati: [salt:32][iv:12][sifreli_veri]
 */
object BackupCrypto {

    private const val PBKDF2_ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256
    private const val SALT_LENGTH = 32
    private const val IV_LENGTH = 12
    private const val GCM_TAG_LENGTH = 128

    /**
     * Veriyi AES-256-GCM ile sifreler.
     * @return salt + iv + ciphertext
     */
    fun encrypt(plainData: ByteArray, password: String): ByteArray {
        val salt = ByteArray(SALT_LENGTH).also { SecureRandom().nextBytes(it) }
        val iv = ByteArray(IV_LENGTH).also { SecureRandom().nextBytes(it) }

        val key = deriveKey(password, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH, iv))

        val cipherText = cipher.doFinal(plainData)

        // salt + iv + ciphertext
        return salt + iv + cipherText
    }

    /**
     * AES-256-GCM ile sifreli veriyi cozer.
     * @return plaintext veya null (sifre yanlis / veri bozuk)
     */
    fun decrypt(encryptedData: ByteArray, password: String): ByteArray? {
        if (encryptedData.size < SALT_LENGTH + IV_LENGTH + 1) return null

        return try {
            val salt = encryptedData.copyOfRange(0, SALT_LENGTH)
            val iv = encryptedData.copyOfRange(SALT_LENGTH, SALT_LENGTH + IV_LENGTH)
            val cipherText = encryptedData.copyOfRange(SALT_LENGTH + IV_LENGTH, encryptedData.size)

            val key = deriveKey(password, salt)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH, iv))

            cipher.doFinal(cipherText)
        } catch (e: Exception) {
            // Sifre yanlis veya veri bozuk
            null
        }
    }

    private fun deriveKey(password: String, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(password.toCharArray(), salt, PBKDF2_ITERATIONS, KEY_LENGTH_BITS)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val keyBytes = factory.generateSecret(spec).encoded
        spec.clearPassword()
        return SecretKeySpec(keyBytes, "AES")
    }
}
