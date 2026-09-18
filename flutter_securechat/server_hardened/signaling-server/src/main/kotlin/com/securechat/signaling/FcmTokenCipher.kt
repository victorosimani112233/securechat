package com.securechat.signaling

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
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
    random: SecureRandom = SecureRandom(),
    nonceBudget: Long = 1L shl 32,
) {
    private val key: SecretKeySpec
    private val nonces = GcmNonceSequence(random, nonceBudget)
    private val keyId: String

    init {
        require(keyBytes.size == KEY_BYTES) {
            "FCM token encryption key must be exactly 32 bytes"
        }
        key = SecretKeySpec(keyBytes.copyOf(), "AES")
        keyId = deriveKeyId(keyBytes)
    }

    fun seal(userIndex: String, plaintext: String): String =
        sealWithAad("$V5_PREFIX$keyId:", v5Aad(userIndex), plaintext)

    fun open(userIndex: String, stored: String): String? = when {
        stored.startsWith(V5_PREFIX) -> {
            val separator = stored.indexOf(':', startIndex = V5_PREFIX.length)
            if (
                separator <= V5_PREFIX.length ||
                stored.substring(V5_PREFIX.length, separator) != keyId
            ) {
                null
            } else {
                openEncoded(v5Aad(userIndex), stored.substring(separator + 1))
            }
        }
        stored.startsWith(V4_PREFIX) ->
            openEncoded(v4Aad(userIndex), stored.removePrefix(V4_PREFIX))
        else -> null
    }

    fun needsMigration(stored: String): Boolean = stored.startsWith(V4_PREFIX)

    internal fun sealLegacyV4(userIndex: String, plaintext: String): String =
        sealWithAad(V4_PREFIX, v4Aad(userIndex), plaintext)

    private fun sealWithAad(prefix: String, aad: ByteArray?, plaintext: String): String {
        val nonce = nonces.next()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        if (aad != null) cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return prefix + Base64.getEncoder().encodeToString(nonce + ciphertext)
    }

    private fun openEncoded(aad: ByteArray, encoded: String): String? =
        try {
            val packed = Base64.getDecoder().decode(encoded)
            require(packed.size >= NONCE_BYTES + TAG_BYTES)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(TAG_BITS, packed.copyOfRange(0, NONCE_BYTES)),
            )
            cipher.updateAAD(aad)
            String(cipher.doFinal(packed.copyOfRange(NONCE_BYTES, packed.size)), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }

    private fun v4Aad(userIndex: String): ByteArray =
        "securechat-fcm-token-v4\u0000$userIndex".toByteArray(Charsets.UTF_8)

    private fun v5Aad(userIndex: String): ByteArray =
        "securechat-fcm-token-v5\u0000$keyId\u0000$userIndex".toByteArray(Charsets.UTF_8)

    private fun deriveKeyId(keyBytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("securechat-fcm-token-key-id-v1".toByteArray(StandardCharsets.US_ASCII))
        digest.update(0.toByte())
        digest.update(keyBytes)
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(digest.digest().copyOfRange(0, 9))
    }

    companion object {
        private const val V4_PREFIX = "v4:"
        private const val V5_PREFIX = "v5:"
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
            return FcmTokenCipher(
                SecretPolicy.requireStrongKey("FCM_TOKEN_ENCRYPTION_KEY", decoded),
            )
        }
    }
}
