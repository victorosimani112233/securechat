package com.securechat.crypto

import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import kotlinx.coroutines.Dispatchers
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

    // Signal Protocol senkron interface'leri — IO dispatcher'da calistir
    // main thread'i bloklamaktan kacinilir, ozellikle eski cihazlarda DB erisimi yavasken
    private fun <T> ioBlocking(block: suspend () -> T): T = runBlocking(Dispatchers.IO) { block() }

    // --- IdentityKeyStore ---

    override fun getIdentityKeyPair(): IdentityKeyPair = ioBlocking {
        val bytes = identityStore.getIdentityKeyPair()
            ?: throw IllegalStateException("Identity key pair not found")
        IdentityKeyPair(bytes)
    }

    override fun getLocalRegistrationId(): Int = ioBlocking {
        identityStore.getLocalRegistrationId()
    }

    override fun saveIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey
    ): Boolean = ioBlocking {
        identityStore.storeIdentity(address.name, identityKey.serialize())
    }

    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction
    ): Boolean = ioBlocking {
        val existingKey = identityStore.loadIdentity(address.name)
        if (existingKey == null) return@ioBlocking true
        // GUVENLIK (M1 fix): Timing attack korumasi icin constant-time karsilastirma.
        // Daha onceki '==' (Kotlin equals) timing-leak yapabiliyordu — first-mismatch'te erken cikis.
        // MessageDigest.isEqual garanti edilen sabit zamanli byte-wise karsilastirma yapar.
        java.security.MessageDigest.isEqual(existingKey, identityKey.serialize())
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? = ioBlocking {
        identityStore.loadIdentity(address.name)?.let { IdentityKey(it, 0) }
    }

    // --- PreKeyStore ---

    override fun loadPreKey(preKeyId: Int): PreKeyRecord = ioBlocking {
        val bytes = preKeyStore.loadPreKey(preKeyId)
            ?: throw InvalidKeyIdException("PreKey not found: $preKeyId")
        PreKeyRecord(bytes)
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord): Unit = ioBlocking {
        preKeyStore.storePreKey(preKeyId, record.serialize())
    }

    override fun containsPreKey(preKeyId: Int): Boolean = ioBlocking {
        preKeyStore.containsPreKey(preKeyId)
    }

    override fun removePreKey(preKeyId: Int): Unit = ioBlocking {
        preKeyStore.removePreKey(preKeyId)
    }

    // --- SignedPreKeyStore ---

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord = ioBlocking {
        val bytes = signedPreKeyStore.loadSignedPreKey(signedPreKeyId)
            ?: throw InvalidKeyIdException("SignedPreKey not found: $signedPreKeyId")
        SignedPreKeyRecord(bytes)
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> = ioBlocking {
        signedPreKeyStore.loadAllSignedPreKeys().map { SignedPreKeyRecord(it) }
    }

    override fun storeSignedPreKey(
        signedPreKeyId: Int,
        record: SignedPreKeyRecord
    ): Unit = ioBlocking {
        signedPreKeyStore.storeSignedPreKey(signedPreKeyId, record.serialize())
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean = ioBlocking {
        signedPreKeyStore.containsSignedPreKey(signedPreKeyId)
    }

    override fun removeSignedPreKey(signedPreKeyId: Int): Unit = ioBlocking {
        signedPreKeyStore.removeSignedPreKey(signedPreKeyId)
    }

    // --- SessionStore ---

    override fun loadSession(address: SignalProtocolAddress): SessionRecord = ioBlocking {
        val bytes = sessionStore.loadSession(address.name, address.deviceId)
        if (bytes != null) SessionRecord(bytes) else SessionRecord()
    }

    override fun getSubDeviceSessions(name: String): List<Int> = ioBlocking {
        sessionStore.getSubDeviceSessions(name)
    }

    override fun storeSession(
        address: SignalProtocolAddress,
        record: SessionRecord
    ): Unit = ioBlocking {
        sessionStore.storeSession(address.name, address.deviceId, record.serialize())
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean = ioBlocking {
        sessionStore.containsSession(address.name, address.deviceId)
    }

    override fun deleteSession(address: SignalProtocolAddress): Unit = ioBlocking {
        sessionStore.deleteSession(address.name, address.deviceId)
    }

    override fun deleteAllSessions(name: String): Unit = ioBlocking {
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
