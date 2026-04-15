package com.securechat.storage.crypto

import android.content.SharedPreferences
import android.util.Base64
import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.storage.dao.IdentityDao
import com.securechat.storage.entity.IdentityEntity
import com.securechat.storage.model.TrustLevel
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Identity key store implementasyonu.
 * Uzak kimlikler Room DAO ile saklanir.
 * Yerel registrationId ve identityKeyPair ise SharedPreferences'da tutulur.
 * Not: Production'da EncryptedSharedPreferences kullanilmalidir.
 */
@Singleton
class CryptoIdentityStoreImpl @Inject constructor(
    private val identityDao: IdentityDao,
    private val prefs: SharedPreferences
) : CryptoIdentityStore {

    companion object {
        private const val KEY_REGISTRATION_ID = "local_registration_id"
        private const val KEY_IDENTITY_KEY_PAIR = "local_identity_key_pair"
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

    override suspend fun getLocalRegistrationId(): Int {
        return prefs.getInt(KEY_REGISTRATION_ID, -1)
    }

    override suspend fun storeLocalRegistrationId(registrationId: Int) {
        prefs.edit().putInt(KEY_REGISTRATION_ID, registrationId).apply()
    }

    override suspend fun getIdentityKeyPair(): ByteArray? {
        val encoded = prefs.getString(KEY_IDENTITY_KEY_PAIR, null) ?: return null
        return Base64.decode(encoded, Base64.NO_WRAP)
    }

    override suspend fun storeIdentityKeyPair(keyPair: ByteArray) {
        val encoded = Base64.encodeToString(keyPair, Base64.NO_WRAP)
        prefs.edit().putString(KEY_IDENTITY_KEY_PAIR, encoded).apply()
    }
}
