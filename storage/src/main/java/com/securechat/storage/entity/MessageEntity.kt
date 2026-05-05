package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus

/**
 * Mesaj entity'si. SQLCipher ile sifrelenmis DB'de saklanir.
 * Konuşma silindiginde cascade ile mesajlar da silinir.
 */
@Entity(
    tableName = "messages",
    indices = [
        Index(value = ["conversation_id", "timestamp"]),
        Index(value = ["conversation_id", "is_outgoing", "status"]),
        Index(value = ["conversation_id", "content_type"]),
        Index(value = ["sender_id"]),
        Index(value = ["status"]),
        Index(value = ["is_starred"]),
        Index(value = ["expires_at"])
    ],
    foreignKeys = [
        ForeignKey(
            entity = ConversationEntity::class,
            parentColumns = ["id"],
            childColumns = ["conversation_id"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class MessageEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "conversation_id") val conversationId: String,
    @ColumnInfo(name = "sender_id") val senderId: String,
    @ColumnInfo(name = "content") val content: String,
    @ColumnInfo(name = "content_type") val contentType: MessageContentType,
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "status") val status: MessageStatus,
    @ColumnInfo(name = "reply_to_id") val replyToId: String? = null,
    @ColumnInfo(name = "is_outgoing") val isOutgoing: Boolean,
    @ColumnInfo(name = "is_starred") val isStarred: Boolean = false,
    @ColumnInfo(name = "expires_at") val expiresAt: Long? = null, // milisaniye timestamp, null = suresi dolmaz
    @ColumnInfo(name = "edited_at") val editedAt: Long? = null, // duzenleme zamani, null = duzenlenmedi
    @ColumnInfo(name = "edit_history") val editHistory: String? = null, // Onceki iceriklerin JSON dizisi
    @ColumnInfo(name = "reactions") val reactions: String? = null // Emoji reaksiyonlari JSON: {"👍":["userId1"],"❤️":["userId2"]}
)
