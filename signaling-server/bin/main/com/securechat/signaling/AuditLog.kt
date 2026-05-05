package com.securechat.signaling

import com.securechat.signaling.db.Database
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("AuditLog")

/**
 * Guvenlik olaylarini PostgreSQL audit_log tablosuna kaydeder.
 * Asenkron calısir — ana akisi bloklamaz.
 */
object AuditLog {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun log(
        userId: String? = null,
        eventType: String,
        metadata: Map<String, String>? = null,
        ipAddress: String? = null
    ) {
        scope.launch {
            try {
                val metadataJson = metadata?.let { map ->
                    "{" + map.entries.joinToString(",") { (k, v) ->
                        "\"$k\":\"${v.replace("\"", "\\\"")}\""
                    } + "}"
                }
                Database.getConnection().use { conn ->
                    // userId UUID formatinda olmayabilir (eski kayitlar) — validate et
                    val validUuid = userId?.let {
                        try { java.util.UUID.fromString(it); it } catch (_: Exception) { null }
                    }
                    conn.prepareStatement(
                        "INSERT INTO audit_log (user_id, event_type, metadata, ip_address) VALUES (?::uuid, ?, ?::jsonb, ?::inet)"
                    ).use { stmt ->
                        if (validUuid != null) stmt.setString(1, validUuid) else stmt.setNull(1, java.sql.Types.OTHER)
                        stmt.setString(2, eventType)
                        if (metadataJson != null) stmt.setString(3, metadataJson) else stmt.setNull(3, java.sql.Types.OTHER)
                        if (ipAddress != null) stmt.setString(4, ipAddress) else stmt.setNull(4, java.sql.Types.OTHER)
                        stmt.executeUpdate()
                    }
                }
            } catch (e: Exception) {
                log.warn("[!] AuditLog yazma hatasi: ${e.message}")
            }
        }
    }
}
