package com.securechat.storage.repository

import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.domain.Conversation
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageContentType
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

        // Sohbet listesinde ozel mesaj tipleri icin okunabilir onizleme — JSON/pipe-string sizmasin
        val lastMessagePreview = message.previewText
        // SYSTEM mesajlari unread count artirmaz (arama kayitlari bildirim gostermemeli)
        val shouldIncrementUnread = !message.isOutgoing && message.contentType != MessageContentType.SYSTEM

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
                    lastMessage = lastMessagePreview,
                    lastMessageTimestamp = message.timestamp,
                    unreadCount = if (shouldIncrementUnread) 1 else 0,
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
                    lastMessage = lastMessagePreview,
                    lastMessageTimestamp = message.timestamp,
                    unreadCount = if (shouldIncrementUnread) conv.unreadCount + 1 else conv.unreadCount
                )
            )
        }
    }

    override fun getMessages(conversationId: String): Flow<List<LocalMessage>> {
        return messageDao.getMessages(conversationId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getRecentMessages(conversationId: String, limit: Int): Flow<List<LocalMessage>> {
        return messageDao.getRecentMessages(conversationId, limit).map { entities ->
            // getRecentMessages DESC siralama doner, kronolojik sira icin ters cevir
            entities.reversed().map { it.toDomain() }
        }
    }

    override suspend fun getOlderMessages(conversationId: String, beforeTimestamp: Long, limit: Int): List<LocalMessage> {
        return messageDao.getOlderMessages(conversationId, beforeTimestamp, limit)
            .reversed()
            .map { it.toDomain() }
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

    override suspend fun deleteMessage(messageId: String, conversationId: String) {
        messageDao.delete(messageId)
        // Silinen mesaj en son mesaj olabilir — konusma onizlemesini yeniden hesapla
        recalculateLastMessage(conversationId)
    }

    override suspend fun recalculateLastMessage(conversationId: String) {
        val info = conversationDao.getLastMessageInfo(conversationId)
        // info'dan minimal LocalMessage stub olusturup previewText'i al — okunabilir onizleme
        val preview = info?.let {
            val ct = try {
                MessageContentType.valueOf(it.contentType ?: "TEXT")
            } catch (_: Exception) { MessageContentType.TEXT }
            LocalMessage(
                id = "", conversationId = conversationId, senderId = "", peerId = "",
                content = it.content, contentType = ct,
                timestamp = it.timestamp, status = MessageStatus.SENT,
                isOutgoing = true,
                caption = it.caption,
                isViewOnce = it.isViewOnce
            ).previewText
        } ?: ""
        conversationDao.updateLastMessageById(
            conversationId,
            preview,
            info?.timestamp ?: 0L
        )
    }

    override suspend fun getStuckSendingMessages(olderThanMs: Long): List<LocalMessage> {
        val cutoff = System.currentTimeMillis() - olderThanMs
        return messageDao.getStuckSendingMessages(cutoff).map { it.toDomain() }
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
        val messageEntity = messageDao.getById(messageId)
        messageDao.updateContent(messageId, content, contentType)

        // "Herkesten silme" sonrasi konusma onizlemesini guncelle
        if (messageEntity != null) {
            val info = conversationDao.getLastMessageInfo(messageEntity.conversationId)
            if (info != null && info.timestamp == messageEntity.timestamp) {
                val preview = if (contentType == MessageContentType.POLL.name) "📊 Anket" else content
                conversationDao.updateLastMessageById(messageEntity.conversationId, preview, info.timestamp)
            }
        }
    }

    override suspend fun editMessage(messageId: String, newContent: String, editedAt: Long) {
        // Duzenleme oncesi mesajin mevcut icerigini ve gecmisini al
        val messageEntity = messageDao.getById(messageId)

        // Onceki icerigi edit_history JSON dizisine ekle
        var updatedHistory: String? = null
        if (messageEntity != null) {
            val previousContent = messageEntity.content
            val historyEntry = org.json.JSONObject().apply {
                put("content", previousContent)
                put("editedAt", editedAt)
            }
            val historyArray = if (!messageEntity.editHistory.isNullOrBlank()) {
                try {
                    org.json.JSONArray(messageEntity.editHistory)
                } catch (_: Exception) {
                    org.json.JSONArray()
                }
            } else {
                org.json.JSONArray()
            }
            historyArray.put(historyEntry)
            updatedHistory = historyArray.toString()
        }

        messageDao.updateContentEdited(messageId, newContent, editedAt, updatedHistory)

        // Duzenlenen mesaj konusmanin en son mesaji ise, konusma onizlemesini guncelle
        if (messageEntity != null) {
            val info = conversationDao.getLastMessageInfo(messageEntity.conversationId)
            if (info != null && info.timestamp == messageEntity.timestamp) {
                conversationDao.updateLastMessageById(messageEntity.conversationId, newContent, info.timestamp)
            }
        }
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

    override suspend fun applyRetroactiveExpiry(
        conversationId: String,
        duration: Long,
        windowStart: Long,
        now: Long
    ): Int = messageDao.applyRetroactiveExpiry(conversationId, duration, windowStart, now)

    override suspend fun deleteExpiredMessages(): Int {
        val now = System.currentTimeMillis()
        // Etkilenecek konusma id'lerini SILMEDEN once topla — sonra her birinin lastMessage'ini
        // tazeleyebilelim (konusma listesinde bayat preview kalmasin).
        val affectedConvIds = messageDao.getExpiredConversationIds(now)
        // Faz 12: Medya mesajlarinin fiziksel dosyalarini DB'den onceki toplada al,
        // DB silmeden once kayit et — sonra ana silme + filesystem cleanup.
        val expiredMediaContents = runCatching {
            messageDao.getExpiredMediaContents(now)
        }.getOrDefault(emptyList())

        val deleted = messageDao.deleteExpiredMessages(now)

        // DB silindi → simdi fiziksel dosyalari sil. Hata olursa sessizce devam et;
        // disappearing icin kullanici beklemiyor. content = "name|mime|size|path"
        for (content in expiredMediaContents) {
            val parts = content.split("|")
            val filePath = parts.getOrNull(3)?.takeIf { it.isNotBlank() } ?: continue
            runCatching {
                val file = java.io.File(filePath)
                if (file.exists() && file.isFile) file.delete()
            }.onFailure { e ->
                android.util.Log.w("MsgRepo", "Expired media dosya silinemedi: $filePath (${e.javaClass.simpleName})")
            }
        }

        for (convId in affectedConvIds) {
            val latest = messageDao.getLatestMessage(convId)
            if (latest == null) {
                conversationDao.clearLastMessage(convId)
            } else {
                conversationDao.updateLastMessageById(
                    conversationId = convId,
                    message = latest.toDomain().previewText,
                    timestamp = latest.timestamp
                )
            }
        }
        return deleted
    }

    override suspend fun updateConversationFavorite(conversationId: String, isFavorite: Boolean) {
        conversationDao.updateFavorite(conversationId, isFavorite)
    }

    override suspend fun updateConversationMuted(conversationId: String, isMuted: Boolean) {
        conversationDao.updateMuted(conversationId, isMuted)
    }

    override suspend fun updateMessageReactions(messageId: String, reactions: String?) {
        messageDao.updateReactions(messageId, reactions)
    }

    override suspend fun markViewOnceAsViewed(messageId: String) {
        // TEXT mesajlarda is_viewed=1 ile birlikte content'i de sil — bu sayede
        // "Acildi" placeholder kalir ama icerik DB'den geri donulemez bicimde gider.
        // Foto/dosyada mevcut davranis korunur (dosya silme akisi disarida yapilir).
        val existing = messageDao.getById(messageId)
        if (existing?.contentType == com.securechat.storage.model.MessageContentType.TEXT) {
            messageDao.consumeViewOnceText(messageId)
        } else {
            messageDao.markViewOnceAsViewed(messageId)
        }
    }

    override suspend fun updateConversationLocked(conversationId: String, isLocked: Boolean) {
        conversationDao.updateLocked(conversationId, isLocked)
    }

    override suspend fun markStuckMessagesAsFailed(cutoff: Long): Int {
        return messageDao.markStuckMessagesAsFailed(cutoff)
    }

    override suspend fun searchAllMessages(query: String): List<LocalMessage> {
        return messageDao.searchAllMessages("%$query%").map { it.toDomain() }
    }

    override suspend fun getAllMessagesForConversation(conversationId: String): List<LocalMessage> {
        return messageDao.getMessagesPaginated(conversationId, limit = 100_000, offset = 0)
            .sortedBy { it.timestamp }
            .map { it.toDomain() }
    }

    override suspend fun updateMessagePinned(messageId: String, isPinned: Boolean, pinnedAt: Long?) {
        messageDao.updatePinned(messageId, isPinned, pinnedAt)
    }

    override fun observeLatestPinnedMessage(conversationId: String): Flow<LocalMessage?> {
        return messageDao.observeLatestPinned(conversationId).map { entity ->
            entity?.toDomain()
        }
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
    expiresAt = expiresAt,
    editedAt = editedAt,
    editHistory = editHistory,
    reactions = reactions,
    caption = caption,
    isViewOnce = isViewOnce,
    isViewed = isViewed,
    isPinned = isPinned,
    pinnedAt = pinnedAt
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
    expiresAt = expiresAt,
    editedAt = editedAt,
    editHistory = editHistory,
    reactions = reactions,
    caption = caption,
    isViewOnce = isViewOnce,
    isViewed = isViewed,
    isPinned = isPinned,
    pinnedAt = pinnedAt
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
    isFavorite = isFavorite,
    isLocked = isLocked,
    manuallyUnread = manuallyUnread
)
