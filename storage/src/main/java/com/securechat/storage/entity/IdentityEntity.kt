package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.securechat.storage.model.TrustLevel

/**
 * Identity key entity'si. Uzak kullanicilarin kimlik anahtarlarini saklar.
 */
@Entity(tableName = "identities")
data class IdentityEntity(
    @PrimaryKey val addressName: String,
    @ColumnInfo(name = "identity_key", typeAffinity = ColumnInfo.BLOB) val identityKey: ByteArray,
    @ColumnInfo(name = "trust_level") val trustLevel: TrustLevel
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as IdentityEntity
        if (addressName != other.addressName) return false
        if (!identityKey.contentEquals(other.identityKey)) return false
        if (trustLevel != other.trustLevel) return false
        return true
    }

    override fun hashCode(): Int {
        var result = addressName.hashCode()
        result = 31 * result + identityKey.contentHashCode()
        result = 31 * result + trustLevel.hashCode()
        return result
    }
}
