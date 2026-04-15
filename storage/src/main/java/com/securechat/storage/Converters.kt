package com.securechat.storage

import androidx.room.TypeConverter
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.model.TrustLevel

/**
 * Room TypeConverter'lari. Enum degerlerini String olarak DB'ye yazar.
 */
class Converters {

    @TypeConverter
    fun fromMessageContentType(value: MessageContentType): String = value.name

    @TypeConverter
    fun toMessageContentType(value: String): MessageContentType =
        MessageContentType.valueOf(value)

    @TypeConverter
    fun fromMessageStatus(value: MessageStatus): String = value.name

    @TypeConverter
    fun toMessageStatus(value: String): MessageStatus =
        MessageStatus.valueOf(value)

    @TypeConverter
    fun fromTrustLevel(value: TrustLevel): String = value.name

    @TypeConverter
    fun toTrustLevel(value: String): TrustLevel =
        TrustLevel.valueOf(value)
}
