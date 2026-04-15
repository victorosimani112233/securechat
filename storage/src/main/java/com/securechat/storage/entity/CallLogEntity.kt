package com.securechat.storage.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Arama gecmisi kaydi.
 * Her arama (gelen, giden, cevapsiz) icin bir kayit olusturulur.
 */
@Entity(
    tableName = "call_log",
    indices = [Index(value = ["timestamp"])]
)
data class CallLogEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "peer_id") val peerId: String,
    @ColumnInfo(name = "peer_name") val peerName: String,
    @ColumnInfo(name = "call_type") val callType: String,       // VOICE, VIDEO
    @ColumnInfo(name = "direction") val direction: String,      // INCOMING, OUTGOING
    @ColumnInfo(name = "status") val status: String,            // ANSWERED, MISSED, REJECTED, FAILED
    @ColumnInfo(name = "timestamp") val timestamp: Long,
    @ColumnInfo(name = "duration") val duration: Long = 0       // milisaniye
)
