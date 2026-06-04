package com.securechat.botapi.auth

import com.securechat.botapi.db.ApiClientRepository
import com.securechat.botapi.db.BotRedisManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import redis.clients.jedis.JedisPubSub
import java.util.concurrent.ConcurrentHashMap

private val log = LoggerFactory.getLogger("ClientKeyCache")

/**
 * kid → AuthenticatedClient cache'i.
 *
 * Cache miss → ApiClientRepository.findActiveByKid → DB.
 * Cache invalidate: Redis pub/sub channel "bot_api:client_invalidate"
 * uzerinden kid (veya "*" tum cache flush) yayinlanir; admin endpoint'leri
 * revoke/rotate sonrasi yayinlar. Coklu instance senaryosunda da tutarlilik.
 *
 * Thread-safe: ConcurrentHashMap + immutable AuthenticatedClient.
 */
object ClientKeyCache {

    private const val INVALIDATE_CHANNEL = "bot_api:client_invalidate"

    private val cache = ConcurrentHashMap<String, AuthenticatedClient>()
    private val scope = CoroutineScope(Dispatchers.IO)
    private var subscriberJob: Job? = null

    /** Pub/sub subscriber'i baslat. Bot-api boyunca canli kalmali. */
    fun startInvalidationListener() {
        if (subscriberJob != null) return
        subscriberJob = scope.launch {
            while (isActive()) {
                try {
                    val dedicated = BotRedisManager.borrowDedicated()
                    try {
                        dedicated.subscribe(object : JedisPubSub() {
                            override fun onMessage(channel: String, message: String) {
                                handleInvalidate(message)
                            }
                        }, INVALIDATE_CHANNEL)
                    } finally {
                        dedicated.close()
                    }
                } catch (e: Exception) {
                    log.warn("[ClientCache] pub/sub baglanti hatasi — 1sn icinde yeniden denenecek: {}", e.message)
                    Thread.sleep(1000)
                }
            }
        }
        log.info("[ClientCache] Invalidation listener baslatildi (channel={})", INVALIDATE_CHANNEL)
    }

    private fun isActive(): Boolean = subscriberJob?.isActive == true

    fun stop() {
        subscriberJob?.cancel()
        subscriberJob = null
    }

    /**
     * Cache miss durumunda DB lookup yapar; sonucu cache'ler.
     * Revoke/expired ise null doner.
     */
    fun get(kid: String): AuthenticatedClient? {
        cache[kid]?.let { return it }
        val fromDb = ApiClientRepository.findActiveByKid(kid) ?: return null
        cache[kid] = fromDb
        return fromDb
    }

    /** Belirli kid'i cache'ten dusurur. Admin endpoint'leri broadcast oncesi cagirir. */
    fun invalidate(kid: String) {
        cache.remove(kid)
    }

    /** Tum cache'i temizler — emergency cases icin. */
    fun invalidateAll() {
        cache.clear()
        log.warn("[ClientCache] Tum cache flush edildi")
    }

    /** Diger instance'lara da invalidate sinyali gonderir. */
    fun broadcastInvalidate(kid: String) {
        invalidate(kid)
        try {
            BotRedisManager.use { it.publish(INVALIDATE_CHANNEL, kid) }
        } catch (e: Exception) {
            log.warn("[ClientCache] Pub/sub yayini basarisiz (kid={}): {}", kid, e.message)
        }
    }

    private fun handleInvalidate(message: String) {
        if (message == "*") {
            invalidateAll()
        } else {
            cache.remove(message)
            log.info("[ClientCache] Invalidate alindi: kid={}", message)
        }
    }
}
