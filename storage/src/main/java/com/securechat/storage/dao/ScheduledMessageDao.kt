package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.ScheduledMessageEntity
import kotlinx.coroutines.flow.Flow

/**
 * Planli mesajlar veritabani erisim nesnesi.
 */
@Dao
interface ScheduledMessageDao {

    @Query("SELECT * FROM scheduled_messages ORDER BY next_trigger_time ASC")
    fun getAll(): Flow<List<ScheduledMessageEntity>>

    @Query("SELECT * FROM scheduled_messages WHERE id = :id")
    suspend fun getById(id: String): ScheduledMessageEntity?

    @Query("SELECT * FROM scheduled_messages WHERE is_enabled = 1 AND next_trigger_time <= :now ORDER BY next_trigger_time ASC")
    suspend fun getDueMessages(now: Long): List<ScheduledMessageEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: ScheduledMessageEntity)

    @Update
    suspend fun update(entity: ScheduledMessageEntity)

    @Query("DELETE FROM scheduled_messages WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM scheduled_messages")
    suspend fun deleteAll()
}
