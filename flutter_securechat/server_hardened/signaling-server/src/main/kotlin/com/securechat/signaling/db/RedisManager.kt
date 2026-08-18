package com.securechat.signaling.db

import com.securechat.signaling.SecretSource
import redis.clients.jedis.JedisPool
import redis.clients.jedis.JedisPoolConfig
import redis.clients.jedis.Jedis
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("RedisManager")

/**
 * Redis baglanti havuzu (Jedis).
 * Offline mesaj kuyrugu ve rate limiting icin kullanilir.
 */
object RedisManager {

    private lateinit var pool: JedisPool

    fun init(
        host: String = System.getenv("REDIS_HOST") ?: "localhost",
        port: Int = System.getenv("REDIS_PORT")?.toIntOrNull() ?: 6379,
        password: String? = SecretSource.optional("REDIS_PASSWORD")
    ) {
        val config = JedisPoolConfig().apply {
            maxTotal = 50
            maxIdle = 20
            minIdle = 5
            testOnBorrow = true
            testOnReturn = true
        }
        pool = if (password.isNullOrBlank()) {
            JedisPool(config, host, port)
        } else {
            JedisPool(config, host, port, 5000, password)
        }
        log.info("[Redis] Baglanti havuzu baslatildi ($host:$port)")
    }

    fun <T> use(block: (Jedis) -> T): T {
        return pool.resource.use { jedis -> block(jedis) }
    }

    fun isHealthy(): Boolean {
        return try {
            use { it.ping() == "PONG" }
        } catch (_: Exception) {
            false
        }
    }

    /** Fails closed unless Redis is a RAM-only transient store. */
    fun requireMemoryOnly() {
        val configuration = use { jedis ->
            // Lack of CONFIG permission is intentionally fatal: production
            // cannot claim a no-disk guarantee it cannot verify.
            jedis.configGet("appendonly", "save")
        }
        RedisEphemeralPolicy.requireMemoryOnly(configuration)
        log.info("[Redis] RDB/AOF kapali; transient state RAM-only")
    }

    fun close() {
        if (::pool.isInitialized) {
            pool.close()
            log.info("[Redis] Baglanti havuzu kapatildi")
        }
    }
}
