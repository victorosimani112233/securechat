package com.securechat.botapi.auth

import com.securechat.botapi.db.ApiClientRepository
import com.securechat.botapi.db.BotRedisManager
import org.slf4j.LoggerFactory

private val credentialLog = LoggerFactory.getLogger("ClientCredentialResolver")

/**
 * Authoritative bot credential resolver.
 *
 * The historical type name is retained to keep the caller surface stable, but
 * positive credential/policy caching is intentionally forbidden. Every
 * request rechecks `revoked_at` and `expires_at` in PostgreSQL, fail-closed on
 * a database error. This also prevents decrypted names and recipient
 * allow-lists from living in process RAM beyond the request that uses them.
 */
object ClientKeyCache {
    private const val INVALIDATE_CHANNEL = "bot_api:client_invalidate"

    fun get(kid: String): AuthenticatedClient? =
        ApiClientRepository.findActiveByKid(kid)

    /**
     * Kept for safe rolling upgrades: older nodes may still have a bounded
     * cache and subscribe to this channel. Current nodes never depend on it.
     */
    fun broadcastInvalidate(kid: String) {
        try {
            BotRedisManager.use { it.publish(INVALIDATE_CHANNEL, kid) }
        } catch (error: Exception) {
            // The current process is already DB-authoritative. Do not turn a
            // compatibility broadcast failure into a credential bypass.
            credentialLog.warn(
                "[ClientCredential] Compatibility invalidation failed: {}",
                error.javaClass.simpleName,
            )
        }
    }
}
