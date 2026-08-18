package com.securechat.signaling

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Push tokenlarinin at-rest AEAD zarfi.
 *
 * V4 ciphertext, ham hesap UUID'sine degil keyed [userIndex] degerine
 * baglanir. Boylece PostgreSQL satiri baska bir hesaba tasindiginda acilmaz
 * ve kalici tabloda hesap UUID'si tutmak gerekmez.
 */
internal class FcmTokenCipher(
    keyBytes: ByteArray,
    private val random: SecureRandom = SecureRandom(),
) {
    private val key: SecretKeySpec

    init {
        require(keyBytes.size == KEY_BYTES) {
            "FCM token encryption key must be exactly 32 bytes"
        }
        key = SecretKeySpec(keyBytes.copyOf(), "AES")
    }

    fun seal(userIndex: String, plaintext: String): String =
        sealWithAad(V4_PREFIX, v4Aad(userIndex), plaintext)

    fun openV4(userIndex: String, stored: String): String? =
        openWithAad(V4_PREFIX, v4Aad(userIndex), stored)

    private fun sealWithAad(prefix: String, aad: ByteArray?, plaintext: String): String {
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        if (aad != null) cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return prefix + Base64.getEncoder().encodeToString(nonce + ciphertext)
    }

    private fun openWithAad(prefix: String, aad: ByteArray?, stored: String): String? {
        if (!stored.startsWith(prefix)) return null
        return try {
            val packed = Base64.getDecoder().decode(stored.removePrefix(prefix))
            require(packed.size >= NONCE_BYTES + TAG_BYTES)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(TAG_BITS, packed.copyOfRange(0, NONCE_BYTES)),
            )
            if (aad != null) cipher.updateAAD(aad)
            String(cipher.doFinal(packed.copyOfRange(NONCE_BYTES, packed.size)), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun v4Aad(userIndex: String): ByteArray =
        "securechat-fcm-token-v4\u0000$userIndex".toByteArray(Charsets.UTF_8)

    companion object {
        private const val V4_PREFIX = "v4:"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val KEY_BYTES = 32
        private const val NONCE_BYTES = 12
        private const val TAG_BYTES = 16
        private const val TAG_BITS = 128

        fun fromEnvironment(environment: Map<String, String> = System.getenv()): FcmTokenCipher {
            val encoded = SecretSource.required("FCM_TOKEN_ENCRYPTION_KEY", environment)
            val decoded = try {
                Base64.getDecoder().decode(encoded)
            } catch (_: IllegalArgumentException) {
                error("FCM_TOKEN_ENCRYPTION_KEY must be valid Base64")
            }
            require(decoded.size == KEY_BYTES) {
                "FCM_TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes"
            }
            return FcmTokenCipher(decoded)
        }
    }
}
