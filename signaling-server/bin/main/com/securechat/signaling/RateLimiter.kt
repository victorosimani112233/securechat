package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("RateLimiter")

/**
 * Redis tabanli sliding window rate limiter.
 * Key: ratelimit:{endpoint}:{identifier}
 */
object RateLimiter {

    data class RateLimit(val maxRequests: Int, val windowSeconds: Long)

    // Endpoint bazli limitler
    val LIMITS = mapOf(
        "users_check" to RateLimit(10, 60),         // 10 req/dakika per IP
        "users_register" to RateLimit(5, 3600),      // 5 req/saat per IP
        "ice_config" to RateLimit(30, 3600),          // 30 req/saat per userId
        "ws_message" to RateLimit(100, 1),            // 100 msg/sn per userId
        "otp_request" to RateLimit(5, 600),           // 5 req/10dk per IP (OTP istegi)
        "otp_verify" to RateLimit(20, 600)            // 20 req/10dk per IP (brute force korumasi zaten OTP servisinde)
    )

    /**
     * Rate limit kontrolu yapar.
     * @return true = izin verildi, false = limit asildi
     */
    fun allow(endpoint: String, identifier: String): Boolean {
        val limit = LIMITS[endpoint] ?: return true
        val key = "ratelimit:$endpoint:$identifier"
        val now = System.currentTimeMillis()
        val windowStart = now - (limit.windowSeconds * 1000)

        return try {
            RedisManager.use { jedis ->
                // Eski kayitlari temizle
                jedis.zremrangeByScore(key, "-inf", windowStart.toDouble().toString())
                // Mevcut istek sayisi
                val count = jedis.zcard(key)
                if (count >= limit.maxRequests) {
                    false
                } else {
                    jedis.zadd(key, now.toDouble(), "$now")
                    jedis.expire(key, limit.windowSeconds + 1)
                    true
                }
            }
        } catch (e: Exception) {
            // GUVENLIK: Redis down ise FAIL-CLOSED — istek reddedilir.
            // Onceki davranis (true donmek) DoS acigi yaratiyordu:
            // saldirgan Redis'i devre disi birakirsa rate-limit kapanir.
            log.error("[!] RateLimiter Redis hatasi — fail-closed reddediliyor: ${e.message}")
            false
        }
    }

    /**
     * Limit asiladiginda kalan sure (saniye).
     */
    fun retryAfter(endpoint: String, identifier: String): Long {
        val limit = LIMITS[endpoint] ?: return 0
        val key = "ratelimit:$endpoint:$identifier"
        return try {
            RedisManager.use { jedis ->
                val oldest = jedis.zrangeWithScores(key, 0, 0)
                if (oldest.isNotEmpty()) {
                    val oldestTime = oldest.first().score.toLong()
                    val windowEnd = oldestTime + (limit.windowSeconds * 1000)
                    val remaining = (windowEnd - System.currentTimeMillis()) / 1000
                    if (remaining > 0) remaining else 0
                } else 0
            }
        } catch (_: Exception) { 0 }
    }
}
