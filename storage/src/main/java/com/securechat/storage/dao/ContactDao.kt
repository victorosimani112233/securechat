package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securechat.storage.entity.ContactEntity
import kotlinx.coroutines.flow.Flow

/**
 * Rehber kisisi veri erisim nesnesi. Arama ve filtreleme islemlerini destekler.
 */
@Dao
interface ContactDao {

    @Query("SELECT * FROM contacts ORDER BY display_name ASC")
    fun getAll(): Flow<List<ContactEntity>>

    @Query("SELECT * FROM contacts WHERE is_registered = 1 ORDER BY display_name ASC")
    fun getRegistered(): Flow<List<ContactEntity>>

    @Query("SELECT * FROM contacts WHERE phone_hash IN (:hashes)")
    suspend fun getByHashes(hashes: List<String>): List<ContactEntity>

    @Query("SELECT * FROM contacts WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): ContactEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(contact: ContactEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(contacts: List<ContactEntity>)

    @Update
    suspend fun update(contact: ContactEntity)

    @Query("DELETE FROM contacts WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM contacts WHERE display_name LIKE '%' || :query || '%' OR phone_number LIKE '%' || :query || '%'")
    fun search(query: String): Flow<List<ContactEntity>>
}
