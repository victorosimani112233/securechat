package com.securechat.botapi.db

import com.securechat.botapi.auth.AuthenticatedClient
import org.slf4j.LoggerFactory
import java.security.SecureRandom
import java.sql.Timestamp
import java.time.Instant
import java.util.Base64
import java.util.UUID

private val log = LoggerFactory.getLogger("ApiClientRepository")

/**
 * api_client tablosu icin DAO.
 *
 * Tum sorgular HikariCP connection ile prepared statement uzerinden yapilir.
 * Bot-api Flyway calistirmaz; bu repo schema'nin var oldugunu varsayar.
 */
object ApiClientRepository {

    private val rng = SecureRandom()

    /**
     * Yeni client ekler. kid sunucu uretir (16 byte random → "k_" prefix + base64url).
     * @return olusturulan kid
     */
    fun create(
        name: String,
        publicKey: ByteArray,
        allowList: List<String>,
        ratePerHour: Int = 50,
        perRecipientPerDay: Int = 500,
        expiresAt: Instant? = null
    ): String {
        require(publicKey.size == 32) { "Ed25519 public key 32 byte olmali" }
        require(ratePerHour in 1..10_000) { "ratePerHour 1-10000 arasi olmali" }

        val kid = generateKid()
        val sealedName = ApiClientPrivateFields.sealName(kid, name)
        val sealedAllowList = ApiClientPrivateFields.sealAllowList(kid, allowList)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """INSERT INTO api_client(kid, name, public_key, allow_list,
                       rate_per_hour, per_recipient_per_day, expires_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)"""
            ).use { stmt ->
                stmt.setString(1, kid)
                stmt.setString(2, sealedName)
                stmt.setBytes(3, publicKey)
                stmt.setArray(4, conn.createArrayOf("TEXT", arrayOf(sealedAllowList)))
                stmt.setInt(5, ratePerHour)
                stmt.setInt(6, perRecipientPerDay)
                if (expiresAt != null) stmt.setTimestamp(7, Timestamp.from(expiresAt))
                else stmt.setNull(7, java.sql.Types.TIMESTAMP_WITH_TIMEZONE)
                stmt.executeUpdate()
            }
        }
        log.info("[ApiClient] Yeni client olusturuldu; allowListSize={}", allowList.size)
        return kid
    }

    /** kid ile aktif (revoked olmayan, suresi gecmemis) client'i bulur. */
    fun findActiveByKid(kid: String): AuthenticatedClient? {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT client_id, kid, name, public_key, allow_list,
                          rate_per_hour, per_recipient_per_day, expires_at, revoked_at
                   FROM api_client
                   WHERE kid = ?
                     AND revoked_at IS NULL
                     AND (expires_at IS NULL OR expires_at > NOW())"""
            ).use { stmt ->
                stmt.setString(1, kid)
                stmt.executeQuery().use { rs ->
                    if (!rs.next()) return null
                    val allowArr = rs.getArray("allow_list").array as Array<*>
                    val storedKid = rs.getString("kid")
                    return AuthenticatedClient(
                        clientId = rs.getObject("client_id", UUID::class.java).toString(),
                        kid = storedKid,
                        name = ApiClientPrivateFields.openName(storedKid, rs.getString("name")),
                        publicKey = rs.getBytes("public_key"),
                        allowList = openAllowList(storedKid, allowArr),
                        ratePerHour = rs.getInt("rate_per_hour"),
                        perRecipientPerDay = rs.getInt("per_recipient_per_day")
                    )
                }
            }
        }
    }

    fun listAll(): List<ClientSummary> {
        val out = mutableListOf<ClientSummary>()
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT kid, name, allow_list, rate_per_hour, per_recipient_per_day,
                          expires_at, revoked_at, created_at
                   FROM api_client ORDER BY created_at DESC"""
            ).use { stmt ->
                stmt.executeQuery().use { rs ->
                    while (rs.next()) {
                        val allowArr = rs.getArray("allow_list").array as Array<*>
                        val storedKid = rs.getString("kid")
                        out += ClientSummary(
                            kid = storedKid,
                            name = ApiClientPrivateFields.openName(storedKid, rs.getString("name")),
                            allowList = openAllowList(storedKid, allowArr),
                            ratePerHour = rs.getInt("rate_per_hour"),
                            perRecipientPerDay = rs.getInt("per_recipient_per_day"),
                            expiresAt = rs.getTimestamp("expires_at")?.toInstant(),
                            revokedAt = rs.getTimestamp("revoked_at")?.toInstant(),
                            createdAt = rs.getTimestamp("created_at").toInstant()
                        )
                    }
                }
            }
        }
        return out
    }

    /** Revoke (anlik etki — cache invalidate pub/sub ile birlikte cagrilmali). */
    fun revoke(kid: String, reason: String? = null): Boolean {
        val safeReason = when (reason) {
            "rotate" -> "rotate"
            "expired" -> "expired"
            "compromised" -> "compromised"
            else -> "admin"
        }
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """UPDATE api_client
                   SET revoked_at = NOW(), revoke_reason = ?, updated_at = NOW()
                   WHERE kid = ? AND revoked_at IS NULL"""
            ).use { stmt ->
                stmt.setString(1, safeReason)
                stmt.setString(2, kid)
                return stmt.executeUpdate() > 0
            }
        }
    }

    private fun generateKid(): String {
        val bytes = ByteArray(16).also { rng.nextBytes(it) }
        return "k_" + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    private fun openAllowList(kid: String, stored: Array<*>): List<String> {
        require(stored.size == 1) { "Plaintext API client allow-list rejected" }
        return ApiClientPrivateFields.openAllowList(kid, stored.single().toString())
    }

    data class ClientSummary(
        val kid: String,
        val name: String,
        val allowList: List<String>,
        val ratePerHour: Int,
        val perRecipientPerDay: Int,
        val expiresAt: Instant?,
        val revokedAt: Instant?,
        val createdAt: Instant
    )
}
