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
 * Asenkron calisir — ana akisi bloklamaz.
 *
 * GUVENLIK (M10 fix): IP adresleri anonymize edilir.
 * - IPv4: son octet 0'lanir (1.2.3.4 → 1.2.3.0) — /24 subnet seviyesinde tutulur.
 * - IPv6: son 80 bit (suffix) 0'lanir — /48 prefix seviyesinde tutulur.
 * Bu GDPR'ya uygun anonymization saglar (Article 4(5) pseudonymization).
 * Abuse detection ve coarse geo-correlation icin yeterli, kullaniciya geri bagli degil.
 *
 * userId UUID DB'de internal — log aggregation'a leak olmaz (postgres icinde audit_log).
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
                val anonymizedIp = ipAddress?.let { anonymizeIp(it) }
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
                        if (anonymizedIp != null) stmt.setString(4, anonymizedIp) else stmt.setNull(4, java.sql.Types.OTHER)
                        stmt.executeUpdate()
                    }
                }
            } catch (e: Exception) {
                log.warn("[!] AuditLog yazma hatasi: ${e.message}")
            }
        }
    }

    /**
     * IP anonymization: GDPR-compliant (Article 4(5)).
     * IPv4: 1.2.3.4 → 1.2.3.0
     * IPv6: fe80::1234:5678 → fe80::
     * Gecersiz IP icin null doner.
     */
    private fun anonymizeIp(ip: String): String? {
        val trimmed = ip.trim().removePrefix("::ffff:")  // IPv4-mapped IPv6
        return when {
            trimmed.contains(':') -> {
                // IPv6 — ilk 3 hextet (48 bit) tut, gerisini :: yap
                val parts = trimmed.split(':')
                if (parts.size < 3) return null
                parts.take(3).joinToString(":") + "::"
            }
            trimmed.contains('.') -> {
                // IPv4 — son octet'i 0 yap
                val octets = trimmed.split('.')
                if (octets.size != 4) return null
                "${octets[0]}.${octets[1]}.${octets[2]}.0"
            }
            else -> null
        }
    }
}
