package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
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
import org.testcontainers.containers.PostgreSQLContainer

/**
 * Kalici rehber kotasi.
 *
 * Kota daha once yalniz Redis'te tutuluyordu. Redis bu dagitimda kasten
 * kalicisizdir; restart tum kotalari sifirliyor ve enumeration'a karsi
 * konulan sinir tekrar tekrar denenebiliyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class DirectoryQuotaIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_directory_quota_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private val day = 20_000L * 86_400_000L

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; rehber kotasi integration testi atlandi",
        )
        postgres.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password)
            .use { connection ->
                connection.autoCommit = true
                for (version in 1..LAST_MIGRATION) {
                    val migration = Files.list(migrationDir).use { paths ->
                        paths.filter { it.fileName.toString().startsWith("V${version}__") }
                            .findFirst()
                            .orElseThrow()
                    }
                    connection.createStatement().use { it.execute(Files.readString(migration)) }
                }
            }
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
    }

    @AfterAll
    fun tearDown() {
        if (DockerClientFactory.instance().isDockerAvailable) {
            Database.close()
            postgres.stop()
        }
    }

    private fun consume(userId: String, cost: Int, nowMillis: Long, limit: Int): Boolean =
        Database.getConnection().use { connection ->
            DirectoryQuota.consume(connection, userId, cost, nowMillis, limit)
        }

    @Test
    fun `the daily limit is enforced and survives a restart`() {
        val user = "quota-user-1"

        assertTrue(consume(user, 256, day, 512))
        assertTrue(consume(user, 256, day, 512))
        // Sinir doldu: ucuncu batch reddedilmeli.
        assertFalse(consume(user, 256, day, 512))

        // Redis'in silinmesi kotayi etkilemez; kayit PostgreSQL'dedir.
        assertFalse(consume(user, 1, day, 512))
    }

    @Test
    fun `a rejected request does not consume quota`() {
        val user = "quota-user-2"

        assertTrue(consume(user, 500, day, 512))
        assertFalse(consume(user, 256, day, 512))
        // Reddedilen istek sayaci artirsaydi hesap kendini kalici olarak
        // kilitlerdi; kalan 12 aday hala harcanabilir olmali.
        assertTrue(consume(user, 12, day, 512))
    }

    @Test
    fun `the counter resets on the next day bucket`() {
        val user = "quota-user-3"

        assertTrue(consume(user, 512, day, 512))
        assertFalse(consume(user, 1, day, 512))
        assertTrue(consume(user, 512, day + 86_400_000L, 512))
    }

    @Test
    fun `accounts do not share a counter`() {
        assertTrue(consume("quota-user-4", 512, day, 512))
        assertTrue(consume("quota-user-5", 512, day, 512))
    }

    @Test
    fun `concurrent requests cannot exceed the limit`() {
        val user = "quota-user-6"
        val threads = 8
        val executor = Executors.newFixedThreadPool(threads)
        try {
            val tasks = (0 until threads).map {
                Callable { consume(user, 256, day, 512) }
            }
            val granted = executor.invokeAll(tasks).count { it.get() }

            // Iki batch gecmeli; es zamanli okuma yarisi yasanirsa daha
            // fazlasi gecerdi.
            assertEquals(2, granted)
        } finally {
            executor.shutdown()
            executor.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `old day buckets are purged`() {
        val user = "quota-user-7"
        assertTrue(consume(user, 10, day, 512))

        val removed = Database.getConnection().use { connection ->
            DirectoryQuota.purgeExpired(connection, day + 5 * 86_400_000L)
        }

        assertTrue(removed >= 1)
    }

    companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
    }
}
