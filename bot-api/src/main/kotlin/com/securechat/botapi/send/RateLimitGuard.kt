package com.securechat.botapi.send

import com.securechat.botapi.auth.AuthenticatedClient
import com.securechat.botapi.db.BotRedisManager
import org.slf4j.LoggerFactory
import redis.clients.jedis.params.ZAddParams
import java.util.UUID

private val log = LoggerFactory.getLogger("RateLimitGuard")

/**
 * 3-katmanli rate limit (sliding window, Redis sorted set):
 *   1. per-client per-hour  → client.ratePerHour
 *   2. per-recipient per-day → client.perRecipientPerDay (bol limit, default 500)
 *   3. global per-minute    → 1000 (emergency brake)
 *
 * Group send = 1 unit (member sayisi kadar degil) — Plan #10.
 *
 * Algoritma signaling-server/RateLimiter.kt'tekiyle ayni (sliding window
 * sorted set). Cross-module dep yerine local impl.
 */
object RateLimitGuard {

    private const val GLOBAL_LIMIT_PER_MINUTE = 1000

    data class Result(val allowed: Boolean, val reason: String? = null, val retryAfterSeconds: Long = 0)

    fun check(client: AuthenticatedClient, recipientRef: String): Result {
        // 1. Per-client per-hour
        val perClientResult = window(
            key = "bot_rl:client:${client.clientId}",
            windowSeconds = 3600,
            maxRequests = client.ratePerHour
        )
        if (!perClientResult.allowed) {
            return Result(false, "client_per_hour", perClientResult.retryAfterSeconds)
        }

        // 2. Per-recipient per-day
        val perRecipientResult = window(
            key = "bot_rl:recipient:${client.clientId}:$recipientRef",
            windowSeconds = 86400,
            maxRequests = client.perRecipientPerDay
        )
        if (!perRecipientResult.allowed) {
            return Result(false, "recipient_per_day", perRecipientResult.retryAfterSeconds)
        }

        // 3. Global per-minute brake
        val globalResult = window(
            key = "bot_rl:global",
            windowSeconds = 60,
            maxRequests = GLOBAL_LIMIT_PER_MINUTE
        )
        if (!globalResult.allowed) {
            return Result(false, "global", globalResult.retryAfterSeconds)
        }

        return Result(true)
    }

    private fun window(key: String, windowSeconds: Int, maxRequests: Int): Result {
        return BotRedisManager.use { jedis ->
            val now = System.currentTimeMillis()
            val windowStart = now - windowSeconds * 1000L

            jedis.zremrangeByScore(key, "-inf", windowStart.toString())
            val count = jedis.zcard(key)
            if (count >= maxRequests) {
                // Retry-after = en eski entry'nin window'dan çıkmasına kalan saniye
                val oldest = jedis.zrangeWithScores(key, 0, 0).firstOrNull()?.score?.toLong() ?: now
                val retryAfter = (oldest + windowSeconds * 1000L - now) / 1000L
                return@use Result(false, retryAfterSeconds = retryAfter.coerceAtLeast(1))
            }
            val member = "${now}-${UUID.randomUUID()}"
            jedis.zadd(key, now.toDouble(), member, ZAddParams.zAddParams())
            jedis.expire(key, windowSeconds + 60L)  // TTL biraz fazlasi — auto cleanup
            Result(true)
        }
    }
}
