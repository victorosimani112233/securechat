package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
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
 * OTP durum gecislerinin atomikligi.
 *
 * Onceki akis `HGETALL -> karsilastir -> DEL/HINCRBY` idi: paralel iki dogru
 * deneme ikisi de basarili sayilip tek OTP'den iki registration grant
 * uretebiliyordu; paralel yanlis denemeler ise deneme tavanini asabiliyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class OtpAtomicityIntegrationTest {

    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; OTP integration testi atlandi",
        )
        redis.start()
        RedisManager.init(redis.host, redis.getMappedPort(6379), null)
    }

    @AfterAll
    fun tearDown() {
        RedisManager.close()
        redis.stop()
    }

    private fun email() = "user-${UUID.randomUUID()}@example.com"

    @Test
    fun `a correct code verifies once and only once`() {
        val address = email()
        val otp = OtpService.generateOtp(address)

        assertTrue(OtpService.verifyOtp(address, otp))
        // Tuketilmis OTP yeniden kullanilamaz.
        assertFalse(OtpService.verifyOtp(address, otp))
    }

    @Test
    fun `parallel correct submissions mint a single success`() {
        val address = email()
        val otp = OtpService.generateOtp(address)
        val attempts = 8

        val pool = Executors.newFixedThreadPool(attempts)
        try {
            val successes = pool.invokeAll(
                (0 until attempts).map { Callable { OtpService.verifyOtp(address, otp) } },
            ).count { it.get() }
            // Atomik olmayan uygulamada bu sayi 1'den buyuk olabiliyordu.
            assertEquals(1, successes)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `the attempt ceiling is never exceeded by parallel guesses`() {
        val address = email()
        val correct = OtpService.generateOtp(address)
        val wrong = if (correct == "000000") "111111" else "000000"
        val attempts = 20

        val pool = Executors.newFixedThreadPool(8)
        try {
            pool.invokeAll(
                (0 until attempts).map { Callable { OtpService.verifyOtp(address, wrong) } },
            ).forEach { it.get() }
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }

        // Tavan asildiktan sonra dogru kod bile kabul edilmez.
        assertFalse(OtpService.verifyOtp(address, correct))
    }

    @Test
    fun `a malformed code never touches the stored state`() {
        val address = email()
        val otp = OtpService.generateOtp(address)

        repeat(10) { assertFalse(OtpService.verifyOtp(address, "abc")) }
        // Bicimsiz denemeler deneme hakkini tuketmemeli.
        assertTrue(OtpService.verifyOtp(address, otp))
    }

    @Test
    fun `the cooldown is enforced in the same atomic step`() {
        val address = email()
        OtpService.generateOtp(address)

        val error = assertThrows(OtpService.OtpCooldownException::class.java) {
            OtpService.generateOtp(address)
        }
        assertTrue(error.remainingMillis > 0)
        assertTrue(error.remainingMillis <= OtpService.COOLDOWN_MILLIS)
    }

    @Test
    fun `parallel requests for one address produce a single code`() {
        val address = email()
        val attempts = 8

        val pool = Executors.newFixedThreadPool(attempts)
        try {
            val created = pool.invokeAll(
                (0 until attempts).map {
                    Callable { runCatching { OtpService.generateOtp(address) }.isSuccess }
                },
            ).count { it.get() }
            assertEquals(1, created)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `a code issued for one address does not verify for another`() {
        val first = email()
        val second = email()
        val otp = OtpService.generateOtp(first)
        OtpService.generateOtp(second)

        assertFalse(OtpService.verifyOtp(second, otp))
    }
}
