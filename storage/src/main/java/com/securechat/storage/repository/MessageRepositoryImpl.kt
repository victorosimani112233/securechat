package com.securechat.storage.repository

import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.domain.Conversation
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.resolver.ContactNameResolver
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mesaj repository implementasyonu. Entity <-> Domain donusumleri burada yapilir.
 * Mesaj kaydederken ilgili konuşmanin son mesajini da gunceller.
 */
@Singleton
class MessageRepositoryImpl @Inject constructor(
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao,
    private val contactNameResolver: ContactNameResolver
) : MessageRepository {

    override suspend fun saveMessage(message: LocalMessage) {
        // Grup konusmasi icin once ID ile, birebir icin peerId ile bak
        val conv = conversationDao.getById(message.conversationId)
            ?: conversationDao.getByPeerId(message.peerId)

        // Konusma yoksa once olustur (FK kisitlamasi icin mesajdan once olmali)
        if (conv == null) {
            // Kisi adini ve telefon numarasini resolve et
            val displayName = contactNameResolver.resolveDisplayName(message.peerId)
            val phoneNumber = contactNameResolver.resolvePhoneNumber(message.peerId)

            conversationDao.insert(
                ConversationEntity(
                    id = message.conversationId.ifBlank { message.peerId },
                    peerId = message.peerId,
                    peerName = displayName,
                    peerPhone = phoneNumber,
                    lastMessage = message.content,
                    lastMessageTimestamp = message.timestamp,
                    unreadCount = if (!message.isOutgoing) 1 else 0,
                    isMuted = false,
                    isPinned = false
                )
            )
        }

        // Mesaji kaydet
        val entity = message.toEntity()
        messageDao.insert(entity)

        // Varolan konusmanin son mesaj bilgisini guncelle (REPLACE degil UPDATE!)
        if (conv != null) {
            conversationDao.update(
                conv.copy(
                    lastMessage = message.content,
                    lastMessageTimestamp = message.timestamp,
                    unreadCount = if (!message.isOutgoing) conv.unreadCount + 1 else conv.unreadCount
                )
            )
        }
    }

    override fun getMessages(conversationId: String): Flow<List<LocalMessage>> {
        return messageDao.getMessages(conversationId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getConversations(): Flow<List<Conversation>> {
        return conversationDao.getAll().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun updateMessageStatus(messageId: String, status: MessageStatus) {
        messageDao.updateStatus(messageId, status)
    }

    override suspend fun getMessageById(messageId: String): LocalMessage? {
        return messageDao.getById(messageId)?.toDomain()
    }

    override suspend fun markConversationAsRead(conversationId: String) {
        conversationDao.markAsRead(conversationId)
    }

    override suspend fun deleteMessage(messageId: String) {
        messageDao.delete(messageId)
    }

    override suspend fun deleteConversation(conversationId: String) {
        messageDao.deleteByConversation(conversationId)
        conversationDao.delete(conversationId)
    }

    override suspend fun updateConversationNames() {
        // ConversationDao'ya suspend getAllNow fonksiyonu eklemek yerine
        // burada doğrudan entity'lerle çalışalım
        try {
            // Tüm konuşmaları tek seferde al
            conversationDao.getAllImmediate().forEach { conv ->
                // Eğer peerName peerId ile aynıysa (yani telefon numarasıysa), güncelle
                if (conv.peerName == conv.peerId || conv.peerName == conv.peerPhone || conv.peerName.startsWith("+")) {
                    val displayName = contactNameResolver.resolveDisplayName(conv.peerId)
                    if (displayName != conv.peerName) {
                        conversationDao.update(conv.copy(peerName = displayName))
                    }
                }
            }
        } catch (e: Exception) {
            // Hata durumunda log et ama çökmesin
            android.util.Log.w("MessageRepository", "updateConversationNames failed", e)
        }
    }

    override suspend fun updateMessageStarred(messageId: String, isStarred: Boolean) {
        messageDao.updateStarred(messageId, isStarred)
    }

    override suspend fun updateMessageContent(messageId: String, content: String, contentType: String) {
        messageDao.updateContent(messageId, content, contentType)
    }

    override suspend fun updateConversationArchived(conversationId: String, isArchived: Boolean) {
        conversationDao.updateArchived(conversationId, isArchived)
    }

    override fun getArchivedConversations(): Flow<List<Conversation>> {
        return conversationDao.getArchived().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun updateDisappearingDuration(conversationId: String, duration: Long) {
        conversationDao.updateDisappearingDuration(conversationId, duration)
    }

    override suspend fun deleteExpiredMessages(): Int {
        return messageDao.deleteExpiredMessages(System.currentTimeMillis())
    }

    override suspend fun updateConversationFavorite(conversationId: String, isFavorite: Boolean) {
        conversationDao.updateFavorite(conversationId, isFavorite)
    }

    override suspend fun updateConversationMuted(conversationId: String, isMuted: Boolean) {
        conversationDao.updateMuted(conversationId, isMuted)
    }
}

// --- Extension fonksiyonlari: Entity <-> Domain donusumleri ---

/** LocalMessage domain modelini MessageEntity'ye donusturur. */
internal fun LocalMessage.toEntity(): MessageEntity = MessageEntity(
    id = id,
    conversationId = conversationId,
    senderId = senderId,
    content = content,
    contentType = contentType,
    timestamp = timestamp,
    status = status,
    replyToId = replyToId,
    isOutgoing = isOutgoing,
    isStarred = isStarred,
    expiresAt = expiresAt
)

/**
 * MessageEntity'yi LocalMessage domain modeline donusturur.
 * Not: peerId bilgisi entity'de bulunmadigi icin bos string atanir;
 * gerektiginde conversation uzerinden doldurulmalidir.
 */
internal fun MessageEntity.toDomain(): LocalMessage = LocalMessage(
    id = id,
    conversationId = conversationId,
    senderId = senderId,
    peerId = "",
    content = content,
    contentType = contentType,
    timestamp = timestamp,
    status = status,
    replyToId = replyToId,
    isOutgoing = isOutgoing,
    isStarred = isStarred,
    expiresAt = expiresAt
)

/** ConversationEntity'yi Conversation domain modeline donusturur. */
internal fun ConversationEntity.toDomain(): Conversation = Conversation(
    id = id,
    peerId = peerId,
    peerName = peerName,
    peerPhone = peerPhone,
    lastMessage = lastMessage,
    lastMessageTimestamp = lastMessageTimestamp,
    unreadCount = unreadCount,
    isMuted = isMuted,
    isPinned = isPinned,
    isGroup = isGroup,
    groupMembers = groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
    groupAdmins = groupAdmins?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
    contactNote = contactNote,
    customNotificationUri = customNotificationUri,
    isArchived = isArchived,
    disappearingDuration = disappearingDuration,
    isFavorite = isFavorite
)
