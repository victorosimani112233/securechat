package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * SenderKey entity'si. Grup mesajlasmasi (Sender Keys protokolu) icin her
 * (groupId, senderId, deviceId) ucluse karsilik bir SenderKeyRecord tutar.
 *
 * record alani SenderKeyRecord.serialize() ciktisidir (libsignal).
 */
@Entity(
    tableName = "sender_keys",
    primaryKeys = ["group_id", "sender_id", "device_id"]
)
data class SenderKeyEntity(
    @ColumnInfo(name = "group_id") val groupId: String,
    @ColumnInfo(name = "sender_id") val senderId: String,
    @ColumnInfo(name = "device_id") val deviceId: Int,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray,
    @ColumnInfo(name = "updated_at") val updatedAt: Long
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as SenderKeyEntity
        if (groupId != other.groupId) return false
        if (senderId != other.senderId) return false
        if (deviceId != other.deviceId) return false
        if (!record.contentEquals(other.record)) return false
        if (updatedAt != other.updatedAt) return false
        return true
    }

    override fun hashCode(): Int {
        var result = groupId.hashCode()
        result = 31 * result + senderId.hashCode()
        result = 31 * result + deviceId
        result = 31 * result + record.contentHashCode()
        result = 31 * result + updatedAt.hashCode()
        return result
    }
}
