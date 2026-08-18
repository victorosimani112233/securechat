package com.securechat.botapi.delivery

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors

/**
 * Giden kuyrugun teslim garantileri.
 *
 * Onceki tasarimda `RPOP` mesaji hemen siliyordu: process veya soket o anda
 * olurse 202 verilmis bir mesaj kayboluyordu. Basarisiz teslimde mesaj
 * `LPUSH` ile geri yaziliyor ve FIFO kuyrukta sirasinin sonuna dusuyordu.
 * `WebSocket.send()==true` ise yalniz "tampona kondu" demektir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class OutboundQueueDurabilityTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private val bot = UUID.randomUUID().toString()

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; outbound queue testi atlandi",
        )
        redis.start()
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 31).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 71).toByte() }
        BotApiConfig.outboundQueueTtlSeconds = 900
        BotApiConfig.redisHost = redis.host
        BotApiConfig.redisPort = redis.getMappedPort(6379)
        BotApiConfig.redisPassword = null
        BotRedisManager.init()
    }

    @AfterAll
    fun tearDown() {
        BotRedisManager.close()
        redis.stop()
    }

    private fun envelope(id: String) =
        """{"type":"encrypted_message","messageId":"$id","ciphertext":"AAA="}"""

    @Test
    fun `a checked out message stays in flight until it is acknowledged`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("m1"))

        val checkout = OutboundQueue.checkoutNext(queueOwner)
        assertThat(checkout).isNotNull()
        assertThat(checkout!!.messageId).isEqualTo("m1")
        // Kuyruktan cikti ama kaybolmadi.
        assertThat(OutboundQueue.size(queueOwner)).isEqualTo(0)
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(1)

        OutboundQueue.acknowledge(queueOwner, "m1")
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(0)
    }

    @Test
    fun `an unacknowledged message returns to the queue after the visibility timeout`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("m2"))
        OutboundQueue.checkoutNext(queueOwner)

        // Gorunurluk suresi henuz dolmadi.
        assertThat(OutboundQueue.reclaimExpired(queueOwner)).isEqualTo(0)

        expireInflight(queueOwner)
        assertThat(OutboundQueue.reclaimExpired(queueOwner)).isEqualTo(1)
        assertThat(OutboundQueue.size(queueOwner)).isEqualTo(1)
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(0)
    }

    @Test
    fun `a reclaimed message keeps its place at the front of the queue`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("first"))
        OutboundQueue.enqueue(queueOwner, envelope("second"))

        val checkout = OutboundQueue.checkoutNext(queueOwner)
        assertThat(checkout!!.messageId).isEqualTo("first")
        expireInflight(queueOwner)
        OutboundQueue.reclaimExpired(queueOwner)

        // Geri alinan mesaj sirasini korumali; eski `LPUSH` onu sona atardi.
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("first")
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("second")
    }

    @Test
    fun `multiple reclaimed messages preserve checkout order even when ids sort differently`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("z-first"))
        OutboundQueue.enqueue(queueOwner, envelope("a-second"))
        OutboundQueue.enqueue(queueOwner, envelope("middle-third"))

        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("z-first")
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("a-second")
        expireInflight(queueOwner)

        assertThat(OutboundQueue.reclaimExpired(queueOwner)).isEqualTo(2)
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("z-first")
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("a-second")
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("middle-third")
    }

    @Test
    fun `concurrent checkouts use independent in-flight records`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("concurrent-a"))
        OutboundQueue.enqueue(queueOwner, envelope("concurrent-b"))
        val executor = Executors.newFixedThreadPool(2)
        try {
            val results = executor.invokeAll(
                listOf(
                    Callable { OutboundQueue.checkoutNext(queueOwner) },
                    Callable { OutboundQueue.checkoutNext(queueOwner) },
                ),
            ).mapNotNull { it.get()?.messageId }

            assertThat(results).containsExactly("concurrent-a", "concurrent-b")
            assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(2)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `a failed send is requeued in order and stops the drain`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("a"))
        OutboundQueue.enqueue(queueOwner, envelope("b"))

        val delivered = mutableListOf<String>()
        OutboundQueue.drainAll(queueOwner) { payload ->
            delivered += payload
            // Ilk mesaj gonderilemiyor.
            false
        }

        assertThat(delivered).hasSize(1)
        assertThat(OutboundQueue.size(queueOwner)).isEqualTo(2)
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(0)
        // Sira korunmali.
        assertThat(OutboundQueue.checkoutNext(queueOwner)!!.messageId).isEqualTo("a")
    }

    @Test
    fun `a successful drain leaves every message awaiting an acknowledgement`() {
        val queueOwner = UUID.randomUUID().toString()
        OutboundQueue.enqueue(queueOwner, envelope("x"))
        OutboundQueue.enqueue(queueOwner, envelope("y"))

        OutboundQueue.drainAll(queueOwner) { true }

        // Gonderim denendi, fakat ACK gelmeden hicbiri silinmez.
        assertThat(OutboundQueue.size(queueOwner)).isEqualTo(0)
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(2)

        OutboundQueue.acknowledge(queueOwner, "x")
        OutboundQueue.acknowledge(queueOwner, "y")
        assertThat(OutboundQueue.inflightSize(queueOwner)).isEqualTo(0)
    }

    @Test
    fun `an empty queue yields nothing`() {
        assertThat(OutboundQueue.checkoutNext(UUID.randomUUID().toString())).isNull()
    }

    /** In-flight kayitlarini gorunurluk suresi dolmus gibi geriye alir. */
    private fun expireInflight(queueOwner: String) {
        BotRedisManager.use { jedis ->
            val indexKey = "${BotQueuePrivacy.key(queueOwner)}:inflight_at"
            jedis.zrange(indexKey, 0, -1).forEach { member ->
                val score = requireNotNull(jedis.zscore(indexKey, member))
                jedis.zadd(indexKey, score - 60_000.0, member)
            }
        }
    }
}
