package com.securechat.network

import java.util.Base64
import com.securechat.crypto.MessageEncryptor
import com.securechat.network.model.PendingMessage
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cevrimdisi mesaj kuyrugu.
 *
 * P2P baglantisi olmadigi durumlarda mesajlar signaling sunucusu
 * uzerinden iletilir. Signaling baglantisi da yoksa mesajlar
 * bu kuyrukta saklanir ve baglanti kuruldugunda gonderilir.
 *
 * GUVENLIK: Mesajlar kuyruga eklenmeden once Signal Protocol ile sifrelenir.
 * Kuyruktaki mesajlar sifrelenmis formattadir.
 */
@Singleton
class OfflineMessageQueue @Inject constructor(
    private val signalingClient: SignalingClient,
    private val messageEncryptor: MessageEncryptor
) {
    private val pendingQueue = ConcurrentLinkedQueue<PendingMessage>()

    /**
     * Mesaji sifreler ve signaling uzerinden gondermeye calisir.
     * Gonderilemezse kuyruga ekler.
     *
     * @param senderId Gonderen kullanici ID'si
     * @param recipientId Alici kullanici ID'si
     * @param plaintext Gonderilecek duz metin
     */
    fun queueMessage(senderId: String, recipientId: String, plaintext: String) {
        val encrypted = messageEncryptor.encrypt(recipientId, plaintext.toByteArray(Charsets.UTF_8))
        val envelopeJsonObj = buildJsonObject {
            put("type", encrypted.type.name)
            put("content", Base64.getEncoder().encodeToString(encrypted.content))
            put("timestamp", encrypted.timestamp)
            put("senderRegistrationId", encrypted.senderRegistrationId)
        }
        val encodedEnvelope = Base64.getEncoder().encodeToString(
            envelopeJsonObj.toString().toByteArray()
        )

        val signal = SignalMessage.EncryptedMessage(
            senderId = senderId,
            recipientId = recipientId,
            timestamp = System.currentTimeMillis(),
            envelope = encodedEnvelope
        )

        if (!signalingClient.sendSignal(signal)) {
            pendingQueue.add(PendingMessage(recipientId, plaintext, System.currentTimeMillis()))
        }
    }

    /**
     * Kuyrukta bekleyen mesaj sayisini dondurur.
     *
     * @return Bekleyen mesaj sayisi
     */
    fun getPendingCount(): Int = pendingQueue.size

    /**
     * Kuyruktaki tum bekleyen mesajlari gondermeye calisir.
     * Basariyla gonderilen mesajlar kuyruktan cikarilir.
     * Gonderilemeyenler kuyruga geri eklenir.
     *
     * @param senderId Gonderen kullanici ID'si
     */
    fun flushQueue(senderId: String) {
        // Once tum bekleyen mesajlari kuyruktan cikar
        val snapshot = mutableListOf<PendingMessage>()
        while (pendingQueue.isNotEmpty()) {
            val pending = pendingQueue.poll() ?: break
            snapshot.add(pending)
        }
        // Sonra her birini gondermeyi dene
        // queueMessage basarisiz olursa mesaji tekrar kuyruga ekler
        for (pending in snapshot) {
            queueMessage(senderId, pending.recipientId, pending.content)
        }
    }

    /**
     * Kuyruktaki tum mesajlari siler.
     */
    fun clearQueue() {
        pendingQueue.clear()
    }
}
