package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.sql.SQLException
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

/**
 * Kotuye kullanim bildirimleri: dogrulama, saklama, inceleme ve silme.
 *
 * Bildirim icerik tasimaz; bu test bilinmeyen alan reddini ve saklama
 * sinirlarini da kanitlar.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AbuseReportsIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_abuse_reports_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; bildirim integration testi atlandi",
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

    private val reporter = UUID.randomUUID().toString()

    private fun valid(vararg targets: String, reason: String = "spam", note: String? = null) =
        AbuseReports.validate(
            AbuseReports.SubmitRequest("user", targets.toList(), reason, note),
            reporter,
        ) { true } as AbuseReports.Validation.Valid

    private fun reportsFor(target: String) =
        AbuseReports.list(openOnly = false).filter { target in it.targetUserIds }

    @Test
    fun `validation rejects bad input and the reporter as target`() {
        val target = UUID.randomUUID().toString()
        fun check(request: AbuseReports.SubmitRequest) =
            AbuseReports.validate(request, reporter) { it == target }

        assertEquals(
            AbuseReports.Validation.Invalid("invalid_reason"),
            check(AbuseReports.SubmitRequest("user", listOf(target), "content")),
        )
        assertEquals(
            AbuseReports.Validation.Invalid("invalid_kind"),
            check(AbuseReports.SubmitRequest("message", listOf(target), "spam")),
        )
        assertEquals(
            AbuseReports.Validation.Invalid("invalid_targets"),
            check(AbuseReports.SubmitRequest("user", listOf("not-a-uuid"), "spam")),
        )
        assertEquals(
            AbuseReports.Validation.Invalid("invalid_targets"),
            check(AbuseReports.SubmitRequest("group", List(33) { target }, "spam")),
        )
        assertEquals(
            AbuseReports.Validation.Invalid("unknown_targets"),
            check(AbuseReports.SubmitRequest("user", listOf(reporter), "spam")),
        )
        assertEquals(
            AbuseReports.Validation.Invalid("note_too_long"),
            check(AbuseReports.SubmitRequest("user", listOf(target), "spam", "x".repeat(501))),
        )
        val unknown = UUID.randomUUID().toString()
        val result = check(
            AbuseReports.SubmitRequest("group", listOf(target, unknown, reporter), "other", " \u0000hi\n "),
        ) as AbuseReports.Validation.Valid
        assertEquals(listOf(target), result.targets)
        assertEquals("hi", result.note)
    }

    @Test
    fun `stored report is listed without reporter identity and can be closed once`() {
        val target = UUID.randomUUID().toString()
        val id = AbuseReports.store(valid(target, reason = "child_safety", note = "n"), reporter)

        val view = reportsFor(target).single()
        assertEquals(id, view.reportId)
        assertEquals("child_safety", view.reason)
        assertEquals(listOf(target), view.targetUserIds)
        assertTrue(AbuseReports.list(openOnly = true).any { it.reportId == id })

        assertTrue(AbuseReports.close(id, "no_action"))
        assertFalse(AbuseReports.close(id, "no_action"), "kapali rapor tekrar kapanmaz")
        assertFalse(AbuseReports.list(openOnly = true).any { it.reportId == id })
        assertEquals("no_action", reportsFor(target).single().resolution)
        assertFalse(AbuseReports.close("not-a-uuid", "no_action"))
    }

    @Test
    fun `schema refuses content-like or malformed rows`() {
        Database.getConnection().use { connection ->
            assertThrows(SQLException::class.java) {
                connection.prepareStatement(
                    "INSERT INTO abuse_reports(report_id, kind, reason, note) VALUES (?::uuid, 'user', 'spam', ?)",
                ).use {
                    it.setString(1, UUID.randomUUID().toString())
                    it.setString(2, "x".repeat(501))
                    it.executeUpdate()
                }
            }
            assertThrows(SQLException::class.java) {
                connection.prepareStatement(
                    "INSERT INTO abuse_reports(report_id, kind, reason, closed_at) VALUES (?::uuid, 'user', 'spam', NOW())",
                ).use {
                    it.setString(1, UUID.randomUUID().toString())
                    it.executeUpdate()
                }
            }
        }
    }

    @Test
    fun `account deletion drops targets and detaches the reporter`() {
        val deletedTarget = UUID.randomUUID().toString()
        val other = UUID.randomUUID().toString()
        val leavingReporter = UUID.randomUUID().toString()
        AbuseReports.store(valid(deletedTarget, other), reporter)
        val byLeaver = AbuseReports.store(
            AbuseReports.validate(
                AbuseReports.SubmitRequest("user", listOf(other), "harassment"),
                leavingReporter,
            ) { true } as AbuseReports.Validation.Valid,
            leavingReporter,
        )

        Database.getConnection().use { connection ->
            AbuseReports.deleteAccount(connection, deletedTarget)
            AbuseReports.deleteAccount(connection, leavingReporter)
        }

        assertTrue(reportsFor(deletedTarget).isEmpty())
        assertEquals(2, reportsFor(other).size, "baska hesaba dair bildirim kalir")
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT reporter_index FROM abuse_reports WHERE report_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, byLeaver)
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertNull(rows.getString(1))
                }
            }
        }
    }

    @Test
    fun `retention removes old closed and very old open reports only`() {
        val target = UUID.randomUUID().toString()
        val recentOpen = AbuseReports.store(valid(target), reporter)
        val recentClosed = AbuseReports.store(valid(target), reporter)
        val oldClosed = AbuseReports.store(valid(target), reporter)
        val ancientOpen = AbuseReports.store(valid(target), reporter)
        AbuseReports.close(recentClosed, "no_action")
        AbuseReports.close(oldClosed, "account_removed")
        Database.getConnection().use { connection ->
            fun age(id: String, column: String, days: Int) =
                connection.prepareStatement(
                    "UPDATE abuse_reports SET $column = NOW() - (? * INTERVAL '1 day') WHERE report_id = ?::uuid",
                ).use {
                    it.setInt(1, days)
                    it.setString(2, id)
                    it.executeUpdate()
                }
            age(oldClosed, "closed_at", AbuseReports.CLOSED_RETENTION_DAYS + 1)
            age(ancientOpen, "created_at", AbuseReports.MAX_RETENTION_DAYS + 1)

            assertTrue(AbuseReports.purgeExpired(connection) >= 2)
        }

        val remaining = reportsFor(target).map { it.reportId }.toSet()
        assertEquals(setOf(recentOpen, recentClosed), remaining)
    }

    private companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
    }
}
