package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM ile bot'un Signal private key'lerini saran yardimci.
 *
 * Master key: BotApiConfig.botMasterKey (32 byte, env'den base64 decode).
 * Her wrap'ta yeni 12-byte random nonce uretilir; nonce DB'de ayri kolonda
 * birlikte saklanir (gizli degil, key reuse onlemi).
 *
 * Authenticated encryption — GCM tag uzunlugu 128 bit.
 */
object KeyEncryptor {

    private const val NONCE_LENGTH = 12
    private const val TAG_LENGTH_BITS = 128
    private val rng = SecureRandom()

    data class WrappedKey(val ciphertext: ByteArray, val nonce: ByteArray) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is WrappedKey) return false
            return ciphertext.contentEquals(other.ciphertext) && nonce.contentEquals(other.nonce)
        }
        override fun hashCode(): Int = 31 * ciphertext.contentHashCode() + nonce.contentHashCode()
    }

    fun wrap(plaintext: ByteArray, aad: ByteArray = byteArrayOf()): WrappedKey {
        val nonce = ByteArray(NONCE_LENGTH).also { rng.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(BotApiConfig.botMasterKey, "AES"),
            GCMParameterSpec(TAG_LENGTH_BITS, nonce)
        )
        if (aad.isNotEmpty()) cipher.updateAAD(aad)
        val ct = cipher.doFinal(plaintext)
        return WrappedKey(ct, nonce)
    }

    fun unwrap(wrapped: WrappedKey, aad: ByteArray = byteArrayOf()): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(BotApiConfig.botMasterKey, "AES"),
            GCMParameterSpec(TAG_LENGTH_BITS, wrapped.nonce)
        )
        if (aad.isNotEmpty()) cipher.updateAAD(aad)
        return cipher.doFinal(wrapped.ciphertext)
    }

    fun unwrap(
        ciphertext: ByteArray,
        nonce: ByteArray,
        aad: ByteArray = byteArrayOf()
    ): ByteArray = unwrap(WrappedKey(ciphertext, nonce), aad)
}
