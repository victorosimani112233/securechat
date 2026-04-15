package com.securechat.crypto

import com.securechat.crypto.model.KeyBundle
import com.securechat.crypto.store.CryptoIdentityStore
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.util.KeyHelper
import javax.inject.Inject
import javax.inject.Singleton

/**
 * PreKey uretimi ve yonetimi.
 * Ilk kayit sirasinda identity key pair, registration ID, one-time PreKey'ler
 * ve signed PreKey uretir. Periyodik olarak PreKey stogunu kontrol eder
 * ve gerektiginde yeni batch uretir.
 *
 * Key hierarchy:
 * - Identity Key Pair: Uzun omurlu, cihaz basina 1
 * - Signed PreKey: Orta omurlu, her 7 gunde rotate edilir
 * - One-Time PreKey: Tek kullanimlik, batch halinde uretilir
 */
@Singleton
class PreKeyManager @Inject constructor(
    private val protocolStore: SecureChatProtocolStore,
    private val identityStore: CryptoIdentityStore
) {
    companion object {
        /** Her batch'te uretilecek one-time PreKey sayisi */
        const val PREKEY_BATCH_SIZE = 100

        /** Bu esik altina dusulurse yeni PreKey batch uretilir */
        const val PREKEY_REFRESH_THRESHOLD = 20

        /** Signed PreKey rotation periyodu (gun) */
        const val SIGNED_PREKEY_ROTATION_DAYS = 7L
    }

    /**
     * Ilk kayit sirasinda tum kriptografik anahtarlari uretir.
     * Identity key pair, registration ID, one-time PreKey'ler ve signed PreKey olusturur.
     *
     * @return Uretilen key bundle (sunucuya gonderilmek uzere)
     */
    suspend fun generateInitialKeys(): KeyBundle {
        val identityKeyPair = KeyHelper.generateIdentityKeyPair()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val preKeys = KeyHelper.generatePreKeys(0, PREKEY_BATCH_SIZE)
        val signedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, 0)

        // Lokal store'a kaydet
        identityStore.storeIdentityKeyPair(identityKeyPair.serialize())
        identityStore.storeLocalRegistrationId(registrationId)
        preKeys.forEach { protocolStore.storePreKey(it.id, it) }
        protocolStore.storeSignedPreKey(signedPreKey.id, signedPreKey)

        return KeyBundle(identityKeyPair.publicKey, registrationId, preKeys, signedPreKey)
    }

    /**
     * Mevcut PreKey stogunu kontrol eder ve esik altindaysa yeni batch uretir.
     *
     * @return Yeni uretilen PreKey listesi, veya yeterli stok varsa null
     */
    suspend fun replenishPreKeysIfNeeded(): List<PreKeyRecord>? {
        val availableCount = protocolStore.getAvailablePreKeyCount()
        if (availableCount < PREKEY_REFRESH_THRESHOLD) {
            val nextId = protocolStore.getNextPreKeyId()
            val newPreKeys = KeyHelper.generatePreKeys(nextId, PREKEY_BATCH_SIZE)
            newPreKeys.forEach { protocolStore.storePreKey(it.id, it) }
            return newPreKeys
        }
        return null
    }

    /**
     * Signed PreKey'i rotate eder. Yeni signed PreKey uretir ve store'a kaydeder.
     * Eski signed PreKey'ler bir sure daha tutulur (gec gelen mesajlar icin).
     */
    suspend fun rotateSignedPreKey() {
        val identityKeyPair = IdentityKeyPair(
            identityStore.getIdentityKeyPair()
                ?: throw IllegalStateException("Identity key pair not initialized")
        )
        val currentSignedPreKeys = protocolStore.loadSignedPreKeys()
        val nextId = if (currentSignedPreKeys.isEmpty()) 0 else {
            currentSignedPreKeys.maxOf { it.id } + 1
        }
        val newSignedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, nextId)
        protocolStore.storeSignedPreKey(newSignedPreKey.id, newSignedPreKey)
    }
}
