package com.securechat.botapi.send

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.auth.AuthenticatedClient
import com.securechat.botapi.auth.NonceStore
import com.securechat.botapi.db.BotRedisManager
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName

/**
 * Bot gonderim kapilari: rate limit, nonce ve idempotency.
 *
 * Ucu de kotuye kullanim sinirlaridir ve ucu de Redis'te durur. Rate limit
 * penceresi atomik degilse es zamanli istekler siniri birlikte asar;
 * idempotency rezervasyonu yarisirsa ayni mesaj iki kez gonderilir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class BotRateLimitAndIdempotencyTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; test atlandi")
        redis.start()
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 17).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 53).toByte() }
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

    private fun client(
        ratePerHour: Int = 10,
        perRecipientPerDay: Int = 10,
    ) = AuthenticatedClient(
        clientId = UUID.randomUUID().toString(),
        kid = "k",
        name = "AC1:test",
        publicKey = ByteArray(32),
        allowList = emptyList(),
        ratePerHour = ratePerHour,
        perRecipientPerDay = perRecipientPerDay,
    )

    // ---------------- Rate limit ----------------

    @Test
    fun `requests are allowed up to the hourly ceiling and refused after it`() {
        val subject = client(ratePerHour = 5, perRecipientPerDay = 1000)
        val recipient = "user:${UUID.randomUUID()}"

        repeat(5) { assertThat(RateLimitGuard.check(subject, recipient).allowed).isTrue() }
        val refused = RateLimitGuard.check(subject, recipient)

        assertThat(refused.allowed).isFalse()
        assertThat(refused.reason).isEqualTo("client_per_hour")
        assertThat(refused.retryAfterSeconds).isGreaterThan(0L)
    }

    @Test
    fun `a group fanout charges one unit per recipient`() {
        val subject = client(ratePerHour = 10, perRecipientPerDay = 1000)
        val recipient = "group:${UUID.randomUUID()}"

        // Tek istek 8 alici: tek birim sayilsaydi limit amplifikasyonu olurdu.
        assertThat(RateLimitGuard.check(subject, recipient, cost = 8).allowed).isTrue()
        assertThat(RateLimitGuard.check(subject, recipient, cost = 8).allowed).isFalse()
    }

    @Test
    fun `the per recipient ceiling is independent of the client ceiling`() {
        val subject = client(ratePerHour = 1000, perRecipientPerDay = 3)
        val recipient = "user:${UUID.randomUUID()}"
        val other = "user:${UUID.randomUUID()}"

        repeat(3) { assertThat(RateLimitGuard.check(subject, recipient).allowed).isTrue() }
        val refused = RateLimitGuard.check(subject, recipient)

        assertThat(refused.allowed).isFalse()
        assertThat(refused.reason).isEqualTo("recipient_per_day")
        // Baska bir alici bundan etkilenmemeli.
        assertThat(RateLimitGuard.check(subject, other).allowed).isTrue()
    }

    @Test
    fun `two clients do not share a counter`() {
        val first = client(ratePerHour = 2)
        val second = client(ratePerHour = 2)
        val recipient = "user:${UUID.randomUUID()}"

        repeat(2) { assertThat(RateLimitGuard.check(first, recipient).allowed).isTrue() }
        assertThat(RateLimitGuard.check(first, recipient).allowed).isFalse()
        assertThat(RateLimitGuard.check(second, recipient).allowed).isTrue()
    }

    @Test
    fun `an invalid cost is refused outright`() {
        val subject = client()
        val recipient = "user:${UUID.randomUUID()}"

        assertThat(RateLimitGuard.check(subject, recipient, cost = 0).allowed).isFalse()
        assertThat(RateLimitGuard.check(subject, recipient, cost = -1).allowed).isFalse()
        assertThat(RateLimitGuard.check(subject, recipient, cost = 257).allowed).isFalse()
        // 256 gecerli bir maliyettir; reddedilirse sebep sinir olmalidir,
        // "gecersiz maliyet" degil.
        val roomy = client(ratePerHour = 1000, perRecipientPerDay = 1000)
        assertThat(RateLimitGuard.check(roomy, recipient, cost = 256).allowed).isTrue()
    }

    @Test
    fun `concurrent requests cannot exceed the ceiling together`() {
        val subject = client(ratePerHour = 10, perRecipientPerDay = 1000)
        val recipient = "user:${UUID.randomUUID()}"
        val threads = 16
        val executor = Executors.newFixedThreadPool(threads)
        try {
            val tasks = (0 until threads).map {
                Callable { RateLimitGuard.check(subject, recipient).allowed }
            }
            val granted = executor.invokeAll(tasks).count { it.get() }

            // Pencere atomik degilse es zamanli okumalar siniri birlikte asar.
            assertThat(granted).isEqualTo(10)
        } finally {
            executor.shutdown()
            executor.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `many requests inside the same millisecond each count`() {
        val subject = client(ratePerHour = 4, perRecipientPerDay = 1000)
        val recipient = "user:${UUID.randomUUID()}"

        // Ayni milisaniyedeki istekler ayni sorted-set member'ina duserse
        // tek istek gibi sayilirlardi.
        val allowed = (1..8).count { RateLimitGuard.check(subject, recipient).allowed }

        assertThat(allowed).isEqualTo(4)
    }

    @Test
    fun `a zero ceiling refuses everything`() {
        val subject = client(ratePerHour = 0)

        assertThat(RateLimitGuard.check(subject, "user:x").allowed).isFalse()
    }

    @Test
    fun `the counter key carries neither the client id nor the recipient`() {
        val subject = client(ratePerHour = 5)
        val recipient = "user:${UUID.randomUUID()}"
        RateLimitGuard.check(subject, recipient)

        val keys = BotRedisManager.use { jedis -> jedis.keys("bot_rl_v2:*") } ?: emptySet()

        assertThat(keys).isNotEmpty()
        for (key in keys) {
            assertThat(key).doesNotContain(subject.clientId)
            assertThat(key).doesNotContain(recipient)
        }
    }

    // ---------------- Nonce ----------------

    @Test
    fun `a nonce can only be consumed once`() {
        val jti = UUID.randomUUID().toString()

        assertThat(NonceStore.tryConsume(jti)).isTrue()
        assertThat(NonceStore.tryConsume(jti)).isFalse()
    }

    @Test
    fun `distinct nonces do not collide`() {
        assertThat(NonceStore.tryConsume(UUID.randomUUID().toString())).isTrue()
        assertThat(NonceStore.tryConsume(UUID.randomUUID().toString())).isTrue()
    }

    @Test
    fun `a concurrent replay is won by exactly one caller`() {
        val jti = UUID.randomUUID().toString()
        val threads = 12
        val executor = Executors.newFixedThreadPool(threads)
        try {
            val tasks = (0 until threads).map { Callable { NonceStore.tryConsume(jti) } }
            val winners = executor.invokeAll(tasks).count { it.get() }

            assertThat(winners).isEqualTo(1)
        } finally {
            executor.shutdown()
            executor.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `the nonce record expires and stores no raw jti`() {
        val jti = UUID.randomUUID().toString()
        NonceStore.tryConsume(jti)

        val keys = BotRedisManager.use { jedis -> jedis.keys("bot_jti_v2:*") } ?: emptySet()
        assertThat(keys).isNotEmpty()
        for (key in keys) assertThat(key).doesNotContain(jti)

        val ttl = BotRedisManager.use { jedis -> jedis.ttl(keys.first()) } ?: -1L
        assertThat(ttl).isGreaterThan(0L)
        assertThat(ttl).isAtMost(120L)
    }

    // ---------------- Idempotency ----------------

    @Test
    fun `the first request reserves and a second sees pending`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()

        assertThat(IdempotencyStore.checkAndReserve(clientId, key))
            .isInstanceOf(IdempotencyStore.CheckResult.Fresh::class.java)
        assertThat(IdempotencyStore.checkAndReserve(clientId, key))
            .isInstanceOf(IdempotencyStore.CheckResult.Pending::class.java)
    }

    @Test
    fun `a completed request returns its cached response`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        val response = """{"messageId":"m-1","status":"queued"}"""
        IdempotencyStore.checkAndReserve(clientId, key)
        IdempotencyStore.storeResult(clientId, key, response)

        val result = IdempotencyStore.checkAndReserve(clientId, key)

        assertThat(result).isInstanceOf(IdempotencyStore.CheckResult.Cached::class.java)
        assertThat((result as IdempotencyStore.CheckResult.Cached).responseJson).isEqualTo(response)
    }

    @Test
    fun `releasing lets the same key be retried`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        IdempotencyStore.checkAndReserve(clientId, key)

        IdempotencyStore.release(clientId, key)

        assertThat(IdempotencyStore.checkAndReserve(clientId, key))
            .isInstanceOf(IdempotencyStore.CheckResult.Fresh::class.java)
    }

    @Test
    fun `the same key from another client is independent`() {
        val key = UUID.randomUUID().toString()
        IdempotencyStore.checkAndReserve(UUID.randomUUID().toString(), key)

        assertThat(IdempotencyStore.checkAndReserve(UUID.randomUUID().toString(), key))
            .isInstanceOf(IdempotencyStore.CheckResult.Fresh::class.java)
    }

    @Test
    fun `exactly one concurrent caller gets the reservation`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        val threads = 12
        val executor = Executors.newFixedThreadPool(threads)
        try {
            val tasks = (0 until threads).map {
                Callable { IdempotencyStore.checkAndReserve(clientId, key) }
            }
            val results = executor.invokeAll(tasks).map { it.get() }

            // Iki "Fresh" ayni mesajin iki kez gonderilmesi demektir.
            assertThat(results.count { it is IdempotencyStore.CheckResult.Fresh }).isEqualTo(1)
        } finally {
            executor.shutdown()
            executor.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `a plaintext or foreign cache value is never returned`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        IdempotencyStore.checkAndReserve(clientId, key)
        IdempotencyStore.storeResult(clientId, key, """{"messageId":"m","status":"queued"}""")

        // Baska bir client'in baglamiyla acilmaya calisilan kayit
        // cozulemez; duz metin geri dondurulmemelidir.
        val foreign = IdempotencyStore.checkAndReserve(UUID.randomUUID().toString(), key)

        assertThat(foreign).isInstanceOf(IdempotencyStore.CheckResult.Fresh::class.java)
    }

    @Test
    fun `an invalid idempotency key is refused`() {
        val clientId = UUID.randomUUID().toString()

        for (bad in listOf("", " ", "x".repeat(129))) {
            var threw = false
            try {
                IdempotencyStore.checkAndReserve(clientId, bad)
            } catch (_: IllegalArgumentException) {
                threw = true
            }
            assertThat(threw).isTrue()
        }
    }

    @Test
    fun `the stored response is sealed rather than plain json`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        val marker = "MARKER-${UUID.randomUUID()}"
        IdempotencyStore.checkAndReserve(clientId, key)
        IdempotencyStore.storeResult(clientId, key, """{"messageId":"$marker"}""")

        val stored = BotRedisManager.use { jedis ->
            jedis.keys("bot_idem_v2:*").mapNotNull { jedis.get(it) }
        } ?: emptyList()

        assertThat(stored).isNotEmpty()
        for (value in stored) assertThat(value).doesNotContain(marker)
    }

    @Test
    fun `the reservation carries a bounded ttl`() {
        val clientId = UUID.randomUUID().toString()
        val key = UUID.randomUUID().toString()
        IdempotencyStore.checkAndReserve(clientId, key)

        val ttls = BotRedisManager.use { jedis ->
            jedis.keys("bot_idem_v2:*").map { jedis.ttl(it) }
        } ?: emptyList()

        assertThat(ttls).isNotEmpty()
        assertThat(ttls.max()).isAtMost(BotApiConfig.idempotencyTtlSeconds.toLong())
        assertThat(ttls.max()).isGreaterThan(0L)
    }
}
