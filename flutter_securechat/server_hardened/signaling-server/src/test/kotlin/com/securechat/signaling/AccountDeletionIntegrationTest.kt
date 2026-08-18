package com.securechat.signaling

import com.securechat.signaling.db.Database
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/**
 * Hesap silmenin atomik, idempotent ve kismi-hataya dayanikli oldugunu
 * kanitlar.
 *
 * Onceki akista commit sonrasi temizlik adimlari korumasiz siralanmisti;
 * aradaki bir hata kalan adimlari atliyor ve istemciye 500 donuyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AccountDeletionIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_deletion_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; hesap silme integration testi atlandi",
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
        Database.close()
        postgres.stop()
    }

    private fun newAccountWithCopies(): String {
        val userId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "INSERT INTO users(user_id, directory_token) VALUES (?::uuid, ?)",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setString(2, "service:test-${UUID.randomUUID()}")
                statement.executeUpdate()
            }
            connection.prepareStatement(
                "INSERT INTO fcm_tokens(user_index, token) VALUES (?, ?)",
            ).use { statement ->
                statement.setString(1, ServerPrivacy.blindIndex("push-user", userId))
                statement.setString(2, "v4:sealed-token")
                statement.executeUpdate()
            }
            connection.prepareStatement(
                """INSERT INTO bot_signal_session(recipient_index, device_id, session_record)
                   VALUES (?, 1, ?)""",
            ).use { statement ->
                statement.setString(1, ServerPrivacy.blindIndex("bot-signal-peer", userId))
                statement.setBytes(2, "sealed-ratchet".toByteArray())
                statement.executeUpdate()
            }
        }
        CredentialState.clearCache()
        return userId
    }

    private fun copyCount(userId: String): Int =
        Database.getConnection().use { connection ->
            var total = 0
            connection.prepareStatement(
                "SELECT COUNT(*) FROM users WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows -> rows.next(); total += rows.getInt(1) }
            }
            connection.prepareStatement(
                "SELECT COUNT(*) FROM fcm_tokens WHERE user_index = ?",
            ).use { statement ->
                statement.setString(1, ServerPrivacy.blindIndex("push-user", userId))
                statement.executeQuery().use { rows -> rows.next(); total += rows.getInt(1) }
            }
            connection.prepareStatement(
                "SELECT COUNT(*) FROM bot_signal_session WHERE recipient_index = ?",
            ).use { statement ->
                statement.setString(1, ServerPrivacy.blindIndex("bot-signal-peer", userId))
                statement.executeQuery().use { rows -> rows.next(); total += rows.getInt(1) }
            }
            total
        }

    @Test
    fun `deletion removes every durable copy in one transaction`() = runBlocking {
        val userId = newAccountWithCopies()
        assertEquals(3, copyCount(userId))
        val token = AuthService.issueToken(userId)

        val result = AccountDeletion.execute(userId, steps = emptyList())

        assertEquals(AccountDeletion.Outcome.DELETED, result.outcome)
        assertEquals(0, copyCount(userId))
        CredentialState.clearCache()
        // Silme aninda hesap authenticate edilemez hale gelir.
        assertNull(AuthService.verifyToken(token))
    }

    @Test
    fun `repeating the request stays successful instead of failing`() = runBlocking {
        val userId = newAccountWithCopies()

        val first = AccountDeletion.execute(userId, steps = emptyList())
        val second = AccountDeletion.execute(userId, steps = emptyList())

        assertEquals(AccountDeletion.Outcome.DELETED, first.outcome)
        assertEquals(AccountDeletion.Outcome.ALREADY_ABSENT, second.outcome)
        assertEquals(0, copyCount(userId))
    }

    @Test
    fun `a failing cleanup step does not skip the remaining steps`() = runBlocking {
        val userId = newAccountWithCopies()
        val ran = mutableListOf<String>()
        val steps = listOf(
            AccountDeletion.PurgeStep("push_cache") { ran += "push_cache" },
            AccountDeletion.PurgeStep("registry") {
                ran += "registry"
                throw IllegalStateException("registry unavailable")
            },
            AccountDeletion.PurgeStep("socket") { ran += "socket" },
            AccountDeletion.PurgeStep("offline_queue") { ran += "offline_queue" },
        )

        val result = AccountDeletion.execute(userId, steps)

        assertEquals(AccountDeletion.Outcome.DELETED, result.outcome)
        assertEquals(0, copyCount(userId))
        // Hata veren adimdan sonrakiler yine calisti.
        assertTrue(ran.contains("socket"))
        assertTrue(ran.contains("offline_queue"))
        assertEquals(listOf("registry"), result.residualSteps)
    }

    @Test
    fun `a transiently failing step is retried until it succeeds`() = runBlocking {
        val userId = newAccountWithCopies()
        val attempts = AtomicInteger()
        val steps = listOf(
            AccountDeletion.PurgeStep("offline_queue") {
                if (attempts.incrementAndGet() < 2) throw IllegalStateException("redis blip")
            },
        )

        val result = AccountDeletion.execute(userId, steps)

        assertEquals(emptyList<String>(), result.residualSteps)
        assertEquals(2, attempts.get())
    }

    @Test
    fun `a durable failure aborts before any copy is removed`() = runBlocking {
        val userId = newAccountWithCopies()
        Database.close()
        try {
            runCatching { AccountDeletion.execute(userId, steps = emptyList()) }
                .also { assertTrue(it.isFailure) }
        } finally {
            Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        }
        // Kalici kayit dokunulmadan durur; istemci yeniden deneyebilir.
        assertEquals(3, copyCount(userId))
    }

    private companion object {
        const val LAST_MIGRATION = 18
    }
}
