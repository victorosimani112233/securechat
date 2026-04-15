package com.securechat.crypto

import com.securechat.crypto.model.CallEncryptionKeys
import org.whispersystems.libsignal.kdf.HKDFv3
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

/**
 * WebRTC arama sifreleme anahtar yonetimi.
 * SRTP (Secure Real-time Transport Protocol) icin
 * HKDF tabanli anahtar turetimi yapar.
 *
 * GUVENLIK: Turetilen anahtarlar arama sona erdiginde
 * CallEncryptionKeys.clear() ile bellekten sifirlanmalidir.
 */
@Singleton
class CallCryptoManager @Inject constructor(
    private val protocolStore: SecureChatProtocolStore
) {
    companion object {
        private const val SRTP_INFO = "SecureChat-SRTP-Key"
        private const val DERIVED_KEY_LENGTH = 64
    }

    /**
     * Belirtilen peer ile arama icin SRTP master key ve salt turetir.
     * Rastgele nonce olusturur ve HKDF ile anahtar turetir.
     *
     * GUVENLIK: Donen CallEncryptionKeys nesnesi arama sonunda
     * clear() ile sifirlanmalidir.
     *
     * @param peerId Arama yapilacak kullanicinin ID'si
     * @return SRTP master key ve salt iceren anahtar cifti
     */
    fun deriveCallEncryptionKey(peerId: String): CallEncryptionKeys {
        // Rastgele nonce olustur
        val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }

        // HKDF v3 ile anahtar turet (32 byte key + 32 byte salt)
        // Info parametresine peerId eklenerek her peer icin farkli anahtar turetilir
        val hkdf = HKDFv3()
        val info = "$SRTP_INFO:$peerId".toByteArray()
        val derivedKey = hkdf.deriveSecrets(
            nonce,
            info,
            DERIVED_KEY_LENGTH
        )

        val keys = CallEncryptionKeys(
            masterKey = derivedKey.copyOfRange(0, 32),
            masterSalt = derivedKey.copyOfRange(32, 64)
        )

        // Ara key material'i sifirla
        nonce.fill(0)
        derivedKey.fill(0)

        return keys
    }
}
