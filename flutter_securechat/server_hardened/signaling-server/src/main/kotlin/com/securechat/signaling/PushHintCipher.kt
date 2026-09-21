package com.securechat.signaling

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Encrypts the fixed-width call/message wake classification for a device. */
internal class PushHintCipher(
    private val random: SecureRandom = SecureRandom(),
) {
    fun seal(key: ByteArray, kind: Char): String {
        require(key.size == KEY_BYTES) { "Push hint key must be 32 bytes" }
        require(kind == CALL_KIND || kind == MESSAGE_KIND) { "Invalid push hint kind" }
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(TAG_BITS, nonce),
        )
        cipher.updateAAD(AAD)
        val ciphertext = cipher.doFinal(byteArrayOf(kind.code.toByte()))
        val payload = nonce + ciphertext
        return WIRE_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(payload)
    }

    internal fun open(key: ByteArray, wire: String): Char? {
        if (key.size != KEY_BYTES || wire.length != WIRE_LENGTH || !wire.startsWith(WIRE_PREFIX)) {
            return null
        }
        return try {
            val encoded = wire.removePrefix(WIRE_PREFIX)
            val payload = Base64.getUrlDecoder().decode(encoded)
            if (payload.size != NONCE_BYTES + 1 + TAG_BYTES) return null
            // Reject alternate Base64 spellings that decode to the same bytes.
            // A fixed-width opaque field must have one canonical wire form.
            if (Base64.getUrlEncoder().withoutPadding().encodeToString(payload) != encoded) {
                return null
            }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, payload.copyOfRange(0, NONCE_BYTES)),
            )
            cipher.updateAAD(AAD)
            val plaintext = cipher.doFinal(payload.copyOfRange(NONCE_BYTES, payload.size))
            plaintext.singleOrNull()?.toInt()?.toChar()?.takeIf {
                it == CALL_KIND || it == MESSAGE_KIND
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val CALL_KIND = 'c'
        const val MESSAGE_KIND = 'm'
        const val WIRE_LENGTH = 42
        private const val WIRE_PREFIX = "v1."
        private const val KEY_BYTES = 32
        private const val NONCE_BYTES = 12
        private const val TAG_BYTES = 16
        private const val TAG_BITS = TAG_BYTES * 8
        private val AAD = "securechat-push-hint:v1".toByteArray(Charsets.US_ASCII)
    }
}
