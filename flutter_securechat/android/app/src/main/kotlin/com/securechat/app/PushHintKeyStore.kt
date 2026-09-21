package com.securechat.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Stores the exportable device hint key wrapped by a non-exportable Keystore key. */
internal object PushHintKeyStore {
    private const val KEY_ALIAS = "securechat_push_hint_wrap_v1"
    private const val PREFS = "securechat_push_hint"
    private const val WRAPPED_KEY = "wrapped_device_key_v1"
    private const val RAW_KEY_BYTES = 32
    private const val NONCE_BYTES = 12
    private const val TAG_BITS = 128

    @Synchronized
    fun getOrCreateEncoded(context: Context): String {
        val raw = read(context) ?: create(context)
        Log.i("SecureChatPushHint", "device_hint_key_ready")
        return Base64.encodeToString(
            raw,
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        )
    }

    @Synchronized
    fun read(context: Context): ByteArray? {
        val encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(WRAPPED_KEY, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= NONCE_BYTES) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                wrappingKey(),
                GCMParameterSpec(TAG_BITS, payload.copyOfRange(0, NONCE_BYTES))
            )
            cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.US_ASCII))
            cipher.doFinal(payload.copyOfRange(NONCE_BYTES, payload.size))
                .takeIf { it.size == RAW_KEY_BYTES }
        } catch (_: Exception) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().remove(WRAPPED_KEY).commit()
            runCatching {
                KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    .deleteEntry(KEY_ALIAS)
            }
            null
        }
    }

    private fun create(context: Context): ByteArray {
        val raw = ByteArray(RAW_KEY_BYTES).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
        cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.US_ASCII))
        val payload = cipher.iv + cipher.doFinal(raw)
        val persisted = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(WRAPPED_KEY, Base64.encodeToString(payload, Base64.NO_WRAP))
            .commit()
        check(persisted) { "Push hint key persistence failed" }
        return raw
    }

    private fun wrappingKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        ).apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build()
            )
        }.generateKey()
    }
}
