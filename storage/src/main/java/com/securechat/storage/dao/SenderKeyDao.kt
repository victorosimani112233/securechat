package com.securechat.storage.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.securechat.storage.entity.SenderKeyEntity

/**
 * SenderKey veri erisim nesnesi. Composite primary key (group_id, sender_id, device_id).
 */
@Dao
interface SenderKeyDao {

    @Query("SELECT * FROM sender_keys WHERE group_id = :groupId AND sender_id = :senderId AND device_id = :deviceId")
    suspend fun get(groupId: String, senderId: String, deviceId: Int): SenderKeyEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(entity: SenderKeyEntity)

    @Query("DELETE FROM sender_keys WHERE group_id = :groupId AND sender_id = :senderId AND device_id = :deviceId")
    suspend fun delete(groupId: String, senderId: String, deviceId: Int)

    @Query("DELETE FROM sender_keys WHERE group_id = :groupId")
    suspend fun deleteAllForGroup(groupId: String)

    @Query("SELECT EXISTS(SELECT 1 FROM sender_keys WHERE group_id = :groupId AND sender_id = :senderId AND device_id = :deviceId)")
    suspend fun exists(groupId: String, senderId: String, deviceId: Int): Boolean
}
