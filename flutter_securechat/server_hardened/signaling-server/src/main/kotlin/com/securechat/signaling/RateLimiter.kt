package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("RateLimiter")

/**
 * Redis tabanli sliding window rate limiter.
 * Key: ratelimit_v2:{HMAC(endpoint, identifier)}. IP/user identifiers are not
 * persisted as Redis key material.
 */
object RateLimiter {

    data class RateLimit(val maxRequests: Int, val windowSeconds: Long)

    // Endpoint bazli limitler
    val LIMITS = mapOf(
        "directory_evaluate" to RateLimit(32, 86_400), // en fazla 8192 aday/gun/account
        "directory_snapshot" to RateLimit(12, 3_600),  // snapshot polling siniri
        "directory_self_update" to RateLimit(4, 86_400), // own-index migration/rotation
        "users_register" to RateLimit(5, 3600),      // 5 req/saat per IP
        "ice_config" to RateLimit(30, 3600),          // 30 req/saat per userId
        "ws_message" to RateLimit(50, 1),             // 50 msg/sn per userId (DoS koruma)
        "ws_connect" to RateLimit(10, 1),             // 10 yeni WS baglanti/sn per IP
        "file_chunk_bytes" to RateLimit(5_242_880, 60), // 5 MB/dk per userId (bytes window)
        "otp_request" to RateLimit(5, 600),           // 5 req/10dk per IP (OTP istegi)
        "otp_verify" to RateLimit(20, 600),        // 20 req/10dk per IP (brute force korumasi zaten OTP servisinde)
        "presence_subscribe" to RateLimit(120, 60)
    )

    /**
     * Sliding window kontrolu tek atomik adimda.
     *
     * Onceki uygulama `ZREMRANGEBYSCORE -> ZCARD -> ZADD` seklinde uc ayri
     * gidis-donusti: es zamanli iki istek de "limit altinda" okuyup ikisi de
     * gecebiliyordu. Ayrica member olarak yalniz timestamp yaziliyordu, bu
     * yuzden ayni milisaniyedeki istekler ayni member'a denk gelip tek istek
     * gibi sayiliyordu.
     *
     * Script pencereyi temizler, kullanilan quota'yi toplar, sinir asilmazsa
     * benzersiz bir member ekler ve TTL'i tazeler. Karar ile yazma arasina
     * baska bir istemci giremez.
     *
     * ARGV: windowStart, maxCost, score, ttlSeconds, cost, member
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
          return 0
        end
        redis.call('ZADD', KEYS[1], ARGV[3], ARGV[6])
        redis.call('EXPIRE', KEYS[1], ARGV[4])
        return 1
    """.trimIndent()

    private val memberRandom = java.security.SecureRandom()

    /**
     * Byte-tabanli rate limit — file transfer chunk'larinda kullanilir.
     * Her cagride byteSize kadar quota dusurur; pencerede toplam asarsa false.
     */
    fun allowBytes(endpoint: String, identifier: String, byteSize: Int): Boolean =
        consume(endpoint, identifier, byteSize.toLong())

    /**
     * Rate limit kontrolu yapar.
     * @return true = izin verildi, false = limit asildi
     */
    fun allow(endpoint: String, identifier: String): Boolean =
        consume(endpoint, identifier, cost = 1L)

    private fun consume(endpoint: String, identifier: String, cost: Long): Boolean {
        val limit = LIMITS[endpoint] ?: return true
        val key = ServerPrivacy.rateLimitKey(endpoint, identifier)
        val now = System.currentTimeMillis()
        val windowStart = now - (limit.windowSeconds * 1000)
        // Ayni milisaniyedeki istekler ayni member'a dusmesin diye nonce.
        val member = "$cost:$now:${uniqueSuffix()}"

        return try {
            RedisManager.use { jedis ->
                val result = jedis.eval(
                    SLIDING_WINDOW_SCRIPT,
                    listOf(key),
                    listOf(
                        windowStart.toString(),
                        limit.maxRequests.toString(),
                        now.toString(),
                        (limit.windowSeconds + 1).toString(),
                        cost.toString(),
                        member,
                    ),
                )
                (result as? Long) == 1L
            }
        } catch (e: Exception) {
            // GUVENLIK: Redis down ise FAIL-CLOSED — istek reddedilir.
            // Onceki davranis (true donmek) DoS acigi yaratiyordu:
            // saldirgan Redis'i devre disi birakirsa rate-limit kapanir.
            log.error("[!] RateLimiter Redis hatasi — fail-closed: ${e.javaClass.simpleName}")
            false
        }
    }

    private fun uniqueSuffix(): String {
        val bytes = ByteArray(8)
        memberRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Limit asiladiginda kalan sure (saniye).
     */
    fun retryAfter(endpoint: String, identifier: String): Long {
        val limit = LIMITS[endpoint] ?: return 0
        val key = ServerPrivacy.rateLimitKey(endpoint, identifier)
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
