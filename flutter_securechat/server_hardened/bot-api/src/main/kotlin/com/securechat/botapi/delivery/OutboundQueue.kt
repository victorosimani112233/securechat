package com.securechat.botapi.delivery

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.slf4j.LoggerFactory
import java.util.UUID

private val log = LoggerFactory.getLogger("OutboundQueue")

/**
 * WS baglantisi down iken giden mesajlarin kuyrugu.
 *
 * Onceki tasarimda uc ayri sorun vardi:
 *
 *  1. `RPOP` mesaji kuyruktan hemen siliyordu. Process veya soket bu noktada
 *     olurse mesaj kayboluyordu — oysa API zaten 202 donmustu.
 *  2. Basarisiz teslimde mesaj `LPUSH` ile geri yaziliyordu. Kuyruk
 *     LPUSH/RPOP ile FIFO oldugundan bu, mesaji sirasinin **sonuna** atiyordu.
 *  3. `WebSocket.send()==true` teslim sayiliyordu; oysa o yalniz "soket
 *     tamponuna kondu" demektir.
 *
 * Simdi mesaj kuyruktan cikarken **in-flight** kaydina gecer ve ancak
 * signaling'den gelen ACK ile silinir. Gorunurluk suresi dolan kayitlar
 * kuyrugun basina geri alinir; teslim edilmemis mesaj kaybolmaz.
 */
object OutboundQueue {

    private const val MAX_MESSAGES = 1_000L

    /** ACK gelmezse mesajin yeniden kuyruga alinacagi sure. */
    private const val VISIBILITY_TIMEOUT_MILLIS = 30_000L

    private fun key(botUserId: String) = BotQueuePrivacy.key(botUserId)
    private fun inflightKey(botUserId: String) = "${key(botUserId)}:inflight"
    private fun inflightIndexKey(botUserId: String) = "${key(botUserId)}:inflight_at"
    private val json = Json { ignoreUnknownKeys = true }

    /** Kapasite doluyken eski bir 202 mesajini dusurmek yerine yeni istegi reddeder. */
    private val ENQUEUE_SCRIPT = """
        local total = redis.call('LLEN', KEYS[1]) + redis.call('HLEN', KEYS[2])
        if total >= tonumber(ARGV[2]) then
          return 0
        end
        redis.call('LPUSH', KEYS[1], ARGV[1])
        redis.call('EXPIRE', KEYS[1], ARGV[3])
        return 1
    """.trimIndent()

    /**
     * Mesaji kuyruktan alip in-flight'a tasir. Iki adim tek scriptte oldugu
     * icin arada kaybolamaz.
     *
     * ARGV: checkoutToken, now, ttlSeconds
     */
    private val CHECKOUT_SCRIPT = """
        local sealed = redis.call('RPOP', KEYS[1])
        if not sealed then
          return nil
        end
        local score = tonumber(ARGV[2])
        local latest = redis.call('ZREVRANGE', KEYS[3], 0, 0, 'WITHSCORES')
        if latest[2] and tonumber(latest[2]) >= score then
          score = tonumber(latest[2]) + 1
        end
        redis.call('HSET', KEYS[2], ARGV[1], sealed)
        redis.call('ZADD', KEYS[3], score, ARGV[1])
        redis.call('EXPIRE', KEYS[2], ARGV[3])
        redis.call('EXPIRE', KEYS[3], ARGV[3])
        return sealed
    """.trimIndent()

    /**
     * Gecici checkout tokenini zarf icindeki gercek messageId ile tek Redis
     * adiminda degistirir. Process script oncesi durursa gecici kayit visibility
     * timeout ile geri alinir; script sirasinda durursa Redis atomikligi korur.
     *
     * Donus: 1=rekey, 2=ayni messageId zaten in-flight, 0=token bulunamadi.
     */
    private val REKEY_SCRIPT = """
        local sealed = redis.call('HGET', KEYS[1], ARGV[1])
        if not sealed then
          return 0
        end
        local score = redis.call('ZSCORE', KEYS[2], ARGV[1])
        if not score then
          return 0
        end
        if redis.call('HEXISTS', KEYS[1], ARGV[2]) == 1 then
          redis.call('HDEL', KEYS[1], ARGV[1])
          redis.call('ZREM', KEYS[2], ARGV[1])
          return 2
        end
        redis.call('HDEL', KEYS[1], ARGV[1])
        redis.call('ZREM', KEYS[2], ARGV[1])
        redis.call('HSET', KEYS[1], ARGV[2], sealed)
        redis.call('ZADD', KEYS[2], score, ARGV[2])
        redis.call('EXPIRE', KEYS[1], ARGV[3])
        redis.call('EXPIRE', KEYS[2], ARGV[3])
        return 1
    """.trimIndent()

    /** Basarisiz socket yazimini in-flight'tan FIFO basina atomik geri alir. */
    private val REQUEUE_SCRIPT = """
        local sealed = redis.call('HGET', KEYS[2], ARGV[1])
        if not sealed then
          return 0
        end
        redis.call('RPUSH', KEYS[1], sealed)
        redis.call('HDEL', KEYS[2], ARGV[1])
        redis.call('ZREM', KEYS[3], ARGV[1])
        redis.call('EXPIRE', KEYS[1], ARGV[2])
        return 1
    """.trimIndent()

    /**
     * Gorunurluk suresi dolmus in-flight kayitlarini kuyrugun **basina**
     * geri alir; `RPUSH` sirayi korur, `LPUSH` mesaji sona atardi.
     *
     * ARGV: threshold, ttlSeconds
     */
    private val RECLAIM_SCRIPT = """
        local expired = redis.call('ZRANGEBYSCORE', KEYS[3], '-inf', ARGV[1])
        local reclaimed = 0
        for i = #expired, 1, -1 do
          local sealed = redis.call('HGET', KEYS[2], expired[i])
          if sealed then
            redis.call('RPUSH', KEYS[1], sealed)
            redis.call('HDEL', KEYS[2], expired[i])
            reclaimed = reclaimed + 1
          end
          redis.call('ZREM', KEYS[3], expired[i])
        end
        if reclaimed > 0 then
          redis.call('EXPIRE', KEYS[1], ARGV[2])
        end
        return reclaimed
    """.trimIndent()

    /** WS down — sirada bekle. */
    fun enqueue(botUserId: String, envelopeJson: String) {
        val accepted = BotRedisManager.use { jedis ->
            jedis.eval(
                ENQUEUE_SCRIPT,
                listOf(key(botUserId), inflightKey(botUserId)),
                listOf(
                    BotQueuePrivacy.seal(botUserId, envelopeJson),
                    MAX_MESSAGES.toString(),
                    BotApiConfig.outboundQueueTtlSeconds.toString(),
                ),
            ) == 1L
        }
        check(accepted) { "Outbound queue capacity reached" }
    }

    class Checkout(val messageId: String, val envelopeJson: String)

    /**
     * Siradaki mesaji in-flight'a alarak doner.
     */
    fun checkoutNext(botUserId: String): Checkout? {
        repeat(MAX_MESSAGES.toInt()) {
            val checkoutToken = UUID.randomUUID().toString()
            val sealed = BotRedisManager.use { jedis ->
                jedis.eval(
                    CHECKOUT_SCRIPT,
                    listOf(key(botUserId), inflightKey(botUserId), inflightIndexKey(botUserId)),
                    listOf(
                        checkoutToken,
                        System.currentTimeMillis().toString(),
                        BotApiConfig.outboundQueueTtlSeconds.toString(),
                    ),
                )
            } ?: return null
            val envelope = try {
                BotQueuePrivacy.open(botUserId, sealed.toString())
            } catch (_: Exception) {
                log.warn("[OutboundQueue] Gecersiz veya legacy queue zarfi atildi")
                acknowledge(botUserId, checkoutToken)
                return@repeat
            }
            val messageId = extractMessageId(envelope)
            if (messageId == null) {
                log.warn("[OutboundQueue] messageId okunamadi — zarf atildi")
                acknowledge(botUserId, checkoutToken)
                return@repeat
            }
            when (rekeyInflight(botUserId, checkoutToken, messageId)) {
                1L -> return Checkout(messageId, envelope)
                2L -> {
                    log.warn("[OutboundQueue] Duplicate in-flight messageId atildi")
                    return@repeat
                }
                else -> throw IllegalStateException("In-flight checkout kaydi kayboldu")
            }
        }
        return null
    }

    /** ACK geldi — in-flight kaydi silinir. */
    fun acknowledge(botUserId: String, messageId: String) {
        BotRedisManager.use { jedis ->
            jedis.hdel(inflightKey(botUserId), messageId)
            jedis.zrem(inflightIndexKey(botUserId), messageId)
        }
    }

    /** Gorunurluk suresi dolmus kayitlari kuyruga geri alir. */
    fun reclaimExpired(botUserId: String): Int {
        val threshold = System.currentTimeMillis() - VISIBILITY_TIMEOUT_MILLIS
        val reclaimed = BotRedisManager.use { jedis ->
            jedis.eval(
                RECLAIM_SCRIPT,
                listOf(key(botUserId), inflightKey(botUserId), inflightIndexKey(botUserId)),
                listOf(threshold.toString(), BotApiConfig.outboundQueueTtlSeconds.toString()),
            ) as? Long ?: 0L
        }
        if (reclaimed > 0) {
            log.warn("[OutboundQueue] {} teslim edilmemis mesaj kuyruga geri alindi", reclaimed)
        }
        return reclaimed.toInt()
    }

    fun size(botUserId: String): Long =
        BotRedisManager.use { jedis -> jedis.llen(key(botUserId)) }

    fun inflightSize(botUserId: String): Long =
        BotRedisManager.use { jedis -> jedis.hlen(inflightKey(botUserId)) }

    /**
     * Bekleyen mesajlari sirayla iletir.
     *
     * Handler yalniz "gonderim denendi" bilgisini doner; mesaj in-flight'ta
     * kalir ve ACK gelene ya da gorunurluk suresi dolana kadar silinmez.
     */
    fun drainAll(botUserId: String, handler: (String) -> Boolean) {
        reclaimExpired(botUserId)
        var processed = 0
        while (true) {
            val checkout = checkoutNext(botUserId) ?: break
            val ok = try {
                handler(checkout.envelopeJson)
            } catch (e: Exception) {
                log.warn("[OutboundQueue] Handler hatasi: {}", e.javaClass.simpleName)
                false
            }
            if (!ok) {
                // Gonderilemedi: hemen kuyruga geri, sira korunur.
                check(requeueInflight(botUserId, checkout.messageId)) {
                    "In-flight mesaj atomik olarak kuyruga alinamadi"
                }
                log.warn("[OutboundQueue] Gonderim basarisiz — drain durdu")
                break
            }
            processed++
        }
        if (processed > 0) log.info("[OutboundQueue] {} mesaj iletildi (ACK bekleniyor)", processed)
    }

    private fun rekeyInflight(
        botUserId: String,
        checkoutToken: String,
        messageId: String,
    ): Long = BotRedisManager.use { jedis ->
        jedis.eval(
            REKEY_SCRIPT,
            listOf(inflightKey(botUserId), inflightIndexKey(botUserId)),
            listOf(
                checkoutToken,
                messageId,
                BotApiConfig.outboundQueueTtlSeconds.toString(),
            ),
        ) as? Long ?: 0L
    }

    private fun requeueInflight(botUserId: String, messageId: String): Boolean =
        BotRedisManager.use { jedis ->
            jedis.eval(
                REQUEUE_SCRIPT,
                listOf(key(botUserId), inflightKey(botUserId), inflightIndexKey(botUserId)),
                listOf(messageId, BotApiConfig.outboundQueueTtlSeconds.toString()),
            ) == 1L
        }

    private fun extractMessageId(envelopeJson: String): String? =
        runCatching {
            json.parseToJsonElement(envelopeJson)
                .jsonObject["messageId"]
                ?.jsonPrimitive
                ?.contentOrNull
        }
            .getOrNull()
            ?.takeIf { it.isNotBlank() && it.length <= 128 }
}
