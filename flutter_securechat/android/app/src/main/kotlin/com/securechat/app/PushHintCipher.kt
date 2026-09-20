package com.securechat.app

import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal object PushHintCipher {
    private const val WIRE_PREFIX = "v1."
    private const val WIRE_LENGTH = 42
    private const val NONCE_BYTES = 12
    private const val TAG_BYTES = 16
    private const val TAG_BITS = TAG_BYTES * 8
    private val aad = "securechat-push-hint:v1".toByteArray(Charsets.US_ASCII)

    fun open(key: ByteArray, wire: String): Char? {
        if (key.size != 32 || wire.length != WIRE_LENGTH || !wire.startsWith(WIRE_PREFIX)) {
            return null
        }
        return try {
            val payload = Base64.decode(
                wire.removePrefix(WIRE_PREFIX),
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )
            if (payload.size != NONCE_BYTES + 1 + TAG_BYTES) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, payload.copyOfRange(0, NONCE_BYTES))
            )
            cipher.updateAAD(aad)
            val plaintext = cipher.doFinal(payload.copyOfRange(NONCE_BYTES, payload.size))
            plaintext.singleOrNull()?.toInt()?.toChar()?.takeIf { it == 'c' || it == 'm' }
        } catch (_: Exception) {
            null
        }
    }
}
