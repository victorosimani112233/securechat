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

    private fun envelope(marker: String, size: Int = 64) =
        """{"type":"encrypted_message","messageId":"$marker","ciphertext":"${"A".repeat(size)}"}"""

    // ---------------- Offline kuyruk ----------------

    @Test
    fun `a message for an offline recipient is queued`() = runBlocking {
        val user = UUID.randomUUID().toString()

        manager.routeMessage(user, envelope("m-1"))

        assertEquals(1L, queueSize("message", user))
    }

    @Test
    fun `the queued envelope is sealed`() = runBlocking {
        val user = UUID.randomUUID().toString()
        val marker = "MARKER-${UUID.randomUUID()}"

        manager.routeMessage(user, envelope(marker))

        val stored = RedisManager.use { jedis ->
            jedis.zrange(ServerPrivacy.queueKey("message", user), 0, -1)
        } ?: emptySet()
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
        assertTrue(queueSize("message", user) <= 1_000L, "kuyruk boyutu: ${queueSize("message", user)}")
    }

    @Test
    fun `the queue carries a bounded ttl`() = runBlocking {
        val user = UUID.randomUUID().toString()
        manager.routeMessage(user, envelope("ttl"))

        val ttl = RedisManager.use { jedis ->
            jedis.ttl(ServerPrivacy.queueKey("message", user))
        } ?: -1L

        assertTrue(ttl > 0, "TTL yok")
        assertTrue(ttl <= ServerPrivacy.config.offlineQueueTtlSeconds, "TTL: $ttl")
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

        assertEquals(1L, queueSize("message", first))
        assertEquals(0L, queueSize("message", second))
    }

    @Test
    fun `sentinel recipients never create a queue`() = runBlocking {
        for (sentinel in listOf("SYSTEM", "server", "broadcast")) {
            manager.routeMessage(sentinel, envelope("sentinel"))

            assertEquals(0L, queueSize("message", sentinel), sentinel)
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

        assertEquals(1L, queueSize("message", recipient))
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
    }

    @Test
    fun `a frame without a type still reaches the message queue`() = runBlocking {
        val user = UUID.randomUUID().toString()

        manager.routeMessage(user, """{"messageId":"no-type","ciphertext":"AAAA"}""")

        // Tur okunamiyorsa mesaj dusurulmez; teslim kaybi gizlilikten daha
        // kotu bir sonuctur.
        assertEquals(1L, queueSize("message", user))
    }
}
