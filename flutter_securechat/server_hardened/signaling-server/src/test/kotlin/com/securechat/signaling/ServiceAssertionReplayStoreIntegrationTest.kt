package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
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

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ServiceAssertionReplayStoreIntegrationTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; test atlandi")
        redis.start()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        RedisManager.use { it.flushDB() }
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        RedisManager.close()
        redis.stop()
    }

    @Test
    fun `a service assertion replay id is consumed atomically once`() {
        val jti = UUID.randomUUID().toString()
        val pool = Executors.newFixedThreadPool(16)
        try {
            val accepted = pool.invokeAll(
                List(32) { Callable { ServiceAssertionReplayStore.tryConsume(jti) } },
            ).count { it.get() }
            assertEquals(1, accepted)
        } finally {
            pool.shutdown()
            assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))
        }
        assertFalse(ServiceAssertionReplayStore.tryConsume(jti))
        assertFalse(ServiceAssertionReplayStore.keyFor(jti).contains(jti))
    }
}
