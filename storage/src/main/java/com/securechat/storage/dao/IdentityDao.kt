package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.IdentityEntity

/**
 * Identity key veri erisim nesnesi. Uzak kullanicilarin kimlik anahtarlarini yonetir.
 */
@Dao
interface IdentityDao {

    @Query("SELECT * FROM identities WHERE addressName = :name")
    suspend fun get(name: String): IdentityEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(identity: IdentityEntity)

    @Query("DELETE FROM identities WHERE addressName = :name")
    suspend fun delete(name: String)

    @Query("SELECT EXISTS(SELECT 1 FROM identities WHERE addressName = :name)")
    suspend fun exists(name: String): Boolean
}
