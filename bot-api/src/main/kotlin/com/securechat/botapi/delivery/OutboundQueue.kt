package com.securechat.botapi.delivery

import com.securechat.botapi.db.BotRedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("OutboundQueue")

/**
 * WS bağlantısı down iken giden mesajlar Redis list'inde tutulur,
 * reconnect olduğunda sırayla drain edilir.
 *
 * Redis key: "bot_outbound:<botUserId>" — LPUSH ile yazılır, RPOP ile okunur (FIFO).
 *
 * Garanti: 202 Accepted dondukten sonra SendPipeline mesaji ya WS'ye iletmeli
 * ya da bu queue'ya yazmali. Crash mid-write durumunda idempotency key
 * 24 saat boyunca PENDING kalir; script ayni key ile retry edebilir.
 */
object OutboundQueue {

    private fun key(botUserId: String) = "bot_outbound:$botUserId"

    /** WS down — sirada bekle. */
    fun enqueue(botUserId: String, envelopeJson: String) {
        BotRedisManager.use { jedis ->
            jedis.lpush(key(botUserId), envelopeJson)
        }
    }

    /** Reconnect sonrasi sirayla drain et — null donene kadar. */
    fun pollNext(botUserId: String): String? =
        BotRedisManager.use { jedis -> jedis.rpop(key(botUserId)) }

    fun size(botUserId: String): Long =
        BotRedisManager.use { jedis -> jedis.llen(key(botUserId)) }

    /** Drain yardimcisi: tum bekleyenleri callback'e iletir. */
    fun drainAll(botUserId: String, handler: (String) -> Boolean) {
        var processed = 0
        while (true) {
            val item = pollNext(botUserId) ?: break
            val ok = try { handler(item) } catch (e: Exception) {
                log.warn("[OutboundQueue] Handler hatasi — item geri yaziliyor: {}", e.message)
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
