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

    /**
     * Sliding window — tek atomik adim.
     *
     * Onceki uygulama `ZREMRANGEBYSCORE -> ZCARD -> ZADD` seklinde uc ayri
     * gidis-donusteydi: es zamanli iki istek de "sinir altinda" okuyup
     * ikisi de gecebiliyordu. Signaling tarafinda ayni hata (P1-02) Lua ile
     * kapatilmisti; bot tarafi geride kalmisti.
     *
     * Maliyet member'in icine yazilir, boylece grup fanout'unun N birimi
     * tek bir girdi olarak degil gercek agirligiyla sayilir.
     *
     * ARGV: windowStart, maxRequests, score, ttlSeconds, cost, member
     * Donus: izin verildiyse 1, aksi halde en eski girdinin skoru (negatif
     * degil) — retry-after bundan hesaplanir.
     */
    private val SLIDING_WINDOW_SCRIPT = """
        redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1])
        local entries = redis.call('ZRANGEBYSCORE', KEYS[1], ARGV[1], '+inf')
        local used = 0
        for i = 1, #entries do
          local separator = string.find(entries[i], ':')
          if separator then
            used = used + tonumber(string.sub(entries[i], 1, separator - 1))
          end
        end
        local cost = tonumber(ARGV[5])
        if used + cost > tonumber(ARGV[2]) then
          local oldest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
          if oldest[2] then
            return {0, oldest[2]}
          end
          return {0, ARGV[3]}
        end
        redis.call('ZADD', KEYS[1], ARGV[3], ARGV[6])
        redis.call('EXPIRE', KEYS[1], ARGV[4])
        return {1, '0'}
    """.trimIndent()

    private val memberRandom = java.security.SecureRandom()

    private fun uniqueSuffix(): String {
        val bytes = ByteArray(9)
        memberRandom.nextBytes(bytes)
        return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    internal fun window(key: String, windowSeconds: Int, maxRequests: Int, cost: Int): Result {
        if (maxRequests <= 0) return Result(false, retryAfterSeconds = windowSeconds.toLong())
        val now = System.currentTimeMillis()
        val windowStart = now - windowSeconds * 1000L
        // Ayni milisaniyedeki istekler ayni member'a dusmesin diye nonce.
        val member = "$cost:$now:${uniqueSuffix()}"
        return BotRedisManager.use { jedis ->
            @Suppress("UNCHECKED_CAST")
            val reply = jedis.eval(
                SLIDING_WINDOW_SCRIPT,
                listOf(key),
                listOf(
                    windowStart.toString(),
                    maxRequests.toString(),
                    now.toString(),
                    (windowSeconds + 60L).toString(),
                    cost.toString(),
                    member,
                ),
            ) as List<Any?>
            val allowed = (reply.getOrNull(0) as? Long) == 1L
            if (allowed) {
                Result(true)
            } else {
                val oldest = (reply.getOrNull(1) as? String)?.toDoubleOrNull()?.toLong() ?: now
                val retryAfter = (oldest + windowSeconds * 1000L - now) / 1000L
                Result(false, retryAfterSeconds = retryAfter.coerceAtLeast(1))
            }
        } ?: Result(false, "rate_limit_unavailable", windowSeconds.toLong())
    }

    private fun privateKey(scope: String, value: String): String =
        "bot_rl_v2:${BotQueuePrivacy.blindIndex("rate-$scope", value)}"
}
