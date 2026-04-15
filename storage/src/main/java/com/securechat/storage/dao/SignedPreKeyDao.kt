package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.SignedPreKeyEntity

/**
 * Signed PreKey veri erisim nesnesi.
 */
@Dao
interface SignedPreKeyDao {

    @Query("SELECT * FROM signed_prekeys WHERE id = :id")
    suspend fun get(id: Int): SignedPreKeyEntity?

    @Query("SELECT * FROM signed_prekeys")
    suspend fun getAll(): List<SignedPreKeyEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(signedPreKey: SignedPreKeyEntity)

    @Query("DELETE FROM signed_prekeys WHERE id = :id")
    suspend fun delete(id: Int)

    @Query("SELECT EXISTS(SELECT 1 FROM signed_prekeys WHERE id = :id)")
    suspend fun exists(id: Int): Boolean
}
