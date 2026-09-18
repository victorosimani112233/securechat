package com.securechat.botapi.db

import com.securechat.botapi.BotApiConfig
import org.slf4j.LoggerFactory
import redis.clients.jedis.Jedis
import redis.clients.jedis.JedisPool
import redis.clients.jedis.JedisPoolConfig

private val log = LoggerFactory.getLogger("BotRedisManager")

/**
 * Redis baglanti havuzu (Jedis), bot-api icin.
 *
 * Kullanim alanlari:
 *  - Replay nonce store (bot_jti:<jti>)
 *  - Rate limit sliding window
 *  - Idempotency cache
 *  - Outbound queue (WS reconnect drain)
 *  - Emergency stop flag
 *  - Client cache invalidate pub/sub
 */
object BotRedisManager {

    private lateinit var pool: JedisPool

    fun init() {
        val config = JedisPoolConfig().apply {
            maxTotal = 30
            maxIdle = 10
            minIdle = 2
            testOnBorrow = true
            testOnReturn = true
        }
        pool = if (BotApiConfig.redisPassword.isNullOrBlank()) {
            JedisPool(config, BotApiConfig.redisHost, BotApiConfig.redisPort)
        } else {
            JedisPool(config, BotApiConfig.redisHost, BotApiConfig.redisPort, 5000, BotApiConfig.redisPassword)
        }
        log.info("[BotRedis] Baglanti havuzu acildi: {}:{}", BotApiConfig.redisHost, BotApiConfig.redisPort)
    }

    fun <T> use(block: (Jedis) -> T): T = pool.resource.use { jedis -> block(jedis) }

    /** Pub/sub subscriber gibi long-lived kullanim icin ayri bir Jedis. Kapatma sorumluluğu cağırıcıda. */
    fun borrowDedicated(): Jedis = pool.resource

    fun isHealthy(): Boolean = try {
        use { it.ping() == "PONG" }
    } catch (_: Exception) { false }

    /** Fails closed unless transient bot queues can remain RAM-only. */
    fun requireMemoryOnly() {
        val configuration = use { jedis ->
            jedis.configGet("appendonly", "save")
        }
        RedisEphemeralPolicy.requireMemoryOnly(configuration)
        log.info("[BotRedis] RDB/AOF kapali; transient state RAM-only")
    }

    fun close() {
        if (::pool.isInitialized) {
            pool.close()
            log.info("[BotRedis] Baglanti havuzu kapatildi")
        }
    }
}
