package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.GcmNonceSequence
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM ile bot'un Signal private key'lerini saran yardimci.
 *
 * Master key: BotApiConfig.botMasterKey (32 byte, env'den base64 decode).
 * Her wrap'ta process-random 64-bit prefix + atomik 32-bit counter ile yeni
 * 12-byte nonce uretilir; nonce DB'de ayri kolonda saklanir. `2^32`
 * invocation sonrasinda yeni seal fail-closed durur ve key rotasyonu gerekir.
 *
 * Authenticated encryption — GCM tag uzunlugu 128 bit.
 */
object KeyEncryptor {

    private const val NONCE_LENGTH = 12
    private const val TAG_LENGTH_BITS = 128
    private val BOUND_PREFIX = "SecureChatKeyV3\u0000".toByteArray(StandardCharsets.US_ASCII)
    private val LEGACY_BOUND_PREFIX =
        "SecureChatKeyV2\u0000".toByteArray(StandardCharsets.US_ASCII)
    private const val KEY_ID_BYTES = 9
    private val nonces = GcmNonceSequence(SecureRandom())

    const val PURPOSE_IDENTITY_PRIVATE = "identity-private"
    const val PURPOSE_ONE_TIME_PREKEY_PRIVATE = "one-time-prekey-private"
    const val PURPOSE_SIGNED_PREKEY_PRIVATE = "signed-prekey-private"

    data class WrappedKey(val ciphertext: ByteArray, val nonce: ByteArray) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is WrappedKey) return false
            return ciphertext.contentEquals(other.ciphertext) && nonce.contentEquals(other.nonce)
        }
        override fun hashCode(): Int = 31 * ciphertext.contentHashCode() + nonce.contentHashCode()
    }

    data class UnwrappedKey(val plaintext: ByteArray, val needsMigration: Boolean)

    fun wrap(plaintext: ByteArray, aad: ByteArray = byteArrayOf()): WrappedKey {
        val nonce = nonces.next()
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

    /**
     * Private key'i amacina ve DB satirina baglar. Ciphertext baska bir key
     * turune veya key_id'ye tasinirsa GCM etiketi dogrulanamaz.
     */
    fun wrapBound(plaintext: ByteArray, purpose: String, binding: String): WrappedKey {
        val keyId = keyId()
        val wrapped = wrap(plaintext, bindingAadV3(purpose, binding, keyId))
        return WrappedKey(BOUND_PREFIX + keyId + wrapped.ciphertext, wrapped.nonce)
    }

    /**
     * Eski, AAD'siz kayitlari yalnizca okur. Caller basarili okumadan hemen
     * sonra ayni satiri [wrapBound] ile yeniden yazmalidir.
     */
    fun unwrapBound(
        ciphertext: ByteArray,
        nonce: ByteArray,
        purpose: String,
        binding: String,
    ): UnwrappedKey = when {
        isBoundCiphertext(ciphertext) -> {
            require(ciphertext.size >= BOUND_PREFIX.size + KEY_ID_BYTES + 16) {
                "Bound key envelope is too short"
            }
            val storedKeyId = ciphertext.copyOfRange(
                BOUND_PREFIX.size,
                BOUND_PREFIX.size + KEY_ID_BYTES,
            )
            require(MessageDigest.isEqual(storedKeyId, keyId())) {
                "Unknown bot master key"
            }
            UnwrappedKey(
                plaintext = unwrap(
                    ciphertext.copyOfRange(BOUND_PREFIX.size + KEY_ID_BYTES, ciphertext.size),
                    nonce,
                    bindingAadV3(purpose, binding, storedKeyId),
                ),
                needsMigration = false,
            )
        }
        startsWith(ciphertext, LEGACY_BOUND_PREFIX) -> UnwrappedKey(
            plaintext = unwrap(
                ciphertext.copyOfRange(LEGACY_BOUND_PREFIX.size, ciphertext.size),
                nonce,
                bindingAadV2(purpose, binding),
            ),
            needsMigration = true,
        )
        else -> UnwrappedKey(
            plaintext = unwrap(ciphertext, nonce),
            needsMigration = true,
        )
    }

    fun isBoundCiphertext(ciphertext: ByteArray): Boolean =
        startsWith(ciphertext, BOUND_PREFIX)

    private fun bindingAadV3(
        purpose: String,
        binding: String,
        keyId: ByteArray,
    ): ByteArray {
        require(purpose.isNotBlank() && !purpose.contains('\u0000')) { "Invalid key purpose" }
        require(binding.isNotBlank() && !binding.contains('\u0000')) { "Invalid key binding" }
        val encodedKeyId = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(keyId)
        return "securechat-bot-key-v3\u0000$encodedKeyId\u0000$purpose\u0000$binding"
            .toByteArray(StandardCharsets.UTF_8)
    }

    private fun bindingAadV2(purpose: String, binding: String): ByteArray {
        require(purpose.isNotBlank() && !purpose.contains('\u0000')) { "Invalid key purpose" }
        require(binding.isNotBlank() && !binding.contains('\u0000')) { "Invalid key binding" }
        return "securechat-bot-key-v2\u0000$purpose\u0000$binding"
            .toByteArray(StandardCharsets.UTF_8)
    }

    private fun keyId(): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("securechat-bot-master-key-id-v1".toByteArray(StandardCharsets.US_ASCII))
        digest.update(0.toByte())
        digest.update(BotApiConfig.botMasterKey)
        return digest.digest().copyOfRange(0, KEY_ID_BYTES)
    }

    private fun startsWith(value: ByteArray, prefix: ByteArray): Boolean =
        value.size > prefix.size && value.copyOfRange(0, prefix.size).contentEquals(prefix)
}
