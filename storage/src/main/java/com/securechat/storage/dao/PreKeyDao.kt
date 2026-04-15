package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.PreKeyEntity

/**
 * One-time PreKey veri erisim nesnesi.
 */
@Dao
interface PreKeyDao {

    @Query("SELECT * FROM prekeys WHERE id = :id")
    suspend fun get(id: Int): PreKeyEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(preKey: PreKeyEntity)

    @Query("DELETE FROM prekeys WHERE id = :id")
    suspend fun delete(id: Int)

    @Query("SELECT COUNT(*) FROM prekeys")
    suspend fun count(): Int

    @Query("SELECT MAX(id) FROM prekeys")
    suspend fun maxId(): Int?

    @Query("SELECT EXISTS(SELECT 1 FROM prekeys WHERE id = :id)")
    suspend fun exists(id: Int): Boolean
}
