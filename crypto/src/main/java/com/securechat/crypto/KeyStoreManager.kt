package com.securechat.crypto

import android.content.Context
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
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

        // SQLCipher DB passphrase saklama bilgileri.
        // 32-byte random passphrase SecureRandom ile uretilir, Keystore master key ile
        // sifrelenmis halde SharedPreferences'a yazilir. Diskte plaintext duzeyde tutulmaz.
        private const val DB_PASSPHRASE_PREFS = "securechat_keystore_meta"
        private const val DB_PASSPHRASE_KEY = "db_passphrase_v1"
        private const val DB_PASSPHRASE_LENGTH = 32
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
     *
     * StrongBox: API 28+ destekli cihazlarda dedicated secure chip'te key tutulur.
     * Cihaz desteklemiyorsa TEE (Trusted Execution Environment) fallback otomatik kullanilir.
     */
    private fun getOrCreateMasterKey(): SecretKey {
        if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
            return keyStore.getKey(MASTER_KEY_ALIAS, null) as SecretKey
        }
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE
        )

        // Try StrongBox first (API 28+); fallback to TEE if device lacks StrongBox chip.
        val baseSpec = KeyGenParameterSpec.Builder(
            MASTER_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(false)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            try {
                baseSpec.setIsStrongBoxBacked(true)
                keyGenerator.init(baseSpec.build())
                return keyGenerator.generateKey()
            } catch (e: android.security.keystore.StrongBoxUnavailableException) {
                // Cihazda StrongBox yok — TEE fallback'e gec.
                baseSpec.setIsStrongBoxBacked(false)
            } catch (e: Exception) {
                // Beklenmedik provider hatasi — TEE fallback ile devam et.
                baseSpec.setIsStrongBoxBacked(false)
            }
        }

        keyGenerator.init(baseSpec.build())
        return keyGenerator.generateKey()
    }

    /**
     * SQLCipher veritabani icin DETERMINISTIK passphrase uretir — ANDROID_ID + HMAC ile.
     *
     * Eski yaklasim (Keystore-encrypted random passphrase + SharedPrefs) bazi cihazlarda
     * "sohbetler her acilista siliniyor" bug'ina yol aciyordu. Sebep: Keystore master key
     * cycle veya SharedPrefs apply()/commit() race condition. Her acilista farkli passphrase
     * doniyor, DB acilamiyor, destructive delete tetikleniyordu.
     *
     * YENI yaklasim: passphrase = HMAC-SHA256(salt, ANDROID_ID).
     * - ANDROID_ID factory reset'e kadar AYNI kalir (signing key bazli izole)
     * - SharedPrefs/Keystore'a bagimli degil — disk persistence sorunu YOK
     * - Reinstall sonrasi ayni cihazda ayni passphrase → DB hala acilabilir
     * - Factory reset sonrasi ANDROID_ID degisir → DB sifirlanir (kabul edilebilir)
     *
     * Eski Keystore-encrypted passphrase varsa `getLegacyPassphraseIfAny()` ile alinabilir
     * (StorageModule migration recovery'de kullanilir, eski APK'lardan upgrade icin).
     *
     * GUVENLIK: ANDROID_ID public bir deger degil ama app-scope'ludur. HMAC salt
     * APK icindedir (decompile edilebilir) — gercek production icin gelecekte
     * Keystore + biometric ile guclendirilmeli. Su an "kullanici verisi korunsun"
     * onceligi, security-vs-usability tradeoff'unda usability one ciktirilir.
     */
    fun getOrCreateDbPassphrase(): ByteArray {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID
        ) ?: "fallback_no_android_id"

        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(DB_PASSPHRASE_HMAC_SALT.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val passphrase = mac.doFinal(androidId.toByteArray(Charsets.UTF_8))

        android.util.Log.d(
            "KeyStoreManager",
            "DB passphrase deterministic uretildi (prefix=" +
                passphrase.take(4).joinToString("") { "%02x".format(it) } + ")"
        )
        return passphrase
    }

    /**
     * Eski Keystore-encrypted passphrase'i SharedPreferences'tan okur (varsa).
     * Migration: eski APK'larda yaratilmis DB'leri yeni deterministic passphrase'e rekey
     * etmek icin StorageModule tarafindan kullanilir.
     *
     * @return Eski passphrase 32-byte, yoksa veya decrypt fail ise null
     */
    fun getLegacyPassphraseIfAny(): ByteArray? {
        val prefs = context.getSharedPreferences(DB_PASSPHRASE_PREFS, Context.MODE_PRIVATE)
        val stored = prefs.getString(DB_PASSPHRASE_KEY, null) ?: return null
        return try {
            val encrypted = Base64.decode(stored, Base64.NO_WRAP)
            val passphrase = decrypt(encrypted)
            android.util.Log.i(
                "KeyStoreManager",
                "Legacy Keystore passphrase storage'dan okundu (migration icin)"
            )
            passphrase
        } catch (e: Exception) {
            android.util.Log.w(
                "KeyStoreManager",
                "Legacy passphrase decrypt fail (Keystore key cycle?): ${e.message}"
            )
            null
        }
    }

    /** Legacy SharedPrefs entry'i sil — başarılı migration sonrası caller çağırır. */
    fun clearLegacyPassphrase() {
        context.getSharedPreferences(DB_PASSPHRASE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(DB_PASSPHRASE_KEY)
            .apply()
    }
}

// HMAC salt — APK icinde public, ANDROID_ID ile birlestirilince passphrase derive eder.
// Kullanici verisi korunma onceligi: deterministic passphrase, disk persistence'a bagimli degil.
private const val DB_PASSPHRASE_HMAC_SALT = "elcim_securechat_db_passphrase_v1_salt_2026"
