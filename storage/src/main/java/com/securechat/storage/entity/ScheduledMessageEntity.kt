package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Planli mesaj entity'si.
 * Kullanici tarafindan olusturulan zamanlanmis mesajlari saklar.
 *
 * repeatType:
 *   ONCE      — tek seferlik
 *   DAILY     — her gun
 *   CUSTOM    — secilen gunler (repeatDays ile belirtilir)
 *
 * repeatDays: virgul ile ayrilmis gun numaralari (1=Pzt ... 7=Paz), orn. "1,3,5"
 *             ONCE ve DAILY icin null.
 *
 * recipientIds: virgul ile ayrilmis alici userId listesi, orn. "uuid1,uuid2"
 * recipientNames: virgul ile ayrilmis alici isim listesi (gosterim icin)
 */
@Entity(
    tableName = "scheduled_messages",
    indices = [Index(value = ["next_trigger_time"])]
)
data class ScheduledMessageEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "message_content") val messageContent: String,
    @ColumnInfo(name = "repeat_type") val repeatType: String,         // ONCE, DAILY, CUSTOM
    @ColumnInfo(name = "repeat_days") val repeatDays: String? = null, // "1,3,5" — Pzt,Car,Cum
    @ColumnInfo(name = "hour") val hour: Int,
    @ColumnInfo(name = "minute") val minute: Int,
    @ColumnInfo(name = "recipient_ids") val recipientIds: String,     // "uuid1,uuid2"
    @ColumnInfo(name = "recipient_names") val recipientNames: String, // "Ali,Veli"
    @ColumnInfo(name = "is_enabled") val isEnabled: Boolean = true,
    @ColumnInfo(name = "next_trigger_time") val nextTriggerTime: Long,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis()
)
