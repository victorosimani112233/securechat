package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.SessionEntity

/**
 * Session veri erisim nesnesi. Session id formati: "$name:$deviceId"
 */
@Dao
interface SessionDao {

    @Query("SELECT * FROM sessions WHERE id = :id")
    suspend fun get(id: String): SessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: SessionEntity)

    @Query("DELETE FROM sessions WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT EXISTS(SELECT 1 FROM sessions WHERE id = :id)")
    suspend fun exists(id: String): Boolean

    @Query("DELETE FROM sessions WHERE id LIKE :name || ':%'")
    suspend fun deleteAllForName(name: String)

    @Query("SELECT id FROM sessions WHERE id LIKE :name || ':%'")
    suspend fun getSessionIdsForName(name: String): List<String>
}
