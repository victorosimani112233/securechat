package com.securechat.storage.crypto

import android.content.SharedPreferences
import android.util.Base64
import com.securechat.crypto.KeyStoreManager
import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.storage.dao.IdentityDao
import com.securechat.storage.entity.IdentityEntity
import com.securechat.storage.model.TrustLevel
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Identity key store implementasyonu.
 * Uzak kimlikler Room DAO ile saklanir.
 *
 * GUVENLIK: Yerel identity key pair Android Keystore master key ile (AES-256-GCM)
 * sifrelenmis halde SharedPreferences'a yazilir. Plaintext private key diske ASLA yazilmaz.
 * registrationId hassas degil — int olarak plain tutulur.
 *
 * Migration: KEY_IDENTITY_KEY_PAIR (eski plaintext Base64) varsa, ilk okumada decrypt
 * dener; basarisizsa eski plaintext olarak okuyup KEY_IDENTITY_KEY_PAIR_V2 (encrypted)
 * altina migrate eder. Eski entry silinir.
 */
@Singleton
class CryptoIdentityStoreImpl @Inject constructor(
    private val identityDao: IdentityDao,
    @Named("crypto") private val prefs: SharedPreferences,
    private val keyStoreManager: KeyStoreManager
) : CryptoIdentityStore {

    companion object {
        private const val KEY_REGISTRATION_ID = "local_registration_id"
        // Eski plaintext Base64 entry — migration sonrasi silinir.
        private const val KEY_IDENTITY_KEY_PAIR_LEGACY = "local_identity_key_pair"
        // Yeni: Keystore-encrypted, Base64-encoded entry.
        private const val KEY_IDENTITY_KEY_PAIR_ENCRYPTED = "local_identity_key_pair_v2"
    }

    override suspend fun loadIdentity(name: String): ByteArray? =
        identityDao.get(name)?.identityKey

    override suspend fun storeIdentity(name: String, identityKey: ByteArray): Boolean {
        val existing = identityDao.get(name)
        identityDao.insert(
            IdentityEntity(
                addressName = name,
                identityKey = identityKey,
                trustLevel = TrustLevel.TRUSTED_UNVERIFIED
            )
        )
        // Eger onceden farkli bir anahtar varsa true doner (anahtar degisti sinyali)
        return existing != null && !existing.identityKey.contentEquals(identityKey)
    }

    override suspend fun deleteIdentity(name: String) {
        identityDao.delete(name)
    }

    override suspend fun getLocalRegistrationId(): Int {
        return prefs.getInt(KEY_REGISTRATION_ID, -1)
    }

    override suspend fun storeLocalRegistrationId(registrationId: Int) {
        prefs.edit().putInt(KEY_REGISTRATION_ID, registrationId).apply()
    }

    override suspend fun getIdentityKeyPair(): ByteArray? {
        // Once yeni (encrypted) entry'i dene.
        prefs.getString(KEY_IDENTITY_KEY_PAIR_ENCRYPTED, null)?.let { encryptedBase64 ->
            val encrypted = Base64.decode(encryptedBase64, Base64.NO_WRAP)
            return keyStoreManager.decrypt(encrypted)
        }

        // Migration: eski plaintext entry varsa oku, encrypted'a yaz, eski siyl.
        val legacyEncoded = prefs.getString(KEY_IDENTITY_KEY_PAIR_LEGACY, null) ?: return null
        val keyPair = Base64.decode(legacyEncoded, Base64.NO_WRAP)
        storeIdentityKeyPair(keyPair)
        prefs.edit().remove(KEY_IDENTITY_KEY_PAIR_LEGACY).apply()
        return keyPair
    }

    override suspend fun storeIdentityKeyPair(keyPair: ByteArray) {
        // Keystore master key ile sifrele → Base64 → SharedPreferences.
        // Plaintext private key diske yazilmaz.
        val encrypted = keyStoreManager.encrypt(keyPair)
        val encoded = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        prefs.edit().putString(KEY_IDENTITY_KEY_PAIR_ENCRYPTED, encoded).apply()
    }
}
