package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.delay
import java.util.UUID
import javax.inject.Inject

/**
 * Mesaj gonderme use case'i.
 *
 * Yavas baglanti durumunda mesaji hemen FAILED olarak isaretlemek yerine,
 * maksimum MAX_RETRY_COUNT kez yeniden deneme yapar. Her denemede
 * RETRY_DELAY_MS kadar bekler. Tum denemeler basarisiz olursa mesaj
 * FAILED olarak isaretlenir; bu arada SENDING durumunda kalir.
 */
class SendMessageUseCase @Inject constructor(
    private val messageRepository: MessageRepository,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession,
    private val conversationDao: ConversationDao
) {
    companion object {
        /** Mesaj gonderim denemesi basarisiz oldugunda maksimum yeniden deneme sayisi. */
        const val MAX_RETRY_COUNT = 3
        /** Her yeniden deneme arasindaki bekleme suresi (milisaniye). */
        const val RETRY_DELAY_MS = 2000L
    }

    suspend operator fun invoke(
        conversationId: String,
        content: String,
        replyToId: String? = null,
        contentType: MessageContentType = MessageContentType.TEXT,
        isViewOnce: Boolean = false
    ) {
        val senderId = userSession.userId ?: "unknown"
        val timestamp = System.currentTimeMillis()

        // Grup mu birebir mi kontrol et
        val conversation = conversationDao.getById(conversationId)
        val isGroup = conversation?.isGroup == true

        // Sureli mesaj kontrolu — konusmada sureli mesaj aktifse expiresAt hesapla
        val disappearingDuration = conversation?.disappearingDuration ?: 0
        val expiresAt = if (disappearingDuration > 0) timestamp + disappearingDuration else null

        val message = LocalMessage(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId,
            senderId = senderId,
            peerId = conversationId,
            content = content,
            contentType = contentType,
            timestamp = timestamp,
            status = MessageStatus.SENDING,
            isOutgoing = true,
            replyToId = replyToId,
            expiresAt = expiresAt,
            isViewOnce = isViewOnce
        )
        messageRepository.saveMessage(message)

        // Mesaj icerigi MSGID prefix'i ile gonderilir — alici taraf delivery receipt gonderebilsin
        // REPLY prefix eklenir — alici taraf reply mesajini gorebilsin
        val replyPrefix = if (replyToId != null) "REPLY:$replyToId:" else ""
        // POLL mesajlari POLL: prefix'i ile isaretlenir — alici taraf POLL olarak ayirt edebilsin
        val typePrefix = if (contentType == MessageContentType.POLL) "POLL:" else ""
        // EXP prefix: sureli mesaj icin mutlak expiresAt'i gomeriz — alici da ayni anda gormez
        // olur. Alici lokal duration'i bilmiyorsa veya transit gecikmesi varsa bile dogru calisir.
        val expPrefix = if (expiresAt != null) "EXP:$expiresAt:" else ""
        // VIEWONCE prefix: tek gosterimlik metin mesaji bayragi — POLL/icerikten ONCE.
        // Parser POLL gorunce geri kalanini content sayar; bu yuzden VIEWONCE'u POLL'den
        // once yerlestiriyoruz. Foto/dosya icin FileTransfer.isViewOnce kullanilir.
        val viewOncePrefix = if (isViewOnce) "VIEWONCE:" else ""
        // Sira onemli: EXP, POLL/POLLVOTE'tan ONCE — parser POLL gorunce geri kalanini content
        // sayar. Boylece "MSGID:id:[REPLY:rid:][EXP:abs:][VIEWONCE:][POLL:]content" formati olusur.
        val envelopeContent = "MSGID:${message.id}:${replyPrefix}${expPrefix}${viewOncePrefix}${typePrefix}$content"

        // Ilk deneme
        val sent = attemptSend(senderId, conversationId, timestamp, envelopeContent, isGroup, conversation)

        if (sent) {
            messageRepository.updateMessageStatus(message.id, MessageStatus.SENT)
            return
        }

        // Ilk deneme basarisiz — yeniden deneme dongusu (mesaj SENDING olarak kalir)
        android.util.Log.d("SendMessage", "Ilk gonderim basarisiz, yeniden deneme basliyor: ${message.id}")
        for (attempt in 1..MAX_RETRY_COUNT) {
            delay(RETRY_DELAY_MS)
            val retryResult = attemptSend(senderId, conversationId, timestamp, envelopeContent, isGroup, conversation)
            if (retryResult) {
                messageRepository.updateMessageStatus(message.id, MessageStatus.SENT)
                android.util.Log.d("SendMessage", "Yeniden deneme basarili (deneme #$attempt): ${message.id}")
                return
            }
            android.util.Log.d("SendMessage", "Yeniden deneme basarisiz (deneme #$attempt/$MAX_RETRY_COUNT): ${message.id}")
        }

        // Tum denemeler basarisiz — FAILED olarak isaretle
        android.util.Log.d("SendMessage", "Tum denemeler basarisiz, FAILED: ${message.id}")
        messageRepository.updateMessageStatus(message.id, MessageStatus.FAILED)
    }

    /**
     * Mesaji signaling sunucusu uzerinden gondermeye calisir.
     *
     * @return Mesaj basariyla gonderildiyse true
     */
    private fun attemptSend(
        senderId: String,
        conversationId: String,
        timestamp: Long,
        envelopeContent: String,
        isGroup: Boolean,
        conversation: com.securechat.storage.entity.ConversationEntity?
    ): Boolean {
        return if (isGroup) {
            val groupName = conversation?.peerName ?: ""
            val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            // Server-side fanout: tek mesajda tum uyelerin payloadini gonder
            val payloads = members.associateWith { "GROUP:$conversationId:$groupName:$envelopeContent" }
            signalingClient.sendSignal(
                SignalMessage.GroupMessageFanout(
                    senderId = senderId,
                    timestamp = timestamp,
                    groupId = conversationId,
                    recipientPayloads = payloads
                )
            )
        } else {
            signalingClient.sendSignal(
                SignalMessage.EncryptedMessage(
                    senderId = senderId,
                    recipientId = conversationId,
                    timestamp = timestamp,
                    envelope = envelopeContent
                )
            )
        }
    }
}
