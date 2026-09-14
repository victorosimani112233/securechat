package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

/**
 * Sema migration kapisi.
 *
 * `validateOnMigrate` kapaliyken uygulanmis bir migration dosyasi sonradan
 * degistirilebiliyor ve sema ile kod sessizce ayrisabiliyordu. `baselineOnMigrate`
 * tek basina da yetmez: beklenmeyen bir mevcut sema sessizce V0 sayilip
 * uzerine yazilabilirdi. Startup bu yuzden ulasilan surumu ayrica dogrular.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class SchemaMigrationIntegrationTest {

    private val migrationDir = Path.of(System.getProperty("serverMigrationDir"))

    private fun expectedVersion(): String =
        Files.list(migrationDir).use { paths ->
            paths.map { it.fileName.toString() }
                .filter { it.startsWith("V") && it.endsWith(".sql") }
                .map { it.removePrefix("V").substringBefore("__").toInt() }
                .max(Comparator.naturalOrder())
                .orElseThrow()
                .toString()
        }

    private fun container() = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_schema_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @AfterEach
    fun closePool() {
        runCatching { Database.close() }
    }

    @Test
    fun `a fresh database migrates to exactly the version this build expects`() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok")
        val postgres = container()
        postgres.start()
        try {
            Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
            Database.ensureSchema()

            val applied = DriverManager.getConnection(
                postgres.jdbcUrl, postgres.username, postgres.password,
            ).use { connection ->
                connection.createStatement().use { statement ->
                    statement.executeQuery(
                        "SELECT version FROM flyway_schema_history " +
                            "WHERE success ORDER BY installed_rank DESC LIMIT 1",
                    ).use { rows -> if (rows.next()) rows.getString(1) else null }
                }
            }

            assertEquals(expectedVersion(), applied)
            assertEquals("V${expectedVersion()}", BuildManifest.migrationTarget)
        } finally {
            postgres.stop()
        }
    }

    @Test
    fun `running migrate twice is a no-op rather than an error`() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok")
        val postgres = container()
        postgres.start()
        try {
            Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
            Database.ensureSchema()
            // Yeniden baslatma her deploy'da olur; ikinci calistirma
            // sessizce gecmeli.
            Database.ensureSchema()
        } finally {
            postgres.stop()
        }
    }

    @Test
    fun `a tampered migration checksum stops startup`() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok")
        val postgres = container()
        postgres.start()
        try {
            Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
            Database.ensureSchema()

            // Uygulanmis bir migration'in checksum'ini bozarak dosyanin
            // sonradan degistirilmis olmasini taklit eder.
            DriverManager.getConnection(
                postgres.jdbcUrl, postgres.username, postgres.password,
            ).use { connection ->
                connection.createStatement().use { statement ->
                    statement.executeUpdate(
                        "UPDATE flyway_schema_history SET checksum = checksum + 1 " +
                            "WHERE version = '1'",
                    )
                }
            }

            val error = assertThrows(Exception::class.java) { Database.ensureSchema() }
            assertTrue(
                error.toString().contains("checksum", ignoreCase = true) ||
                    error.toString().contains("validate", ignoreCase = true),
                error.toString(),
            )
        } finally {
            postgres.stop()
        }
    }

    @Test
    fun `a schema newer than this build stops startup`() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok")
        val postgres = container()
        postgres.start()
        try {
            Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
            Database.ensureSchema()

            // Kodun bilmedigi bir surum: eski bir artefaktin yeni bir
            // veritabanina baglanmasi bu sekilde gorunur.
            DriverManager.getConnection(
                postgres.jdbcUrl, postgres.username, postgres.password,
            ).use { connection ->
                connection.createStatement().use { statement ->
                    statement.executeUpdate(
                        """INSERT INTO flyway_schema_history
                           (installed_rank, version, description, type, script,
                            checksum, installed_by, execution_time, success)
                           VALUES (9999, '9999', 'future', 'SQL', 'V9999__future.sql',
                                   0, 'test', 1, true)""",
                    )
                }
            }

            assertThrows(Exception::class.java) { Database.ensureSchema() }
        } finally {
            postgres.stop()
        }
    }
}
