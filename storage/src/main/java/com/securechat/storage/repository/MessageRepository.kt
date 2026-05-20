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

    /** Belirli bir konuşmadaki son N mesaji reaktif olarak getir (sayfalama icin). */
    fun getRecentMessages(conversationId: String, limit: Int): Flow<List<LocalMessage>>

    /** Cursor-based sayfalama: belirtilen zaman damgasindan onceki mesajlari getirir. */
    suspend fun getOlderMessages(conversationId: String, beforeTimestamp: Long, limit: Int): List<LocalMessage>

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

    /** Tek bir mesaji sil ve konusmanin son mesaj onizlemesini yeniden hesapla. */
    suspend fun deleteMessage(messageId: String, conversationId: String)

    /** Konusmanin lastMessage ve lastMessageTimestamp alanlarini yeniden hesaplar. */
    suspend fun recalculateLastMessage(conversationId: String)

    /** SENDING durumunda takili kalmis mesajlari getirir (belirtilen sureden eski). */
    suspend fun getStuckSendingMessages(olderThanMs: Long): List<LocalMessage>

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

    /**
     * Yeni gelen DisappearingTimer signal'i icin retroaktif expiresAt uygula.
     * Race penceresi (windowStart..now) icindeki, henuz expiresAt'i olmayan, gelen mesajlara
     * `arrivalTimestamp + duration` degerini atar. Boylece timer biraz gec geldi durumlarinda
     * onceki mesajlar da otomatik silinir.
     * @return Etkilenen mesaj sayisi
     */
    suspend fun applyRetroactiveExpiry(
        conversationId: String,
        duration: Long,
        windowStart: Long,
        now: Long
    ): Int

    /** Konuşmanın favori durumunu güncelle. */
    suspend fun updateConversationFavorite(conversationId: String, isFavorite: Boolean)

    /** Konuşmanın sessiz modunu güncelle. */
    suspend fun updateConversationMuted(conversationId: String, isMuted: Boolean)

    /** Tum sohbetlerde mesaj ara. */
    suspend fun searchAllMessages(query: String): List<LocalMessage>

    /** Belirli bir sohbetin tum mesajlarini kronolojik sirada getir (export icin). */
    suspend fun getAllMessagesForConversation(conversationId: String): List<LocalMessage>

    /** Mesajin reaksiyon verisini guncelle. */
    suspend fun updateMessageReactions(messageId: String, reactions: String?)

    /** Tek gosterimlik medya mesajini goruntulendi olarak isaretle. */
    suspend fun markViewOnceAsViewed(messageId: String)

    /** Konuşmanın biyometrik kilit durumunu güncelle. */
    suspend fun updateConversationLocked(conversationId: String, isLocked: Boolean)

    /**
     * SENDING durumunda takilmis mesajlari FAILED olarak isaretler.
     * Uygulama baslatildiginda cagrilir — belirtilen cutoff'tan eski SENDING mesajlar kurtarilir.
     * @param cutoff Bu zamandan eski SENDING mesajlar FAILED yapilir (milisaniye timestamp)
     * @return Guncellenen mesaj sayisi
     */
    suspend fun markStuckMessagesAsFailed(cutoff: Long): Int
}
