package com.securechat.crypto

import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.protocol.CiphertextMessage
import org.whispersystems.libsignal.protocol.PreKeySignalMessage
import org.whispersystems.libsignal.protocol.SignalMessage
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mesaj sifreleme ve cozme islemleri.
 * Signal Protocol'un Double Ratchet Algorithm'ini kullanarak
 * her mesaj icin benzersiz anahtar turetir (forward secrecy).
 *
 * GUVENLIK: Plaintext mesaj icerigi ASLA loga yazilmaz.
 * GUVENLIK: Cozulmus plaintext kullanim sonrasi bellekten sifirlanmalidir.
 */
@Singleton
class MessageEncryptor @Inject constructor(
    private val protocolStore: SecureChatProtocolStore
) {
    /**
     * Mesaji Signal Protocol ile sifreler.
     *
     * @param recipientId Alici kullanici ID'si
     * @param plaintext Sifrelenecek duz metin (byte array)
     * @return Sifrelenmis mesaj zarfi
     */
    fun encrypt(recipientId: String, plaintext: ByteArray): EncryptedEnvelope {
        val address = SignalProtocolAddress(recipientId, 1)
        val cipher = SessionCipher(protocolStore, address)
        val cipherMessage = cipher.encrypt(plaintext)

        return EncryptedEnvelope(
            type = if (cipherMessage.type == CiphertextMessage.PREKEY_TYPE)
                EnvelopeType.PREKEY else EnvelopeType.SIGNAL,
            content = cipherMessage.serialize(),
            timestamp = System.currentTimeMillis(),
            senderRegistrationId = protocolStore.localRegistrationId
        )
    }

    /**
     * Sifrelenmis mesaji cozer.
     *
     * @param senderId Gonderen kullanici ID'si
     * @param envelope Sifrelenmis mesaj zarfi
     * @return Cozulmus plaintext (byte array)
     */
    fun decrypt(senderId: String, envelope: EncryptedEnvelope): ByteArray {
        val address = SignalProtocolAddress(senderId, 1)
        val cipher = SessionCipher(protocolStore, address)

        return when (envelope.type) {
            EnvelopeType.PREKEY -> {
                val message = PreKeySignalMessage(envelope.content)
                cipher.decrypt(message)
            }
            EnvelopeType.SIGNAL -> {
                val message = SignalMessage(envelope.content)
                cipher.decrypt(message)
            }
        }
    }
}
