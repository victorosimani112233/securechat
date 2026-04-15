package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.CallLogEntity
import kotlinx.coroutines.flow.Flow

/**
 * Arama gecmisi veritabani erisim nesnesi.
 */
@Dao
interface CallLogDao {

    @Query("SELECT * FROM call_log ORDER BY timestamp DESC")
    fun getAll(): Flow<List<CallLogEntity>>

    @Query("SELECT * FROM call_log WHERE peer_id = :peerId ORDER BY timestamp DESC")
    fun getByPeerId(peerId: String): Flow<List<CallLogEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(callLog: CallLogEntity)

    @Query("DELETE FROM call_log WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM call_log")
    suspend fun deleteAll()
}
