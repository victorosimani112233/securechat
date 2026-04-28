package com.securechat.storage.repository

import com.securechat.storage.domain.Conversation
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageStatus
import kotlinx.coroutines.flow.Flow

/**
 * Mesaj repository interface'i. Use case katmani bu interface'i kullanir.
 */
interface MessageRepository {

    /** Mesaj kaydet ve ilgili konuşmanin son mesajini guncelle. */
    suspend fun saveMessage(message: LocalMessage)

    /** Belirli bir konuşmadaki tum mesajlari reaktif olarak getir. */
    fun getMessages(conversationId: String): Flow<List<LocalMessage>>

    /** Tum konuşmalari reaktif olarak getir. */
    fun getConversations(): Flow<List<Conversation>>

    /** Mesaj durumunu guncelle. */
    suspend fun updateMessageStatus(messageId: String, status: MessageStatus)

    /** Belirli bir mesaji ID'sine gore getir. */
    suspend fun getMessageById(messageId: String): LocalMessage?

    /** Konuşmayi okundu olarak isaretle. */
    suspend fun markConversationAsRead(conversationId: String)

    /** Tek bir mesaji sil. */
    suspend fun deleteMessage(messageId: String)

    /** Konuşmayi ve tum mesajlarini sil. */
    suspend fun deleteConversation(conversationId: String)

    /** Tüm konuşmaların peer isimlerini ContactNameResolver ile güncelle. */
    suspend fun updateConversationNames()

    /** Mesajın yıldızlı durumunu güncelle. */
    suspend fun updateMessageStarred(messageId: String, isStarred: Boolean)

    /** Mesaj icerigini guncelle (herkesten silme icin). */
    suspend fun updateMessageContent(messageId: String, content: String, contentType: String)

    /** Mesaj icerigini duzenle ve editedAt zamanini kaydet. */
    suspend fun editMessage(messageId: String, newContent: String, editedAt: Long)

    /** Konuşmayı arşivle veya arşivden çıkar. */
    suspend fun updateConversationArchived(conversationId: String, isArchived: Boolean)

    /** Arşivlenmiş konuşmaları reaktif olarak getir. */
    fun getArchivedConversations(): Flow<List<Conversation>>

    /** Konuşmanın süreli mesaj süresini güncelle. */
    suspend fun updateDisappearingDuration(conversationId: String, duration: Long)

    /** Süresi dolmuş mesajları sil. Silinen mesaj sayısını döner. */
    suspend fun deleteExpiredMessages(): Int

    /** Konuşmanın favori durumunu güncelle. */
    suspend fun updateConversationFavorite(conversationId: String, isFavorite: Boolean)

    /** Konuşmanın sessiz modunu güncelle. */
    suspend fun updateConversationMuted(conversationId: String, isMuted: Boolean)
}
