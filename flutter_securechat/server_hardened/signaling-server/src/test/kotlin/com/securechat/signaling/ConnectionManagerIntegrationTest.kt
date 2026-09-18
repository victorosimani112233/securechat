package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName

/**
 * Offline kuyruk ve aktif cagri kayitlari, gercek Redis ile.
 *
 * Kuyruk sinirsiz buyurse tek bir cevrimdisi hesap Redis'i doldurabilir;
 * cagri kayitlari temizlenmezse kopan bir baglantidan sonra "hayalet" bir
 * arama ayakta kalir ve kullanici yeni arama alamaz.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ConnectionManagerIntegrationTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private lateinit var manager: ConnectionManager

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; kuyruk testi atlandi")
        redis.start()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        ServerPrivacy.initialize()
        manager = ConnectionManager()
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { RedisManager.close() }
        redis.stop()
    }

    private fun queueSize(bucket: String, userId: String): Long =
        RedisManager.use { jedis -> jedis.zcard(ServerPrivacy.queueKey(bucket, userId)) } ?: 0L

    private fun reliablePayloads(userId: String): List<String> =
        RedisManager.use { jedis ->
            val tokens = jedis.zrange(ServerPrivacy.queueKey("delivery", userId), 0, -1)
                ?: emptySet()
            if (tokens.isEmpty()) emptyList() else jedis.mget(
                *tokens.map {
                    ServerPrivacy.queueItemKey("delivery", userId, it)
                }.toTypedArray()
            ).filterNotNull()
        }

    private fun envelope(marker: String, size: Int = 64) =
        """{"type":"encrypted_message","messageId":"$marker","ciphertext":"${"A".repeat(size)}"}"""

    // ---------------- Offline kuyruk ----------------

    @Test
    fun `a message for an offline recipient is queued`() = runBlocking {
        val user = UUID.randomUUID().toString()

        manager.routeMessage(user, envelope("m-1"))

        assertEquals(1L, queueSize("delivery", user))
    }

    @Test
    fun `the queued envelope is sealed`() = runBlocking {
        val user = UUID.randomUUID().toString()
        val marker = "MARKER-${UUID.randomUUID()}"

        manager.routeMessage(user, envelope(marker))

        val stored = reliablePayloads(user)
        assertTrue(stored.isNotEmpty())
        // Sunucu depolama katmani mesaji ayrica sarar; ne alici kimligi ne
        // de govde duz durur.
        for (entry in stored) {
            assertFalse(entry.contains(marker), entry.take(120))
            assertFalse(entry.contains(user), entry.take(120))
        }
    }

    @Test
    fun `the queue is bounded by message count`() = runBlocking {
        val user = UUID.randomUUID().toString()

        repeat(1_005) { index -> manager.routeMessage(user, envelope("bulk-$index", size = 8)) }

        // Sinirsiz kuyruk tek bir cevrimdisi hesabin Redis'i doldurmasina
        // izin verirdi.
        assertTrue(queueSize("delivery", user) <= 1_000L, "kuyruk boyutu: ${queueSize("delivery", user)}")
    }

    @Test
    fun `the queue carries a bounded ttl`() = runBlocking {
        val user = UUID.randomUUID().toString()
        manager.routeMessage(user, envelope("ttl"))

        val ttl = RedisManager.use { jedis ->
            jedis.ttl(ServerPrivacy.queueKey("delivery", user))
        } ?: -1L

        assertTrue(ttl > 0, "TTL yok")
        assertTrue(ttl <= ServerPrivacy.config.offlineQueueTtlSeconds, "TTL: $ttl")
    }

    @Test
    fun `a newer delivery never extends an older ciphertext ttl`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        manager.routeMessage(recipient, envelope("first"))
        val indexKey = ServerPrivacy.queueKey("delivery", recipient)
        val firstToken = RedisManager.use { jedis ->
            jedis.zrange(indexKey, 0, 0).single()
        }
        val firstItemKey = ServerPrivacy.queueItemKey("delivery", recipient, firstToken)
        val initialTtl = RedisManager.use { jedis -> jedis.ttl(firstItemKey) }

        Thread.sleep(1_100)
        manager.routeMessage(recipient, envelope("second"))

        val remainingTtl = RedisManager.use { jedis -> jedis.ttl(firstItemKey) }
        val secondToken = RedisManager.use { jedis ->
            jedis.zrange(indexKey, -1, -1).single()
        }
        val secondTtl = RedisManager.use { jedis ->
            jedis.ttl(ServerPrivacy.queueItemKey("delivery", recipient, secondToken))
        }
        assertTrue(remainingTtl < initialTtl, "ilk ciphertext TTL'i yenilendi")
        assertTrue(secondTtl > remainingTtl, "yeni ciphertext bagimsiz TTL almadi")
    }

    @Test
    fun `file transfers use a separate bucket with its own ttl`() = runBlocking {
        val user = UUID.randomUUID().toString()

        manager.routeMessage(
            user,
            """{"type":"file_transfer","messageId":"f-1","ciphertext":"AAAA"}""",
        )

        assertEquals(1L, queueSize("file", user))
        assertEquals(0L, queueSize("message", user))
        assertEquals(0L, queueSize("delivery", user))
        val ttl = RedisManager.use { jedis -> jedis.ttl(ServerPrivacy.queueKey("file", user)) } ?: -1L
        // Dosya parcalari cevrimdisi bir kullanicida birikmemelidir; TTL
        // mesaj kuyrugundan kisadir.
        assertTrue(ttl > 0 && ttl <= ServerPrivacy.config.offlineFileTtlSeconds, "TTL: $ttl")
    }

    @Test
    fun `two recipients never share a queue`() = runBlocking {
        val first = UUID.randomUUID().toString()
        val second = UUID.randomUUID().toString()

        manager.routeMessage(first, envelope("only-first"))

        assertEquals(1L, queueSize("delivery", first))
        assertEquals(0L, queueSize("delivery", second))
    }

    @Test
    fun `sentinel recipients never create a queue`() = runBlocking {
        for (sentinel in listOf("SYSTEM", "server", "broadcast")) {
            manager.routeMessage(sentinel, envelope("sentinel"))

            assertEquals(0L, queueSize("message", sentinel), sentinel)
            assertEquals(0L, queueSize("delivery", sentinel), sentinel)
        }
    }

    // ---------------- Aktif cagri kayitlari ----------------

    @Test
    fun `an active call session is visible to both sides`() {
        val caller = UUID.randomUUID().toString()
        val callee = UUID.randomUUID().toString()

        manager.setActiveCallSession(caller, callee)

        assertTrue(manager.hasActiveCallSession(caller, callee))
        // Kayit yonden bagimsizdir; aksi halde karsi taraf aramayi
        // sonlandiramazdi.
        assertTrue(manager.hasActiveCallSession(callee, caller))
    }

    @Test
    fun `an unrelated pair has no session`() {
        val caller = UUID.randomUUID().toString()
        val callee = UUID.randomUUID().toString()
        manager.setActiveCallSession(caller, callee)

        assertFalse(manager.hasActiveCallSession(caller, UUID.randomUUID().toString()))
    }

    @Test
    fun `clearing a session ends it for both sides`() {
        val caller = UUID.randomUUID().toString()
        val callee = UUID.randomUUID().toString()
        manager.setActiveCallSession(caller, callee)

        manager.clearActiveCallSession(callee, caller)

        assertFalse(manager.hasActiveCallSession(caller, callee))
    }

    @Test
    fun `a disconnect clears every call session of that account`() {
        val user = UUID.randomUUID().toString()
        val first = UUID.randomUUID().toString()
        val second = UUID.randomUUID().toString()
        manager.setActiveCallSession(user, first)
        manager.setActiveCallSession(user, second)

        // Network kopmasinda istemci HANGUP gonderemez; sunucu temizler,
        // aksi halde hayalet arama kullaniciyi yeni aramalara kapatirdi.
        manager.clearAllCallSessionsFor(user)

        assertFalse(manager.hasActiveCallSession(user, first))
        assertFalse(manager.hasActiveCallSession(user, second))
    }

    @Test
    fun `an active call record expires on its own`() {
        val caller = UUID.randomUUID().toString()
        val callee = UUID.randomUUID().toString()
        manager.setActiveCallSession(caller, callee)

        val ttl = RedisManager.use { jedis ->
            jedis.ttl(ServerPrivacy.activeCallKey(caller, callee))
        } ?: -1L

        // Sunucu hicbir zaman kalici bir cagri kaydi tutmaz.
        assertTrue(ttl > 0, "TTL yok")
        assertTrue(ttl <= 300, "TTL: $ttl")
    }

    @Test
    fun `the call record key reveals neither participant`() {
        val caller = UUID.randomUUID().toString()
        val callee = UUID.randomUUID().toString()
        manager.setActiveCallSession(caller, callee)

        val key = ServerPrivacy.activeCallKey(caller, callee)

        assertFalse(key.contains(caller))
        assertFalse(key.contains(callee))
    }

    @Test
    fun `pending call signals of a caller can be purged`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        val caller = UUID.randomUUID().toString()
        manager.routeMessage(
            recipient,
            """{"type":"sdp_offer","senderId":"$caller","messageId":"o-1","sdp":"AAAA"}""",
        )
        assertEquals(1L, queueSize("message", recipient))
        assertEquals(0L, queueSize("delivery", recipient))

        // Arayan vazgectiginde bekleyen teklif teslim edilmemeli.
        manager.purgePendingCallSignals(recipient, caller)

        assertEquals(0L, queueSize("message", recipient))
    }

    @Test
    fun `purging one caller does not touch another caller's messages`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        val caller = UUID.randomUUID().toString()
        val other = UUID.randomUUID().toString()
        manager.routeMessage(
            recipient,
            """{"type":"sdp_offer","senderId":"$caller","messageId":"o-1","sdp":"AAAA"}""",
        )
        manager.routeMessage(
            recipient,
            """{"type":"encrypted_message","senderId":"$other","messageId":"m-1","ciphertext":"AAAA"}""",
        )

        manager.purgePendingCallSignals(recipient, caller)

        assertEquals(0L, queueSize("message", recipient))
        assertEquals(1L, queueSize("delivery", recipient))
    }

    @Test
    fun `transient signals are never persisted even when push is unconfigured`() = runBlocking {
        val user = UUID.randomUUID().toString()

        for (type in listOf(
            "typing_indicator",
            "presence_update",
            "presence_subscribe",
            "presence_unsubscribe",
            "audio_data",
            "video_data",
        )) {
            manager.routeMessage(user, """{"type":"$type","messageId":"t-$type"}""")
        }

        // Siniflandirma push tasiyicisina bagli oldugunda, push kapaliyken
        // bu davranis sinyalleri kalici kuyruga yaziliyordu.
        assertEquals(0L, queueSize("message", user))
        assertEquals(0L, queueSize("file", user))
        assertEquals(0L, queueSize("delivery", user))
    }

    @Test
    fun `a frame without a type still reaches the message queue`() = runBlocking {
        val user = UUID.randomUUID().toString()

        manager.routeMessage(user, """{"messageId":"no-type","ciphertext":"AAAA"}""")

        // Tur okunamiyorsa mesaj dusurulmez; teslim kaybi gizlilikten daha
        // kotu bir sonuctur.
        assertEquals(1L, queueSize("message", user))
    }

    @Test
    fun `same sender delivery id is idempotent and recipient ack removes it`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        val sender = UUID.randomUUID().toString()
        val deliveryId = "A".repeat(43)
        val frame = """{"type":"encrypted_message","senderId":"$sender","recipientId":"$recipient","deliveryId":"$deliveryId","envelope":"E2EE:v1:SIGNAL:1:AAAA"}"""

        manager.routeMessage(recipient, frame)
        val indexKey = ServerPrivacy.queueKey("delivery", recipient)
        val firstScore = RedisManager.use { jedis ->
            jedis.zscore(indexKey, jedis.zrange(indexKey, 0, 0).single())
        }
        val firstTtl = RedisManager.use { jedis -> jedis.ttl(indexKey) }
        Thread.sleep(1_100)
        manager.routeMessage(recipient, frame)

        assertEquals(1L, queueSize("delivery", recipient))
        val token = RedisManager.use { jedis ->
            jedis.zrange(indexKey, 0, 0).single()
        }
        assertEquals(firstScore, RedisManager.use { jedis -> jedis.zscore(indexKey, token) })
        val retriedTtl = RedisManager.use { jedis -> jedis.ttl(indexKey) }
        assertTrue(retriedTtl < firstTtl, "retry TTL'i yeniledi: $firstTtl -> $retriedTtl")
        assertTrue(manager.acknowledgeDelivery(recipient, token))
        assertEquals(0L, queueSize("delivery", recipient))
        assertTrue(reliablePayloads(recipient).isEmpty())
    }

    @Test
    fun `an ack from another account cannot remove a queued delivery`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        val attacker = UUID.randomUUID().toString()
        manager.routeMessage(recipient, envelope("ack-owner"))
        val token = RedisManager.use { jedis ->
            jedis.zrange(ServerPrivacy.queueKey("delivery", recipient), 0, 0).single()
        }

        assertFalse(manager.acknowledgeDelivery(attacker, token))
        assertEquals(1L, queueSize("delivery", recipient))
    }

    @Test
    fun `rapid reliable frames preserve signal protocol order`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        val sender = UUID.randomUUID().toString()
        val expected = listOf("control", "sender-key", "message")

        expected.forEachIndexed { index, marker ->
            manager.routeMessage(
                recipient,
                """{"type":"encrypted_message","senderId":"$sender","recipientId":"$recipient","deliveryId":"${('A'.code + index).toChar().toString().repeat(43)}","messageId":"$marker","envelope":"cipher-$marker"}""",
            )
        }

        val actual = RedisManager.use { jedis ->
            val indexKey = ServerPrivacy.queueKey("delivery", recipient)
            jedis.zrange(indexKey, 0, -1).map { token ->
                val sealed = jedis.get(
                    ServerPrivacy.queueItemKey("delivery", recipient, token),
                )
                val opened = ServerPrivacy.openQueue(recipient, sealed)
                Regex("\\\"messageId\\\":\\\"([^\\\"]+)\\\"")
                    .find(opened)?.groupValues?.get(1)
            }
        }

        assertEquals(expected, actual)
    }

    // ---------------- Kuyruk tasmasi: fail-closed ----------------

    @Test
    fun `a full queue refuses new ciphertext instead of dropping waiting messages`() = runBlocking {
        // Anonim relay kimlik dogrulamasi istemez. Tasmada en eski kayitlar
        // silinseydi, capability'yi bilen herkes alicinin bekleyen butun
        // mesajlarini birkac dakikada temizletebilirdi. Dogru davranis
        // gonderene "simdi olmaz" demektir.
        val recipient = UUID.randomUUID().toString()
        val chunk = "A".repeat(2 * 1024 * 1024)

        val firstAccepted = manager.routeSealedMessage(recipient, chunk, "B".repeat(43))
        assertTrue(firstAccepted, "ilk mesaj kabul edilmeliydi")
        val firstToken = RedisManager.use { jedis ->
            jedis.zrange(ServerPrivacy.queueKey("delivery", recipient), 0, 0).single()
        }

        var rejected = false
        for (index in 0 until 64) {
            val deliveryId = index.toString().padStart(43, 'C')
            if (!manager.routeSealedMessage(recipient, chunk, deliveryId)) {
                rejected = true
                break
            }
        }

        assertTrue(rejected, "kuyruk sinirsiz buyudu")
        // Tasma aninda bekleyen ilk ciphertext hala yerinde olmali.
        val stillQueued = RedisManager.use { jedis ->
            jedis.zscore(ServerPrivacy.queueKey("delivery", recipient), firstToken)
        }
        assertTrue(stillQueued != null, "tasma bekleyen mesaji dusurdu")
        manager.purgeQueuedEnvelopes(recipient)
    }

    @Test
    fun `an acknowledged delivery leaves no size ledger entry behind`() = runBlocking {
        // Boyut defteri sinir hesabinin kaynagidir. ACK sonrasi orada kalan
        // bir satir, kuyrugu oldugundan dolu gosterip zamanla mesajlarin
        // reddedilmesine yol acardi.
        val recipient = UUID.randomUUID().toString()
        manager.routeMessage(recipient, envelope("ledger-cleanup"))
        val metaKey = ServerPrivacy.queueMetaKey("delivery", recipient)
        assertEquals(1L, RedisManager.use { jedis -> jedis.hlen(metaKey) })

        val token = RedisManager.use { jedis ->
            jedis.zrange(ServerPrivacy.queueKey("delivery", recipient), 0, 0).single()
        }
        assertTrue(manager.acknowledgeDelivery(recipient, token))

        assertEquals(0L, RedisManager.use { jedis -> jedis.hlen(metaKey) })
        assertTrue(reliablePayloads(recipient).isEmpty())
    }

    @Test
    fun `account queue purge removes every reliable delivery key`() = runBlocking {
        val recipient = UUID.randomUUID().toString()
        manager.routeMessage(recipient, envelope("delete-account"))
        val token = RedisManager.use { jedis ->
            jedis.zrange(ServerPrivacy.queueKey("delivery", recipient), 0, 0).single()
        }

        manager.purgeQueuedEnvelopes(recipient)

        val remaining = RedisManager.use { jedis ->
            listOf(
                ServerPrivacy.queueKey("delivery", recipient),
                ServerPrivacy.queuePayloadKey("delivery", recipient),
                ServerPrivacy.queueOrderKey("delivery", recipient),
                ServerPrivacy.queueMetaKey("delivery", recipient),
                ServerPrivacy.queueItemKey("delivery", recipient, token),
            ).count(jedis::exists)
        }
        assertEquals(0, remaining)
    }
}
