package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Konuşma entity'si. Son mesaj ve okunmamis sayisini tutar.
 */
@Entity(
    tableName = "conversations",
    indices = [
        Index(value = ["last_message_timestamp"]),
        Index(value = ["peer_id"]),
        Index(value = ["is_archived"]),
        Index(value = ["is_pinned", "last_message_timestamp"])
    ]
)
data class ConversationEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "peer_id") val peerId: String,
    @ColumnInfo(name = "peer_name") val peerName: String,
    @ColumnInfo(name = "peer_phone") val peerPhone: String,
    @ColumnInfo(name = "last_message") val lastMessage: String?,
    @ColumnInfo(name = "last_message_timestamp") val lastMessageTimestamp: Long?,
    @ColumnInfo(name = "unread_count") val unreadCount: Int = 0,
    @ColumnInfo(name = "is_muted") val isMuted: Boolean = false,
    @ColumnInfo(name = "is_pinned") val isPinned: Boolean = false,
    @ColumnInfo(name = "is_group") val isGroup: Boolean = false,
    @ColumnInfo(name = "group_members") val groupMembers: String? = null, // virgul ile ayrilmis userId listesi
    @ColumnInfo(name = "contact_note") val contactNote: String? = null,
    @ColumnInfo(name = "custom_notification_uri") val customNotificationUri: String? = null,
    @ColumnInfo(name = "is_archived") val isArchived: Boolean = false,
    @ColumnInfo(name = "disappearing_duration") val disappearingDuration: Long = 0, // milisaniye, 0 = kapali
    @ColumnInfo(name = "group_admins") val groupAdmins: String? = null, // virgul ile ayrilmis admin userId listesi
    @ColumnInfo(name = "is_favorite") val isFavorite: Boolean = false,
    @ColumnInfo(name = "is_locked") val isLocked: Boolean = false // Biyometrik kilit
)
