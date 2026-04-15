package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Session entity'si. Her kullanici-cihaz cifti icin ayri bir session tutulur.
 * PrimaryKey formati: "$name:$deviceId"
 */
@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as SessionEntity
        if (id != other.id) return false
        if (!record.contentEquals(other.record)) return false
        return true
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + record.contentHashCode()
        return result
    }
}
