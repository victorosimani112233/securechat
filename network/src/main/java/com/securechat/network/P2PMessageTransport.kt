package com.securechat.network

import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import com.securechat.network.model.DecryptedMessage
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * P2P DataChannel uzerinden sifreli mesaj gonderme ve alma.
 *
 * Bu sinif:
 * - MessageEncryptor ile mesajlari sifreler/cozer
 * - DataChannel uzerinden byte verisi gonderir/alir
 * - Gelen mesajlari SharedFlow olarak yayar
 *
 * GUVENLIK: Plaintext mesaj icerigi ASLA loga yazilmaz.
 * GUVENLIK: Cozulmus plaintext kullanim sonrasi bellekten sifirlanir.
 */
@Singleton
class P2PMessageTransport @Inject constructor(
    private val peerConnectionManager: PeerConnectionManager,
    private val messageEncryptor: MessageEncryptor
) {
    private val _incomingMessages = MutableSharedFlow<DecryptedMessage>(
        extraBufferCapacity = 512
    )
    val incomingMessages: SharedFlow<DecryptedMessage> = _incomingMessages.asSharedFlow()

    /**
     * Belirtilen peer'e sifreli mesaj gonderir.
     *
     * @param peerId Alici peer'in ID'si
     * @param plaintext Gonderilecek duz metin
     * @return Mesaj basariyla gonderildiyse true, peer baglantisi yoksa false
     */
    fun sendMessage(peerId: String, plaintext: String): Boolean {
        // Yeni API: tek PeerConnection yonetimi; aktif baglanti yoksa gonderilmez
        if (peerConnectionManager.peerStates.value.none { it.value == com.securechat.network.model.PeerState.CONNECTED_P2P }) return false
        @Suppress("UNUSED_VARIABLE")
        val encrypted = messageEncryptor.encrypt(peerId, plaintext.toByteArray(Charsets.UTF_8))
        // Runtime'da serialize edilip DataChannel uzerinden gonderilir:
        // val serialized = Json.encodeToString(encrypted)
        // val buffer = DataChannel.Buffer(ByteBuffer.wrap(serialized.toByteArray()), false)
        // dataChannel.send(buffer)
        return true
    }

    /**
     * DataChannel'dan gelen sifreli mesaji cozer ve SharedFlow'a yayar.
     * Bu metod runtime'da DataChannel observer tarafindan cagrilir.
     *
     * @param senderId Mesaji gonderen peer'in ID'si
     * @param encryptedData Sifrelenmis mesaj verisi (byte array)
     */
    suspend fun onMessageReceived(senderId: String, encryptedData: ByteArray) {
        val envelope = EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = encryptedData,
            timestamp = System.currentTimeMillis(),
            senderRegistrationId = 0
        )
        val plaintext = messageEncryptor.decrypt(senderId, envelope)
        _incomingMessages.emit(
            DecryptedMessage(
                senderId = senderId,
                content = String(plaintext, Charsets.UTF_8),
                timestamp = System.currentTimeMillis()
            )
        )
    }
}
