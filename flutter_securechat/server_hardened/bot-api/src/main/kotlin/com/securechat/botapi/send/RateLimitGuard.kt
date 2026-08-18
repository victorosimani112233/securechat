package com.securechat.botapi.send

import com.securechat.botapi.auth.AuthenticatedClient
import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.delivery.BotQueuePrivacy
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
 * Group fanout her hedef icin bir unit tuketir; tek request ile limit
 * amplification'i yapilamaz.
 *
 * Algoritma signaling-server/RateLimiter.kt'tekiyle ayni (sliding window
 * sorted set). Cross-module dep yerine local impl.
 */
object RateLimitGuard {

    private const val GLOBAL_LIMIT_PER_MINUTE = 1000

    data class Result(val allowed: Boolean, val reason: String? = null, val retryAfterSeconds: Long = 0)

    fun check(client: AuthenticatedClient, recipientRef: String, cost: Int = 1): Result {
        if (cost !in 1..256) return Result(false, "invalid_cost")
        // 1. Per-client per-hour
        val perClientResult = window(
            key = privateKey("client", client.clientId),
            windowSeconds = 3600,
            maxRequests = client.ratePerHour,
            cost = cost
        )
        if (!perClientResult.allowed) {
            return Result(false, "client_per_hour", perClientResult.retryAfterSeconds)
        }

        // 2. Per-recipient per-day
        val perRecipientResult = window(
            key = privateKey("recipient", "${client.clientId}\u0000$recipientRef"),
            windowSeconds = 86400,
            maxRequests = client.perRecipientPerDay,
            cost = cost
        )
        if (!perRecipientResult.allowed) {
            return Result(false, "recipient_per_day", perRecipientResult.retryAfterSeconds)
        }

        // 3. Global per-minute brake
        val globalResult = window(
            key = "bot_rl:global",
            windowSeconds = 60,
            maxRequests = GLOBAL_LIMIT_PER_MINUTE,
            cost = cost
        )
        if (!globalResult.allowed) {
            return Result(false, "global", globalResult.retryAfterSeconds)
        }

        return Result(true)
    }

    private fun window(key: String, windowSeconds: Int, maxRequests: Int, cost: Int): Result {
        return BotRedisManager.use { jedis ->
            val now = System.currentTimeMillis()
            val windowStart = now - windowSeconds * 1000L

            jedis.zremrangeByScore(key, "-inf", windowStart.toString())
            val count = jedis.zcard(key)
            if (count + cost > maxRequests) {
                // Retry-after = en eski entry'nin window'dan çıkmasına kalan saniye
                val oldest = jedis.zrangeWithScores(key, 0, 0).firstOrNull()?.score?.toLong() ?: now
                val retryAfter = (oldest + windowSeconds * 1000L - now) / 1000L
                return@use Result(false, retryAfterSeconds = retryAfter.coerceAtLeast(1))
            }
            repeat(cost) { index ->
                val member = "${now}-${index}-${UUID.randomUUID()}"
                jedis.zadd(key, now.toDouble(), member, ZAddParams.zAddParams())
            }
            jedis.expire(key, windowSeconds + 60L)  // TTL biraz fazlasi — auto cleanup
            Result(true)
        }
    }

    private fun privateKey(scope: String, value: String): String =
        "bot_rl_v2:${BotQueuePrivacy.blindIndex("rate-$scope", value)}"
}
