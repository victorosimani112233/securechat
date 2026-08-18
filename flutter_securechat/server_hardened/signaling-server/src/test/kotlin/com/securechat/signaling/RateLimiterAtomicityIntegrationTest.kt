package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
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
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Rate limiter'in gercek Redis uzerinde atomik oldugunu kanitlar.
 *
 * Onceki uygulama `ZREMRANGEBYSCORE -> ZCARD -> ZADD` seklinde uc ayri
 * gidis-donusttu: es zamanli istekler ayni "limit altinda" okumasini paylasip
 * hep birlikte gecebiliyordu. Ayrica member yalniz timestamp oldugu icin ayni
 * milisaniyedeki istekler tek istek gibi sayiliyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class RateLimiterAtomicityIntegrationTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; rate limiter integration testi atlandi",
        )
        redis.start()
        RedisManager.init(redis.host, redis.getMappedPort(6379), null)
    }

    @AfterAll
    fun tearDown() {
        RedisManager.close()
        redis.stop()
    }

    private fun identity() = UUID.randomUUID().toString()

    @Test
    fun `sequential requests stop exactly at the configured limit`() {
        val endpoint = "ws_connect"
        val limit = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val identifier = identity()

        repeat(limit) { assertTrue(RateLimiter.allow(endpoint, identifier)) }
        assertFalse(RateLimiter.allow(endpoint, identifier))
    }

    @Test
    fun `parallel requests never exceed the limit`() {
        val endpoint = "users_register"
        val limit = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val identifier = identity()
        val attempts = limit * 8

        val pool = Executors.newFixedThreadPool(16)
        try {
            val allowed = pool.invokeAll(
                (0 until attempts).map { Callable { RateLimiter.allow(endpoint, identifier) } },
            ).count { it.get() }
            // Atomik olmayan uygulamada bu sayi limitin ustune cikiyordu.
            assertEquals(limit, allowed)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `requests inside the same millisecond are counted separately`() {
        val endpoint = "ws_message"
        val limit = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val identifier = identity()

        // Ayni milisaniyede pes pese: eski member semasinda hepsi tek kayda
        // dusuyor ve limit hic dolmuyordu.
        var allowed = 0
        repeat(limit + 5) { if (RateLimiter.allow(endpoint, identifier)) allowed++ }
        assertEquals(limit, allowed)
    }

    @Test
    fun `byte quota accumulates the transferred size`() {
        val endpoint = "file_chunk_bytes"
        val maxBytes = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val identifier = identity()
        val chunk = maxBytes / 4

        repeat(4) { assertTrue(RateLimiter.allowBytes(endpoint, identifier, chunk)) }
        assertFalse(RateLimiter.allowBytes(endpoint, identifier, chunk))
    }

    @Test
    fun `a single oversized transfer is refused without consuming the window`() {
        val endpoint = "file_chunk_bytes"
        val maxBytes = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val identifier = identity()

        assertFalse(RateLimiter.allowBytes(endpoint, identifier, maxBytes + 1))
        // Reddedilen istek quota yakmamali.
        assertTrue(RateLimiter.allowBytes(endpoint, identifier, maxBytes))
    }

    @Test
    fun `separate identifiers do not share a window`() {
        val endpoint = "otp_request"
        val limit = RateLimiter.LIMITS.getValue(endpoint).maxRequests
        val first = identity()
        val second = identity()

        repeat(limit) { assertTrue(RateLimiter.allow(endpoint, first)) }
        assertFalse(RateLimiter.allow(endpoint, first))
        assertTrue(RateLimiter.allow(endpoint, second))
    }

    @Test
    fun `an unknown endpoint is not rate limited`() {
        assertTrue(RateLimiter.allow("endpoint_without_policy", identity()))
    }
}
