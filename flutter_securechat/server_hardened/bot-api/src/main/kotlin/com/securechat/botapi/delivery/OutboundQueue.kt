package com.securechat.botapi.delivery

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("OutboundQueue")

/**
 * WS bağlantısı down iken giden mesajlar Redis list'inde tutulur,
 * reconnect olduğunda sırayla drain edilir.
 *
 * Redis key keyed blind index'tir; deger server AEAD zarfindadir. LPUSH ile
 * yazilir, RPOP ile okunur (FIFO).
 *
 * Garanti: 202 Accepted dondukten sonra SendPipeline mesaji ya WS'ye iletmeli
 * ya da bu queue'ya yazmali. Crash mid-write durumunda idempotency kaydi
 * bounded privacy TTL boyunca retry'nin duplicate gonderimini engeller.
 */
object OutboundQueue {

    private const val MAX_MESSAGES = 1_000L

    private fun key(botUserId: String) = BotQueuePrivacy.key(botUserId)

    /** WS down — sirada bekle. */
    fun enqueue(botUserId: String, envelopeJson: String) {
        BotRedisManager.use { jedis ->
            val key = key(botUserId)
            jedis.lpush(key, BotQueuePrivacy.seal(botUserId, envelopeJson))
            jedis.ltrim(key, 0, MAX_MESSAGES - 1)
            jedis.expire(key, BotApiConfig.outboundQueueTtlSeconds)
        }
    }

    /** Reconnect sonrasi sirayla drain et — null donene kadar. */
    fun pollNext(botUserId: String): String? {
        repeat(MAX_MESSAGES.toInt()) {
            val stored = BotRedisManager.use { jedis -> jedis.rpop(key(botUserId)) }
                ?: return null
            try {
                return BotQueuePrivacy.open(botUserId, stored)
            } catch (_: Exception) {
                log.warn("[OutboundQueue] Gecersiz veya legacy queue zarfi atildi")
            }
        }
        return null
    }

    fun size(botUserId: String): Long =
        BotRedisManager.use { jedis -> jedis.llen(key(botUserId)) }

    /** Drain yardimcisi: tum bekleyenleri callback'e iletir. */
    fun drainAll(botUserId: String, handler: (String) -> Boolean) {
        var processed = 0
        while (true) {
            val item = pollNext(botUserId) ?: break
            val ok = try { handler(item) } catch (e: Exception) {
                log.warn("[OutboundQueue] Handler hatasi — item geri yaziliyor: {}", e.javaClass.simpleName)
                enqueue(botUserId, item)  // basa al
                break
            }
            if (!ok) {
                log.warn("[OutboundQueue] Handler false — item geri yaziliyor, drain durdu")
                enqueue(botUserId, item)
                break
            }
            processed++
        }
        if (processed > 0) log.info("[OutboundQueue] {} mesaj drain edildi", processed)
    }
}
