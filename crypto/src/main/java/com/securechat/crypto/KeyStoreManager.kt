package com.securechat.crypto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Android Keystore entegrasyonu.
 * Master key Android Keystore (TEE/StrongBox) uzerinde saklanir.
 * Tum hassas veriler (identity key, session state vb.) bu sinif ile
 * AES-256-GCM kullanilarak sifrelenir/cozulur.
 *
 * GUVENLIK: Private key ASLA loga yazilmaz.
 * GUVENLIK: Key material kullanim sonrasi sifirlanir.
 */
@Singleton
class KeyStoreManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val MASTER_KEY_ALIAS = "securechat_master_key"
        private const val AES_GCM_NOPADDING = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH = 128
        private const val GCM_IV_LENGTH = 12
    }

    private val keyStore: KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    /**
     * Veriyi AES-256-GCM ile sifreler.
     * Dondurulen format: [12 byte IV] + [sifrelenmis veri + GCM tag]
     */
    fun encrypt(data: ByteArray): ByteArray {
        val masterKey = getOrCreateMasterKey()
        val cipher = Cipher.getInstance(AES_GCM_NOPADDING)
        cipher.init(Cipher.ENCRYPT_MODE, masterKey)
        val iv = cipher.iv
        val encrypted = cipher.doFinal(data)
        // IV + encrypted data (GCM tag dahil)
        return iv + encrypted
    }

    /**
     * AES-256-GCM ile sifrelenmiş veriyi cozer.
     * Gelen format: [12 byte IV] + [sifrelenmis veri + GCM tag]
     */
    fun decrypt(data: ByteArray): ByteArray {
        val masterKey = getOrCreateMasterKey()
        val iv = data.copyOfRange(0, GCM_IV_LENGTH)
        val encrypted = data.copyOfRange(GCM_IV_LENGTH, data.size)
        val cipher = Cipher.getInstance(AES_GCM_NOPADDING)
        cipher.init(Cipher.DECRYPT_MODE, masterKey, GCMParameterSpec(GCM_TAG_LENGTH, iv))
        return cipher.doFinal(encrypted)
    }

    /**
     * Android Keystore'dan master key'i alir veya yeni olusturur.
     * AES-256, GCM modu, padding yok. TEE/StrongBox destegi ile donanim tabanli koruma.
     */
    private fun getOrCreateMasterKey(): SecretKey {
        if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
            return keyStore.getKey(MASTER_KEY_ALIAS, null) as SecretKey
        }
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .build()
        )
        return keyGenerator.generateKey()
    }
}
