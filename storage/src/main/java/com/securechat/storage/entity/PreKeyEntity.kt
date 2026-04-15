package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * One-time PreKey entity'si. Tek kullanimliktir ve kullanildiktan sonra silinir.
 */
@Entity(tableName = "prekeys")
data class PreKeyEntity(
    @PrimaryKey val id: Int,
    @ColumnInfo(name = "record", typeAffinity = ColumnInfo.BLOB) val record: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as PreKeyEntity
        if (id != other.id) return false
        if (!record.contentEquals(other.record)) return false
        return true
    }

    override fun hashCode(): Int {
        var result = id
        result = 31 * result + record.contentHashCode()
        return result
    }
}
