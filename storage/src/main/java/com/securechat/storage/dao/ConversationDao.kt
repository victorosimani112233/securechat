package com.securechat.storage.dao

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.ConversationEntity
import kotlinx.coroutines.flow.Flow

/**
 * Son mesaj bilgisi — tek sorguda content + timestamp dondurur.
 */
data class LastMessageInfo(
    @ColumnInfo(name = "content") val content: String,
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "content_type") val contentType: String? = null,
    @ColumnInfo(name = "caption") val caption: String? = null,
    @ColumnInfo(name = "is_view_once") val isViewOnce: Boolean = false
)

/**
 * Konuşma veri erisim nesnesi. Konuşma listesi reaktif olarak guncellenir.
 */
@Dao
interface ConversationDao {

    @Query("SELECT * FROM conversations ORDER BY is_pinned DESC, last_message_timestamp DESC")
    fun getAll(): Flow<List<ConversationEntity>>

    @Query("SELECT * FROM conversations ORDER BY is_pinned DESC, last_message_timestamp DESC")
    suspend fun getAllImmediate(): List<ConversationEntity>

    /** Sender Key rotation worker icin: tum aktif grup konusmalari. */
    @Query("SELECT * FROM conversations WHERE is_group = 1")
    suspend fun getAllGroups(): List<ConversationEntity>

    @Query("SELECT * FROM conversations WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): ConversationEntity?

    @Query("SELECT * FROM conversations WHERE id = :id")
    fun observeById(id: String): kotlinx.coroutines.flow.Flow<ConversationEntity?>

    @Query("SELECT * FROM conversations WHERE peer_id = :peerId LIMIT 1")
    suspend fun getByPeerId(peerId: String): ConversationEntity?

    @Query("SELECT * FROM conversations WHERE peer_id IN (:peerIds)")
    suspend fun getByPeerIds(peerIds: List<String>): List<ConversationEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity)

    @Update
    suspend fun update(conversation: ConversationEntity)

    /**
     * Konusmayi okundu olarak isaretle — unread_count + manuallyUnread temizler.
     * ChatScreen acilinca cagrilir; kullanici daha once "Okunmadi isaretle" demis olsa bile
     * ekran acilinca silinir (bilincli karar — okuduktan sonra kosaca temizlenir).
     */
    @Query("UPDATE conversations SET unread_count = 0, manually_unread = 0 WHERE id = :conversationId")
    suspend fun markAsRead(conversationId: String)

    @Query("DELETE FROM conversations WHERE id = :conversationId")
    suspend fun delete(conversationId: String)

    @Query("UPDATE conversations SET group_members = :groupMembers WHERE id = :groupId")
    suspend fun updateGroupMembers(groupId: String, groupMembers: String)

    @Query("UPDATE conversations SET last_message = :message, last_message_timestamp = :timestamp WHERE peer_id = :peerId")
    suspend fun updateLastMessage(peerId: String, message: String, timestamp: Long)

    @Query("UPDATE conversations SET unread_count = unread_count + 1 WHERE peer_id = :peerId")
    suspend fun incrementUnreadCount(peerId: String)

    @Query("UPDATE conversations SET contact_note = :note WHERE id = :conversationId")
    suspend fun updateContactNote(conversationId: String, note: String?)

    @Query("UPDATE conversations SET custom_notification_uri = :uri WHERE id = :conversationId")
    suspend fun updateCustomNotification(conversationId: String, uri: String?)

    @Query("UPDATE conversations SET peer_name = :name WHERE id = :conversationId")
    suspend fun updatePeerName(conversationId: String, name: String)

    @Query("UPDATE conversations SET is_archived = :isArchived WHERE id = :conversationId")
    suspend fun updateArchived(conversationId: String, isArchived: Boolean)

    @Query("SELECT * FROM conversations WHERE is_archived = 1 ORDER BY last_message_timestamp DESC")
    fun getArchived(): Flow<List<ConversationEntity>>

    @Query("UPDATE conversations SET disappearing_duration = :duration WHERE id = :conversationId")
    suspend fun updateDisappearingDuration(conversationId: String, duration: Long)

    @Query("UPDATE conversations SET group_admins = :admins WHERE id = :conversationId")
    suspend fun updateGroupAdmins(conversationId: String, admins: String)

    @Query("UPDATE conversations SET is_favorite = :isFavorite WHERE id = :conversationId")
    suspend fun updateFavorite(conversationId: String, isFavorite: Boolean)

    @Query("UPDATE conversations SET is_muted = :isMuted WHERE id = :conversationId")
    suspend fun updateMuted(conversationId: String, isMuted: Boolean)

    @Query("UPDATE conversations SET is_locked = :isLocked WHERE id = :conversationId")
    suspend fun updateLocked(conversationId: String, isLocked: Boolean)

    // Sohbet disa aktarma izni — sadece admin toggle eder, propagation icin
    // GroupNotification + PendingExportPolicyFlusher kullanilir.
    @Query("UPDATE conversations SET is_export_enabled = :isEnabled WHERE id = :conversationId")
    suspend fun updateExportEnabled(conversationId: String, isEnabled: Boolean)

    /**
     * Belirtilen konusmadaki en son mesajin icerigini dondurur.
     * Mesaj silme veya duzenleme sonrasi lastMessage alanini yeniden hesaplamak icin kullanilir.
     */
    @Query("SELECT content FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT 1")
    suspend fun getLastMessageContent(conversationId: String): String?

    /**
     * Belirtilen konusmadaki en son mesajin zaman damgasini dondurur.
     * Mesaj silme veya duzenleme sonrasi lastMessageTimestamp alanini yeniden hesaplamak icin kullanilir.
     */
    @Query("SELECT timestamp FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT 1")
    suspend fun getLastMessageTimestamp(conversationId: String): Long?

    /**
     * Son mesaj icerik ve zaman damgasini tek sorguda dondurur (N+1 fix).
     */
    @Query("SELECT content, timestamp, content_type, caption, is_view_once FROM messages WHERE conversation_id = :conversationId ORDER BY timestamp DESC LIMIT 1")
    suspend fun getLastMessageInfo(conversationId: String): LastMessageInfo?

    /**
     * Konusmadaki son mesaji ID ile gunceller.
     * Silme veya duzenleme sonrasi konusma listesindeki onizleme metnini dogru gostermek icin kullanilir.
     */
    @Query("UPDATE conversations SET last_message = :message, last_message_timestamp = :timestamp WHERE id = :conversationId")
    suspend fun updateLastMessageById(conversationId: String, message: String, timestamp: Long)

    // Sureli mesaj cleanup sonrasi: konusmada hic mesaj kalmadiysa lastMessage null'a cekilir.
    @Query("UPDATE conversations SET last_message = NULL, last_message_timestamp = NULL WHERE id = :conversationId")
    suspend fun clearLastMessage(conversationId: String)

    /**
     * Manuel "Okunmadi isaretle" flag'i guncelle.
     * - true = kullanici konusmayi okunmamis isaretledi
     * - false = otomatik temizlik (sohbet ekrani acilinca, markAsRead sirasinda)
     */
    @Query("UPDATE conversations SET manually_unread = :manuallyUnread WHERE id = :conversationId")
    suspend fun updateManuallyUnread(conversationId: String, manuallyUnread: Boolean)
}
