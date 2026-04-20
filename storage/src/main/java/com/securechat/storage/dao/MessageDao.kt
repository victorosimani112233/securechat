package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.model.MessageStatus
import kotlinx.coroutines.flow.Flow

/**
 * Mesaj veri erisim nesnesi. Tum mesaj CRUD islemleri bu DAO uzerinden yapilir.
 * Flow donduren metodlar reaktif olarak degisiklikleri yayar.
 */
@Dao
interface MessageDao {

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp ASC")
    fun getMessages(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT :limit")
    fun getRecentMessages(conversationId: String, limit: Int): Flow<List<MessageEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: MessageEntity)

    @Update
    suspend fun update(message: MessageEntity)

    @Query("UPDATE messages SET status = :status WHERE id = :messageId")
    suspend fun updateStatus(messageId: String, status: MessageStatus)

    @Query("SELECT * FROM messages WHERE id = :messageId LIMIT 1")
    suspend fun getById(messageId: String): MessageEntity?

    @Query("DELETE FROM messages WHERE id = :messageId")
    suspend fun delete(messageId: String)

    @Query("DELETE FROM messages WHERE conversation_id = :conversationId")
    suspend fun deleteByConversation(conversationId: String)

    @Query("SELECT COUNT(*) FROM messages WHERE conversation_id = :conversationId AND status != 'READ' AND is_outgoing = 0")
    fun getUnreadCount(conversationId: String): Flow<Int>

    @Query("DELETE FROM messages WHERE timestamp < :cutoff")
    suspend fun deleteOlderThan(cutoff: Long)

    // 🗑️ Herkesten silme — icerik guncelleme
    @Query("UPDATE messages SET content = :content, content_type = :contentType WHERE id = :messageId")
    suspend fun updateContent(messageId: String, content: String, contentType: String)

    // ⭐ Yıldızlama özellikleri
    @Query("UPDATE messages SET is_starred = :isStarred WHERE id = :messageId")
    suspend fun updateStarred(messageId: String, isStarred: Boolean)

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND is_starred = 1 ORDER BY timestamp DESC")
    fun getStarredMessages(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE is_starred = 1 ORDER BY timestamp DESC")
    fun getAllStarredMessages(): Flow<List<MessageEntity>>

    // 🔍 Arama özellikleri
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND content LIKE :searchQuery ORDER BY timestamp DESC")
    fun searchMessages(conversationId: String, searchQuery: String): Flow<List<MessageEntity>>

    // 📱 Medya/Doküman özellikleri
    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND content_type IN ('IMAGE', 'VIDEO', 'AUDIO') ORDER BY timestamp DESC")
    fun getMediaMessages(conversationId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE conversation_id = :conversationId AND content_type = 'FILE' ORDER BY timestamp DESC")
    fun getDocumentMessages(conversationId: String): Flow<List<MessageEntity>>

    // Sureli mesaj — suresi dolan mesajlari sil
    @Query("DELETE FROM messages WHERE expires_at IS NOT NULL AND expires_at < :now")
    suspend fun deleteExpiredMessages(now: Long): Int
}
