package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("JwtBlacklist")

/**
 * Redis tabanli JWT revocation listesi.
 * Logout veya guvenlik olayi durumunda token JTI'sini blacklist'e ekler.
 *
 * Storage: Redis key per JTI, TTL = token expiry kadar.
 *   key:   jwt_blacklist:<jti>
 *   value: 1 (varlik kontrolu yeterli)
 *
 * Bu yaklasim memory-efficient: token expire olunca Redis kaydi otomatik silinir.
 */
object JwtBlacklist {

    /** Token'i blacklist'e ekler. expiryMs = token'in dogal expire zamani (epoch ms). */
    fun revoke(jti: String, expiryMs: Long) {
        val ttlSec = ((expiryMs - System.currentTimeMillis()) / 1000).coerceAtLeast(1)
        try {
            RedisManager.use { jedis ->
                jedis.setex("jwt_blacklist:$jti", ttlSec, "1")
            }
            log.info("[Blacklist] Token revoke edildi: jti={} ttl={}s", jti, ttlSec)
        } catch (e: Exception) {
            log.error("[Blacklist] Revoke hatasi: {}", e.message)
        }
    }

    fun isRevoked(jti: String): Boolean {
        return try {
            RedisManager.use { jedis ->
                jedis.exists("jwt_blacklist:$jti")
            }
        } catch (e: Exception) {
            // Redis down — fail-CLOSED degil, sadece bu blacklist kontrolu icin fail-OPEN
            // (ana auth kontrolu RateLimiter ve verifier'da; burasi additional layer)
            log.warn("[Blacklist] Check hatasi (fail-open): {}", e.message)
            false
        }
    }
}
