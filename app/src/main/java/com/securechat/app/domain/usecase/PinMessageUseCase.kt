package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject

/**
 * Mesaj sabitleme/cikarma use case'i (chat-icinde pin).
 *
 * Yetki:
 *   - 1:1 sohbette her iki taraf da pin/unpin yapabilir.
 *   - Grup sohbette yalniz admin (groupAdmins listesinde yer alanlar) yapabilir.
 *     Defansif kontrol — server zero-knowledge oldugu icin kotu niyetli client
 *     yine de signal gonderebilir; alici tarafta yine ayni admin kontrolu uygulanir
 *     (IncomingMessageHandler.handleMessagePin).
 *
 * Propagation: 1:1'de tek MessagePin gonderilir; grupta admin diger uyelere fanout eder.
 */
class PinMessageUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val messageRepository: MessageRepository,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * @param conversationId Sohbet/grup kimligi
     * @param messageId Pin edilecek mesaj kimligi
     * @param isPinned true = sabitle, false = pin'i kaldir
     */
    suspend operator fun invoke(
        conversationId: String,
        messageId: String,
        isPinned: Boolean
    ): Boolean {
        val currentUserId = userSession.userId
            ?: throw IllegalStateException("Kullanici giris yapmamis")
        val conversation = conversationDao.getById(conversationId)
            ?: throw IllegalArgumentException("Sohbet bulunamadi")
        messageRepository.getMessageById(messageId)
            ?: throw IllegalArgumentException("Mesaj bulunamadi")

        if (conversation.isGroup) {
            val admins = conversation.groupAdmins
                ?.split(",")?.filter { it.isNotBlank() }
                ?: emptyList()
            if (currentUserId !in admins) {
                throw IllegalAccessException("Sadece grup admin'i mesaj sabitleyebilir")
            }
        }

        val now = System.currentTimeMillis()
        val pinnedAt = if (isPinned) now else null
        messageRepository.updateMessagePinned(messageId, isPinned, pinnedAt)

        // Wire format
        if (conversation.isGroup) {
            val members = conversation.groupMembers
                ?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            for (member in members) {
                if (member != currentUserId) {
                    signalingClient.sendSignal(
                        SignalMessage.MessagePin(
                            senderId = currentUserId,
                            recipientId = member,
                            timestamp = now,
                            messageId = messageId,
                            isPinned = isPinned,
                            pinnedAt = pinnedAt,
                            groupId = conversationId
                        )
                    )
                }
            }
        } else {
            // 1:1 — karsi tarafa tek MessagePin
            signalingClient.sendSignal(
                SignalMessage.MessagePin(
                    senderId = currentUserId,
                    recipientId = conversationId,
                    timestamp = now,
                    messageId = messageId,
                    isPinned = isPinned,
                    pinnedAt = pinnedAt,
                    groupId = null
                )
            )
        }

        android.util.Log.d(
            "PinMessageUseCase",
            "Mesaj ${if (isPinned) "sabitlendi" else "pin kaldirildi"}: $messageId"
        )
        return true
    }
}
