package com.securechat.botapi.audit

import com.securechat.botapi.db.BotDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import java.sql.Types

private val log = LoggerFactory.getLogger("BotAuditLog")
private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/**
 * Bot-api audit yardimcisi — signaling-server'in audit_log tablosuna
 * BOT_API_* event_type'lariyla append-only kayit yazar.
 *
 * Plaintext mesaj iceriği KESINLIKLE yazilmaz; sadece metadata
 * (recipientId, kid, messageId, status, reason vs.).
 *
 * Async: CoroutineScope IO ile fire-and-forget; pipeline latency'sini
 * etkilemez. Hata durumunda warn loglar, asla istisna firlatmaz.
 */
object BotAuditLog {

    fun log(
        eventType: String,
        userId: String? = null,
        metadata: Map<String, String>? = null,
        ipAddress: String? = null
    ) {
        scope.launch {
            try {
                writeRow(eventType, userId, metadata, ipAddress)
            } catch (e: Exception) {
                log.warn("[BotAudit] Yazma hatasi: event={}, {}", eventType, e.message)
            }
        }
    }

    private fun writeRow(
        eventType: String,
        userId: String?,
        metadata: Map<String, String>?,
        ipAddress: String?
    ) {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """INSERT INTO audit_log(user_id, event_type, metadata, ip_address)
                   VALUES (?::uuid, ?, ?::jsonb, ?::inet)"""
            ).use { stmt ->
                if (userId != null) stmt.setString(1, userId) else stmt.setNull(1, Types.OTHER)
                stmt.setString(2, eventType)
                if (metadata != null) stmt.setString(3, toJson(metadata)) else stmt.setNull(3, Types.OTHER)
                if (ipAddress != null) stmt.setString(4, ipAddress) else stmt.setNull(4, Types.OTHER)
                stmt.executeUpdate()
            }
        }
    }

    private fun toJson(map: Map<String, String>): String {
        val sb = StringBuilder("{")
        var first = true
        for ((k, v) in map) {
            if (!first) sb.append(",")
            sb.append('"').append(escape(k)).append("\":\"").append(escape(v)).append('"')
            first = false
        }
        sb.append("}")
        return sb.toString()
    }

    private fun escape(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"")
}
