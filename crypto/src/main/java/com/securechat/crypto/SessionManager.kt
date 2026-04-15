package com.securechat.crypto

import org.whispersystems.libsignal.SessionBuilder
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.PreKeyBundle
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Signal Protocol session yonetimi.
 * X3DH key agreement ile yeni session olusturur ve mevcut session'lara erisim saglar.
 *
 * Session olusturma akisi:
 * 1. Alicinin PreKeyBundle'ini signaling sunucusundan al
 * 2. createSession() ile X3DH key agreement yap
 * 3. Donen SessionCipher ile mesaj sifrele/coz
 */
@Singleton
class SessionManager @Inject constructor(
    private val protocolStore: SecureChatProtocolStore
) {
    /**
     * Yeni bir session olusturur ve SessionCipher dondurur.
     * X3DH key agreement bu metod icerisinde gerceklesir.
     *
     * @param recipientAddress Alicinin Signal Protocol adresi
     * @param preKeyBundle Alicinin public key bundle'i
     * @return Mesaj sifreleme/cozme icin kullanilacak SessionCipher
     */
    fun createSession(
        recipientAddress: SignalProtocolAddress,
        preKeyBundle: PreKeyBundle
    ): SessionCipher {
        val sessionBuilder = SessionBuilder(protocolStore, recipientAddress)
        sessionBuilder.process(preKeyBundle)
        return SessionCipher(protocolStore, recipientAddress)
    }

    /**
     * Mevcut bir session icin SessionCipher dondurur.
     * Session yoksa, ilk mesajda PreKey mesaji gonderilir.
     *
     * @param recipientAddress Alicinin Signal Protocol adresi
     * @return SessionCipher instance'i
     */
    fun getSessionCipher(recipientAddress: SignalProtocolAddress): SessionCipher {
        return SessionCipher(protocolStore, recipientAddress)
    }

    /**
     * Belirtilen kullanici ile aktif bir session olup olmadigini kontrol eder.
     *
     * @param recipientId Alici kullanici ID'si
     * @param deviceId Cihaz ID'si (varsayilan 1)
     * @return Session mevcutsa true
     */
    fun hasSession(recipientId: String, deviceId: Int = 1): Boolean {
        val address = SignalProtocolAddress(recipientId, deviceId)
        return protocolStore.containsSession(address)
    }
}
