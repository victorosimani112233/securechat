package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import java.util.UUID
import javax.inject.Inject

class SendMessageUseCase @Inject constructor(
    private val messageRepository: MessageRepository,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession,
    private val conversationDao: ConversationDao
) {
    suspend operator fun invoke(conversationId: String, content: String) {
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
            contentType = MessageContentType.TEXT,
            timestamp = timestamp,
            status = MessageStatus.SENDING,
            isOutgoing = true,
            expiresAt = expiresAt
        )
        messageRepository.saveMessage(message)

        // Mesaj icerigi MSGID prefix'i ile gonderilir — alici taraf delivery receipt gonderebilsin
        val envelopeContent = "MSGID:${message.id}:$content"

        val sent = if (isGroup) {
            // Grup mesaji: tum uyelere gonder, GROUP:groupId:groupName:content formatinda
            val groupName = conversation?.peerName ?: ""
            val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            var allSent = true
            for (memberId in members) {
                // CRITICAL FIX: Gönderici de mesajı almalı (grup senkronizasyonu için)
                val memberSent = signalingClient.sendSignal(
                    SignalMessage.EncryptedMessage(
                        senderId = senderId,
                        recipientId = memberId,
                        timestamp = timestamp,
                        envelope = "GROUP:$conversationId:$groupName:$envelopeContent"
                    )
                )
                if (!memberSent) allSent = false
            }
            allSent
        } else {
            // Birebir mesaj: dogrudan aliciya gonder
            signalingClient.sendSignal(
                SignalMessage.EncryptedMessage(
                    senderId = senderId,
                    recipientId = conversationId,
                    timestamp = timestamp,
                    envelope = envelopeContent
                )
            )
        }

        val newStatus = if (sent) MessageStatus.SENT else MessageStatus.FAILED
        messageRepository.updateMessageStatus(message.id, newStatus)
    }
}
