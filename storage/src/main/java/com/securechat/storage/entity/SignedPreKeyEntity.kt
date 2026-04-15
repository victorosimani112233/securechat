package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Signed PreKey entity'si. Periyodik olarak rotate edilir (varsayilan 7 gun).
 */
@Entity(tableName = "signed_prekeys")
data class SignedPreKeyEntity(
    @PrimaryKey val id: Int,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray,
    @ColumnInfo(name = "created_at") val createdAt: Long
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as SignedPreKeyEntity
        if (id != other.id) return false
        if (!record.contentEquals(other.record)) return false
        if (createdAt != other.createdAt) return false
        return true
    }

    override fun hashCode(): Int {
        var result = id
        result = 31 * result + record.contentHashCode()
        result = 31 * result + createdAt.hashCode()
        return result
    }
}
