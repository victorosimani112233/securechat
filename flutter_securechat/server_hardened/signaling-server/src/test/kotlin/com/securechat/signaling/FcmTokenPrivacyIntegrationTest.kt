package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.sql.SQLException
import java.sql.Timestamp
import java.util.Base64
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.MethodOrderer
import org.junit.jupiter.api.Order
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.junit.jupiter.api.TestMethodOrder
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.OrderAnnotation::class)
class FcmTokenPrivacyIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_push_privacy_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val encryptionKey = ByteArray(32) { (it + 17).toByte() }
    private val cipher = FcmTokenCipher(encryptionKey)
    private val privacyConfig = PrivacyConfig.fromEnvironment(
        mapOf(
            "PRIVACY_INDEX_KEY" to Base64.getEncoder().encodeToString(
                ByteArray(32) { (it + 71).toByte() },
            ),
            "OFFLINE_QUEUE_ENCRYPTION_KEY" to Base64.getEncoder().encodeToString(
                ByteArray(32) { (it + 121).toByte() },
            ),
        ),
    )
    private val privacy = PrivacyPrimitives(privacyConfig)
    private val now = System.currentTimeMillis()
    private val privateUser = UUID.fromString("123e4567-e89b-42d3-a456-426614174010")
    private val stagedUser = UUID.fromString("123e4567-e89b-42d3-a456-426614174011")
    private val staleUser = UUID.fromString("123e4567-e89b-42d3-a456-426614174012")
    private val corruptUser = UUID.fromString("123e4567-e89b-42d3-a456-426614174013")
    private val newUser = UUID.fromString("123e4567-e89b-42d3-a456-426614174014")
    private val privateToken = "fcm_registration_token:private-v4-0000000001"
    private val stagedToken = "fcm_registration_token:staged-v4-0000000002"
    private val staleToken = "fcm_registration_token:expired-v4-0000000003"
    private val newToken = "fcm_registration_token:new-private-row-00004"
    private lateinit var store: FcmTokenStore
    private var started = false
    private var v14RejectedLegacyRelationship = false

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; PostgreSQL push privacy integration testi atlandi",
        )
        postgres.start()
        started = true

        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password).use {
            connection ->
            val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
            for (version in 1..5) applyMigration(connection, migrationDir, version)

            insertPrivate(
                connection,
                privateUser,
                privateToken,
                Timestamp(now - 1_000),
            )
            insertPrivate(
                connection,
                staleUser,
                staleToken,
                Timestamp(now - 181L * MILLIS_PER_DAY),
            )
            connection.prepareStatement(
                """INSERT INTO fcm_tokens(user_id, user_index, token, updated_at)
                   VALUES (NULL, ?, 'v4:not-valid-base64', ?)""",
            ).use { statement ->
                statement.setString(1, indexFor(corruptUser))
                statement.setTimestamp(2, Timestamp(now - 3_000))
                statement.executeUpdate()
            }
            insertRawCompatibilityRow(connection, stagedUser, stagedToken)
            for (version in 6..13) applyMigration(connection, migrationDir, version)

            // V14 must not silently discard a legacy account relationship.
            connection.autoCommit = false
            try {
                applyMigration(connection, migrationDir, 14)
            } catch (_: SQLException) {
                v14RejectedLegacyRelationship = true
                connection.rollback()
            } finally {
                connection.autoCommit = true
            }
            check(v14RejectedLegacyRelationship) { "V14 accepted a raw push-token user UUID" }

            // This models the documented staged V13 conversion. Only after
            // every row is opaque and v4-sealed may V14 remove the column.
            connection.prepareStatement(
                """UPDATE fcm_tokens
                   SET user_id = NULL, user_index = ?, token = ?
                   WHERE user_id = ?::uuid""",
            ).use { statement ->
                val index = indexFor(stagedUser)
                statement.setString(1, index)
                statement.setString(2, cipher.seal(index, stagedToken))
                statement.setString(3, stagedUser.toString())
                assertEquals(1, statement.executeUpdate())
            }
            applyMigration(connection, migrationDir, 14)
            applyMigration(connection, migrationDir, 15)
            applyMigration(connection, migrationDir, 16)
            applyMigration(connection, migrationDir, 17)
            applyMigration(connection, migrationDir, 18)
        }

        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        store = FcmTokenStore(
            cipher = cipher,
            retentionDays = 90,
            userIndexProvider = { privacy.blindIndex("push-user", it) },
            nowMillis = { now },
        )
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        if (started) postgres.stop()
    }

    @Test
    @Order(1)
    fun `v14 refuses legacy links then leaves only opaque indexes and v4 ciphertext`() {
        assertTrue(v14RejectedLegacyRelationship)
        assertEquals(privateToken, store.getToken(privateUser.toString()))
        assertEquals(stagedToken, store.getToken(stagedUser.toString()))
        assertNull(store.getToken(staleUser.toString()))
        assertNull(store.getToken(corruptUser.toString()))
        assertEquals(2, store.getTokenCount())

        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT user_index, token, registered_on FROM fcm_tokens ORDER BY id",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    var count = 0
                    while (rows.next()) {
                        count++
                        val index = rows.getString("user_index")
                        val encrypted = rows.getString("token")
                        assertEquals(43, index.length)
                        assertTrue(encrypted.startsWith("v4:"))
                        assertFalse(encrypted.contains("fcm_registration_token"))
                        assertFalse(index.contains(privateUser.toString()))
                        assertFalse(index.contains(stagedUser.toString()))
                        assertTrue(rows.getDate("registered_on") != null)
                    }
                    assertEquals(2, count)
                }
            }
            assertColumnAbsent(connection, "fcm_tokens", "user_id")
        }
    }

    @Test
    @Order(2)
    fun `new writes are private bounded and removable`() {
        store.registerToken(newUser.toString(), newToken)
        assertEquals(newToken, store.getToken(newUser.toString()))

        Database.getConnection().use { connection ->
            assertColumnAbsent(connection, "fcm_tokens", "updated_at")
            connection.prepareStatement(
                "SELECT token FROM fcm_tokens WHERE user_index = ?",
            ).use { statement ->
                statement.setString(1, indexFor(newUser))
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertTrue(rows.getString("token").startsWith("v4:"))
                    assertFalse(rows.getString("token").contains(newToken))
                }
            }
        }

        store.removeToken(newUser.toString())
        assertNull(store.getToken(newUser.toString()))
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM fcm_tokens WHERE user_index = ?",
            ).use { statement ->
                statement.setString(1, indexFor(newUser))
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertEquals(0, rows.getInt(1))
                }
            }
        }
    }

    @Test
    @Order(3)
    fun `ciphertext cannot be reassigned and memory obeys retention cutoff`() {
        val firstIndex = indexFor(privateUser)
        val secondIndex = indexFor(stagedUser)
        val envelope = cipher.seal(firstIndex, privateToken)
        assertEquals(privateToken, cipher.openV4(firstIndex, envelope))
        assertNull(cipher.openV4(secondIndex, envelope))

        store.purgeExpiredMemory(now + 1)
        assertNull(store.getToken(privateUser.toString()))
        assertNull(store.getToken(stagedUser.toString()))
        assertEquals(0, store.getTokenCount())
    }

    private fun applyMigration(
        connection: java.sql.Connection,
        migrationDir: Path,
        version: Int,
    ) {
        val migration = Files.list(migrationDir).use { paths ->
            paths.filter { it.fileName.toString().startsWith("V${version}__") }
                .findFirst()
                .orElseThrow()
        }
        connection.createStatement().use { it.execute(Files.readString(migration)) }
    }

    private fun insertPrivate(
        connection: java.sql.Connection,
        userId: UUID,
        token: String,
        updatedAt: Timestamp,
    ) {
        val index = indexFor(userId)
        connection.prepareStatement(
            """INSERT INTO fcm_tokens(user_id, user_index, token, updated_at)
               VALUES (NULL, ?, ?, ?)""",
        ).use { statement ->
            statement.setString(1, index)
            statement.setString(2, cipher.seal(index, token))
            statement.setTimestamp(3, updatedAt)
            statement.executeUpdate()
        }
    }

    private fun insertRawCompatibilityRow(
        connection: java.sql.Connection,
        userId: UUID,
        token: String,
    ) {
        connection.prepareStatement(
            "INSERT INTO fcm_tokens(user_id, token, updated_at) VALUES (?::uuid, ?, ?)",
        ).use { statement ->
            statement.setString(1, userId.toString())
            statement.setString(2, token)
            statement.setTimestamp(3, Timestamp(now - 2_000))
            statement.executeUpdate()
        }
    }

    private fun assertColumnAbsent(
        connection: java.sql.Connection,
        table: String,
        column: String,
    ) {
        connection.prepareStatement(
            """SELECT COUNT(*) FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = ? AND column_name = ?""",
        ).use { statement ->
            statement.setString(1, table)
            statement.setString(2, column)
            statement.executeQuery().use { rows ->
                assertTrue(rows.next())
                assertEquals(0, rows.getInt(1))
            }
        }
    }

    private fun indexFor(userId: UUID): String =
        privacy.blindIndex("push-user", userId.toString())

    companion object {
        private const val MILLIS_PER_DAY = 86_400_000L
    }
}
