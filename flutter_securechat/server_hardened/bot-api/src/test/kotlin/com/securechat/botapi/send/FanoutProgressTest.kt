package com.securechat.botapi.send

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotRedisManager
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName

/**
 * Grup fanout'unun kismi basari davranisi.
 *
 * Onceki akista kismi basari tum idempotency rezervasyonunu birakiyordu:
 * ayni anahtarla yapilan retry, mesaji **zaten almis** uyelere yeniden
 * gonderiyordu. Ilerleme kaydi retry'in yalniz eksik kalanlari islemesini
 * saglar; kayit opaque'tir ve ham UUID ya da grup kimligi tasimaz.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class FanoutProgressTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private val client = "AC1"
    private val members = List(4) { UUID.randomUUID().toString() }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; fanout ilerleme testi atlandi",
        )
        redis.start()
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 13).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 47).toByte() }
        BotApiConfig.idempotencyTtlSeconds = 900
        BotApiConfig.redisHost = redis.host
        BotApiConfig.redisPort = redis.getMappedPort(6379)
        BotApiConfig.redisPassword = null
        BotRedisManager.init()
    }

    @AfterAll
    fun tearDown() {
        if (DockerClientFactory.instance().isDockerAvailable) {
            BotRedisManager.close()
            redis.stop()
        }
    }

    private fun key() = UUID.randomUUID().toString()

    @Test
    fun `nothing is delivered before the first attempt`() {
        val idem = key()

        assertThat(FanoutProgress.delivered(client, idem)).isEmpty()
        assertThat(FanoutProgress.isDelivered(client, idem, members[0])).isFalse()
    }

    @Test
    fun `a retry skips the members that already received the message`() {
        val idem = key()
        // Ilk deneme: iki uye basarili, sonra hata.
        FanoutProgress.markDelivered(client, idem, members[0])
        FanoutProgress.markDelivered(client, idem, members[1])

        val remaining = members.filterNot { FanoutProgress.isDelivered(client, idem, it) }

        assertThat(remaining).containsExactly(members[2], members[3]).inOrder()
    }

    @Test
    fun `marking the same member twice is idempotent`() {
        val idem = key()
        FanoutProgress.markDelivered(client, idem, members[0])
        FanoutProgress.markDelivered(client, idem, members[0])

        assertThat(FanoutProgress.delivered(client, idem)).hasSize(1)
    }

    @Test
    fun `progress is scoped to the idempotency key`() {
        val first = key()
        val second = key()
        FanoutProgress.markDelivered(client, first, members[0])

        // Farkli bir istek ayni uyeyi teslim edilmis saymamali.
        assertThat(FanoutProgress.isDelivered(client, second, members[0])).isFalse()
    }

    @Test
    fun `progress is scoped to the api client`() {
        val idem = key()
        FanoutProgress.markDelivered(client, idem, members[0])

        assertThat(FanoutProgress.isDelivered("AC2", idem, members[0])).isFalse()
    }

    @Test
    fun `a completed fanout clears its progress record`() {
        val idem = key()
        members.forEach { FanoutProgress.markDelivered(client, idem, it) }
        assertThat(FanoutProgress.delivered(client, idem)).hasSize(members.size)

        FanoutProgress.clear(client, idem)

        assertThat(FanoutProgress.delivered(client, idem)).isEmpty()
    }

    @Test
    fun `the record carries neither the raw member id nor the raw idempotency key`() {
        val idem = key()
        FanoutProgress.markDelivered(client, idem, members[0])

        val keys = BotRedisManager.use { jedis -> jedis.keys("bot_fanout_v1:*") } ?: emptySet()
        assertThat(keys).isNotEmpty()
        // Anahtar client + idempotency key'in blind index'idir; ham deger
        // Redis'te hicbir anahtarda gorunmemeli.
        for (redisKey in keys) {
            assertThat(redisKey).doesNotContain(idem)
            assertThat(redisKey).doesNotContain(client)
        }

        val storedMembers = FanoutProgress.delivered(client, idem)
        assertThat(storedMembers).hasSize(1)
        assertThat(storedMembers.first()).doesNotContain(members[0])
    }

    @Test
    fun `the record expires so it cannot outlive the idempotency window`() {
        val idem = key()
        FanoutProgress.markDelivered(client, idem, members[0])

        // Kaydin kendi anahtarini ayni turetmeyle bulur; sinifin diger
        // testleri de anahtar yazdigi icin "tek anahtar" varsayilamaz.
        val ttl = BotRedisManager.use { jedis ->
            jedis.keys("bot_fanout_v1:*")
                .map { it to jedis.ttl(it) }
                .filter { (_, remaining) -> remaining > 0 }
                .map { (_, remaining) -> remaining }
                .maxOrNull()
        }

        assertThat(ttl).isNotNull()
        assertThat(ttl!!).isGreaterThan(0L)
        assertThat(ttl).isAtMost(BotApiConfig.idempotencyTtlSeconds.toLong())
    }
}
