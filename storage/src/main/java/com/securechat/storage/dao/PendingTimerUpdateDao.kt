package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.PendingTimerUpdateEntity

/**
 * Bekleyen sureli mesaj timer guncellemeleri DAO'su.
 * Karsi tarafa WS uzerinden anlik iletilemeyen DisappearingTimer signal'leri burada saklanir
 * ve reconnect callback ile flush edilir.
 */
@Dao
interface PendingTimerUpdateDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: PendingTimerUpdateEntity)

    @Query("SELECT * FROM pending_timer_updates ORDER BY created_at ASC")
    suspend fun getAll(): List<PendingTimerUpdateEntity>

    @Query("DELETE FROM pending_timer_updates WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM pending_timer_updates")
    suspend fun clear()
}
