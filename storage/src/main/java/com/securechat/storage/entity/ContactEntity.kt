package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Rehber kisisi entity'si. Telefon numarasi hash'i ile eslestirilir.
 */
@Entity(tableName = "contacts")
data class ContactEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "phone_number") val phoneNumber: String,
    @ColumnInfo(name = "phone_hash") val phoneHash: String,
    @ColumnInfo(name = "display_name") val displayName: String,
    @ColumnInfo(name = "is_registered") val isRegistered: Boolean,
    @ColumnInfo(name = "avatar_uri") val avatarUri: String? = null,
    @ColumnInfo(name = "last_seen") val lastSeen: Long? = null
)
