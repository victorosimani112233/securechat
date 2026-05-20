package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Sureli mesaj timer degisikligi karsi tarafa iletilemedi (WS kapali / offline) — kuyrukta tutulur.
 * Reconnect callback bu kuyrugu flush eder ve karsi taraf timer'i guncel olur.
 *
 * Bir konusma icin birden cok pending update varsa en yenisi gecerlidir; flush sirasinda
 * eskiler de gonderilir cunku karsi taraf "update_time aldim" sinyali tutmuyor — basit FIFO
 * yeterli.
 */
@Entity(tableName = "pending_timer_updates")
data class PendingTimerUpdateEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    @ColumnInfo(name = "conversation_id") val conversationId: String,
    @ColumnInfo(name = "target_user_id") val targetUserId: String,
    @ColumnInfo(name = "duration") val duration: Long,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis()
)
