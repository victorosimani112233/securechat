package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Grup admin'ine ozel sohbet disa aktarma olay kaydi (E2EE / zero-knowledge).
 *
 * - Server'da TUTULMAZ: log payload her admin icin ayri Signal Protocol session
 *   uzerinden sifrelenir, server sadece transient relay yapar.
 * - Her admin cihazinda sadece KENDI cozumledigi loglar bu tabloda durur.
 * - Yeni atanan admin gecmis loglari GORMEZ (gondericinin payloads map'inde
 *   onun userId'si olmadigi icin). Bu kasitli davranistir.
 *
 * Schema:
 *  - id: lokal UUID
 *  - groupId: hangi gruptaki olay
 *  - actorUserId: export'u yapan kullanicinin userId'si
 *  - actorDisplayName: olay anindaki gosterilen isim (sonradan rehber degisirse iz kalsin)
 *  - eventType: "EXPORT" (gelecekte "COPY_BULK" gibi gen isleyebilir)
 *  - timestamp: olay zamani (ms)
 *  - messageCount: export'a dahil edilen mesaj sayisi
 *  - firstMsgTs / lastMsgTs: export tarih araligi (ms); null ise tum sohbet
 */
@Entity(
    tableName = "export_log",
    indices = [
        Index(value = ["group_id", "timestamp"]),
        Index(value = ["timestamp"])
    ]
)
data class ExportLogEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "group_id") val groupId: String,
    @ColumnInfo(name = "actor_user_id") val actorUserId: String,
    @ColumnInfo(name = "actor_display_name") val actorDisplayName: String,
    @ColumnInfo(name = "event_type") val eventType: String,
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "message_count") val messageCount: Int,
    @ColumnInfo(name = "first_msg_ts") val firstMsgTs: Long? = null,
    @ColumnInfo(name = "last_msg_ts") val lastMsgTs: Long? = null
)
