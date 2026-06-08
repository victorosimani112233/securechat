package com.securechat.app.data.incoming.handlers

import com.securechat.network.SignalMessage
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Karsi taraftan gelen mesaj silme + duzenleme bildirimleri.
 *
 * Faz 10: handleMessageDelete + handleMessageEdit extract edildi.
 */
@Singleton
class MessageEditDeleteHandler @Inject constructor(
    private val messageRepository: MessageRepository,
    private val conversationDao: ConversationDao
) {

    suspend fun onDelete(signal: SignalMessage.MessageDelete) {
        android.util.Log.d("MessageEditDeleteHandler", "Delete: msgId=${signal.messageId} from=${signal.senderId}")
        try {
            messageRepository.updateMessageContent(
                messageId = signal.messageId,
                content = "Bu mesaj silindi",
                contentType = "DELETED"
            )
            // Konusma listesinde son mesaj bu ise guncelle
            val conv = conversationDao.getById(signal.senderId)
            if (conv != null) {
                conversationDao.updateLastMessage(
                    signal.senderId,
                    "Bu mesaj silindi",
                    conv.lastMessageTimestamp ?: System.currentTimeMillis()
                )
            }
        } catch (e: Exception) {
            android.util.Log.e("MessageEditDeleteHandler", "Mesaj silinirken hata: ${e.message}", e)
        }
    }

    suspend fun onEdit(signal: SignalMessage.MessageEdit) {
        android.util.Log.d("MessageEditDeleteHandler", "Edit: msgId=${signal.messageId} from=${signal.senderId}")
        try {
            messageRepository.editMessage(
                messageId = signal.messageId,
                newContent = signal.newContent,
                editedAt = signal.timestamp
            )
        } catch (e: Exception) {
            android.util.Log.e("MessageEditDeleteHandler", "Mesaj duzenlenirken hata: ${e.message}", e)
        }
    }
}
