package com.securechat.crypto

import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import kotlinx.coroutines.runBlocking
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.InvalidKeyIdException
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.PreKeyStore
import org.whispersystems.libsignal.state.SessionRecord
import org.whispersystems.libsignal.state.SessionStore
import org.whispersystems.libsignal.state.SignalProtocolStore
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyStore
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Signal Protocol'un gerektirdigi tum store interface'lerini implement eder.
 * Async storage interface'lerini Signal'in senkron interface'lerine koprular.
 *
 * NOT: Signal Protocol senkron erisim gerektirdiginden, storage cagrilari
 * runBlocking ile yapilir. Bu sinif yalnizca Signal Protocol'un ihtiyac
 * duydugu senkron metodlari saglar.
 *
 * GUVENLIK: Private key ASLA loga yazilmaz.
 */
@Singleton
class SecureChatProtocolStore @Inject constructor(
    private val preKeyStore: CryptoPreKeyStore,
    private val signedPreKeyStore: CryptoSignedPreKeyStore,
    private val sessionStore: CryptoSessionStore,
    private val identityStore: CryptoIdentityStore
) : SignalProtocolStore {

    // --- IdentityKeyStore ---

    override fun getIdentityKeyPair(): IdentityKeyPair = runBlocking {
        val bytes = identityStore.getIdentityKeyPair()
            ?: throw IllegalStateException("Identity key pair not found")
        IdentityKeyPair(bytes)
    }

    override fun getLocalRegistrationId(): Int = runBlocking {
        identityStore.getLocalRegistrationId()
    }

    override fun saveIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey
    ): Boolean = runBlocking {
        identityStore.storeIdentity(address.name, identityKey.serialize())
    }

    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction
    ): Boolean = runBlocking {
        val existingKey = identityStore.loadIdentity(address.name)
        if (existingKey == null) return@runBlocking true
        // Constant-time comparison icin IdentityKey.equals kullanilir
        val existing = IdentityKey(existingKey, 0)
        existing == identityKey
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? = runBlocking {
        identityStore.loadIdentity(address.name)?.let { IdentityKey(it, 0) }
    }

    // --- PreKeyStore ---

    override fun loadPreKey(preKeyId: Int): PreKeyRecord = runBlocking {
        val bytes = preKeyStore.loadPreKey(preKeyId)
            ?: throw InvalidKeyIdException("PreKey not found: $preKeyId")
        PreKeyRecord(bytes)
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord): Unit = runBlocking {
        preKeyStore.storePreKey(preKeyId, record.serialize())
    }

    override fun containsPreKey(preKeyId: Int): Boolean = runBlocking {
        preKeyStore.containsPreKey(preKeyId)
    }

    override fun removePreKey(preKeyId: Int): Unit = runBlocking {
        preKeyStore.removePreKey(preKeyId)
    }

    // --- SignedPreKeyStore ---

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord = runBlocking {
        val bytes = signedPreKeyStore.loadSignedPreKey(signedPreKeyId)
            ?: throw InvalidKeyIdException("SignedPreKey not found: $signedPreKeyId")
        SignedPreKeyRecord(bytes)
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> = runBlocking {
        signedPreKeyStore.loadAllSignedPreKeys().map { SignedPreKeyRecord(it) }
    }

    override fun storeSignedPreKey(
        signedPreKeyId: Int,
        record: SignedPreKeyRecord
    ): Unit = runBlocking {
        signedPreKeyStore.storeSignedPreKey(signedPreKeyId, record.serialize())
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean = runBlocking {
        signedPreKeyStore.containsSignedPreKey(signedPreKeyId)
    }

    override fun removeSignedPreKey(signedPreKeyId: Int): Unit = runBlocking {
        signedPreKeyStore.removeSignedPreKey(signedPreKeyId)
    }

    // --- SessionStore ---

    override fun loadSession(address: SignalProtocolAddress): SessionRecord = runBlocking {
        val bytes = sessionStore.loadSession(address.name, address.deviceId)
        if (bytes != null) SessionRecord(bytes) else SessionRecord()
    }

    override fun getSubDeviceSessions(name: String): List<Int> = runBlocking {
        sessionStore.getSubDeviceSessions(name)
    }

    override fun storeSession(
        address: SignalProtocolAddress,
        record: SessionRecord
    ): Unit = runBlocking {
        sessionStore.storeSession(address.name, address.deviceId, record.serialize())
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean = runBlocking {
        sessionStore.containsSession(address.name, address.deviceId)
    }

    override fun deleteSession(address: SignalProtocolAddress): Unit = runBlocking {
        sessionStore.deleteSession(address.name, address.deviceId)
    }

    override fun deleteAllSessions(name: String): Unit = runBlocking {
        sessionStore.deleteAllSessions(name)
    }

    // --- Ek yardimci metodlar ---

    /**
     * Mevcut kullanilabilir PreKey sayisini dondurur.
     * PreKey yenileme karari icin kullanilir.
     */
    suspend fun getAvailablePreKeyCount(): Int = preKeyStore.getAvailablePreKeyCount()

    /**
     * Siradaki PreKey ID'sini dondurur.
     * Yeni PreKey batch uretiminde baslangic ID olarak kullanilir.
     */
    suspend fun getNextPreKeyId(): Int = preKeyStore.getNextPreKeyId()
}
