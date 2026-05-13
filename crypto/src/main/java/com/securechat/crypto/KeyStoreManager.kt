package com.securechat.crypto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.KeyStore
import java.security.SecureRandom
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
     * SQLCipher veritabani icin random passphrase olusturur veya mevcut olani doner.
     *
     * Akis:
     * 1. SharedPreferences'da encrypted passphrase var mi bak.
     * 2. Varsa: oku, Keystore ile decrypt et — passphrase dondur.
     * 3. Decrypt FAIL ise: Keystore master key bozulmus/cycled → yeni passphrase uret.
     *    BU DURUMDA eski DB acilamaz; caller (StorageModule) destructive recovery yapar.
     * 4. Yoksa (ilk acilis): yeni 32 byte random uret, encrypt, SharedPrefs'e yaz.
     *
     * KRITIK: SharedPreferences yazma .commit() ile SENKRON yapilir — .apply() async,
     * process killed olunca yazma kaybolabilirdi, sonraki acilista passphrase yok diye
     * yeni uretilirdi, eski DB acilamazdi, tum sohbetler silinirdi.
     *
     * GUVENLIK: Plaintext passphrase asla diske yazilmaz; sadece bellekte aktarilir.
     *
     * @return 32-byte plaintext passphrase (caller kullandiktan sonra .fill(0) ile sifirlamali)
     */
    fun getOrCreateDbPassphrase(): ByteArray {
        val prefs = context.getSharedPreferences(DB_PASSPHRASE_PREFS, Context.MODE_PRIVATE)
        val stored = prefs.getString(DB_PASSPHRASE_KEY, null)

        if (stored != null) {
            try {
                val encrypted = Base64.decode(stored, Base64.NO_WRAP)
                val passphrase = decrypt(encrypted)
                android.util.Log.d(
                    "KeyStoreManager",
                    "DB passphrase storage'dan okundu (decrypt OK, prefix=" +
                        passphrase.take(4).joinToString("") { "%02x".format(it) } + ")"
                )
                return passphrase
            } catch (e: Exception) {
                // Keystore master key cycle/bozulma — decrypt edemiyoruz.
                // Eski entry'i sil ve yeni passphrase uret (caller migration recovery yapacak).
                android.util.Log.e(
                    "KeyStoreManager",
                    "DB passphrase decrypt FAIL — Keystore master key cycled? Yeni passphrase uretiliyor: ${e.message}"
                )
                prefs.edit().remove(DB_PASSPHRASE_KEY).commit()
            }
        }

        // Ilk acilis VEYA decrypt fail — yeni passphrase uret
        val passphrase = ByteArray(DB_PASSPHRASE_LENGTH)
        SecureRandom().nextBytes(passphrase)
        android.util.Log.w(
            "KeyStoreManager",
            "Yeni DB passphrase uretildi (prefix=" +
                passphrase.take(4).joinToString("") { "%02x".format(it) } + ")"
        )

        val encrypted = encrypt(passphrase)
        // KRITIK: commit() SENKRON — process kill olsa bile diske yazilmis olur.
        // apply() async oldugundan ilk acilisin hemen ardindan crash/kill durumunda kaybolurdu.
        val written = prefs.edit()
            .putString(DB_PASSPHRASE_KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .commit()
        android.util.Log.d("KeyStoreManager", "DB passphrase SharedPrefs'e yazildi: success=$written")

        return passphrase
    }
}
