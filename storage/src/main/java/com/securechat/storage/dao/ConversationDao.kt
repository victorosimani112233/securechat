package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.ConversationEntity
import kotlinx.coroutines.flow.Flow

/**
 * Konuşma veri erisim nesnesi. Konuşma listesi reaktif olarak guncellenir.
 */
@Dao
interface ConversationDao {

    @Query("SELECT * FROM conversations ORDER BY is_pinned DESC, last_message_timestamp DESC")
    fun getAll(): Flow<List<ConversationEntity>>

    @Query("SELECT * FROM conversations ORDER BY is_pinned DESC, last_message_timestamp DESC")
    suspend fun getAllImmediate(): List<ConversationEntity>

    @Query("SELECT * FROM conversations WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): ConversationEntity?

    @Query("SELECT * FROM conversations WHERE peer_id = :peerId LIMIT 1")
    suspend fun getByPeerId(peerId: String): ConversationEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity)

    @Update
    suspend fun update(conversation: ConversationEntity)

    @Query("UPDATE conversations SET unread_count = 0 WHERE id = :conversationId")
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
}
