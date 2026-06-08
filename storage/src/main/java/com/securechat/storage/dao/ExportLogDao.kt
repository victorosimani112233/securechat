package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.ExportLogEntity
import kotlinx.coroutines.flow.Flow

/**
 * Grup admin'ine ozel sohbet disa aktarma loglari icin DAO.
 * Sadece KENDI cozumledigimiz loglar burada saklanir (zero-knowledge mimari).
 */
@Dao
interface ExportLogDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(entry: ExportLogEntity)

    /** Belirli bir grup icin export loglarini ters kronolojik sirayla akis olarak doner. */
    @Query("SELECT * FROM export_log WHERE group_id = :groupId ORDER BY timestamp DESC")
    fun observeForGroup(groupId: String): Flow<List<ExportLogEntity>>

    /** Belirli bir grup icin export sayisini doner — UI'da rozet/sayac icin. */
    @Query("SELECT COUNT(*) FROM export_log WHERE group_id = :groupId")
    suspend fun countForGroup(groupId: String): Int

    /** Grup silindiginde temizlik icin. */
    @Query("DELETE FROM export_log WHERE group_id = :groupId")
    suspend fun deleteForGroup(groupId: String)
}
