package com.securechat.botapi.db

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.auth.ClientKeyCache
import com.securechat.botapi.delivery.BotQueuePrivacy
import com.securechat.botapi.signal.BotSessionPrivacyMigration
import com.securechat.botapi.signal.BotSessionRecordCipher
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.DockerClientFactory
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.sql.SQLException
import java.util.UUID

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ServerPrivacyMigrationIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_privacy_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private val legacyRecipient = UUID.fromString("123e4567-e89b-42d3-a456-426614174000")
    private val legacySession = "legacy-private-ratchet-record".toByteArray()
    private val kid = "k_migration_fixture"
    private var v14RejectedLegacyRelationship = false

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; PostgreSQL privacy migration integration testi atlandi"
        )
        postgres.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password).use { conn ->
            conn.autoCommit = true
            for (version in 1..3) {
                val migration = Files.list(migrationDir).use { paths ->
                    paths.filter { it.fileName.toString().startsWith("V${version}__") }
                        .findFirst()
                        .orElseThrow()
                }
                conn.createStatement().use { it.execute(Files.readString(migration)) }
            }
            conn.prepareStatement(
                """INSERT INTO api_client(client_id, kid, name, public_key, allow_list)
                   VALUES (?::uuid, ?, ?, ?, ?)"""
            ).use { statement ->
                statement.setString(1, UUID.randomUUID().toString())
                statement.setString(2, kid)
                statement.setString(3, "Private automation")
                statement.setBytes(4, ByteArray(32) { (it + 1).toByte() })
                statement.setArray(
                    5,
                    conn.createArrayOf(
                        "TEXT",
                        arrayOf("user:$legacyRecipient", "group:legacy-private-group")
                    )
                )
                statement.executeUpdate()
            }
            conn.prepareStatement(
                """INSERT INTO bot_signal_session(recipient_user_id, device_id, session_record)
                   VALUES (?::uuid, 1, ?)"""
            ).use { statement ->
                statement.setString(1, legacyRecipient.toString())
                statement.setBytes(2, legacySession)
                statement.executeUpdate()
            }
            val v4 = Files.list(migrationDir).use { paths ->
                paths.filter { it.fileName.toString().startsWith("V4__") }
                    .findFirst()
                    .orElseThrow()
            }
            conn.createStatement().use { it.execute(Files.readString(v4)) }
            for (version in 5..13) {
                val migration = Files.list(migrationDir).use { paths ->
                    paths.filter { it.fileName.toString().startsWith("V${version}__") }
                        .findFirst()
                        .orElseThrow()
                }
                conn.createStatement().use { it.execute(Files.readString(migration)) }
            }

            conn.autoCommit = false
            try {
                applyMigration(conn, migrationDir, 14)
            } catch (_: SQLException) {
                v14RejectedLegacyRelationship = true
                conn.rollback()
            } finally {
                conn.autoCommit = true
            }
        }

        BotApiConfig.databaseUrl = postgres.jdbcUrl
        BotApiConfig.databaseUser = postgres.username
        BotApiConfig.databasePassword = postgres.password
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 41).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 81).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 121).toByte() }
        BotDatabase.init()
        ApiClientPrivacyMigration.migrateAndVerify()

        // Staged V13 conversion: V14 will not silently delete reconstructible
        // ratchet state or its raw compatibility relationship.
        val recipientIndex = BotQueuePrivacy.blindIndex(
            "signal-peer",
            legacyRecipient.toString(),
        )
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """UPDATE bot_signal_session
                   SET recipient_index = ?, recipient_user_id = NULL,
                       session_record = ?
                   WHERE recipient_user_id = ?::uuid AND device_id = 1""",
            ).use { statement ->
                statement.setString(1, recipientIndex)
                statement.setBytes(
                    2,
                    BotSessionRecordCipher.seal(recipientIndex, 1, legacySession),
                )
                statement.setString(3, legacyRecipient.toString())
                assertThat(statement.executeUpdate()).isEqualTo(1)
            }
        }
        BotDatabase.close()
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password).use {
            conn ->
            applyMigration(conn, migrationDir, 14)
            applyMigration(conn, migrationDir, 15)
            applyMigration(conn, migrationDir, 16)
            applyMigration(conn, migrationDir, 17)
            applyMigration(conn, migrationDir, 18)
        }
        BotDatabase.init()
        BotSessionPrivacyMigration.migrateAndVerify()
    }

    @AfterAll
    fun tearDown() {
        BotDatabase.close()
        postgres.stop()
    }

    @Test
    fun `legacy relational metadata and ratchet state become private envelopes`() {
        assertThat(v14RejectedLegacyRelationship).isTrue()
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT name, allow_list FROM api_client WHERE kid = ?"
            ).use { statement ->
                statement.setString(1, kid)
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getString("name")).startsWith("AC1:")
                    assertThat(rows.getString("name")).doesNotContain("Private automation")
                    val allowList = (rows.getArray("allow_list").array as Array<*>)
                        .map { it.toString() }
                    assertThat(allowList).hasSize(1)
                    assertThat(allowList.single()).startsWith("AC1:")
                    assertThat(allowList.single()).doesNotContain(legacyRecipient.toString())
                }
            }

            conn.prepareStatement(
                """SELECT recipient_index, device_id, session_record
                   FROM bot_signal_session"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    val index = rows.getString("recipient_index")
                    assertThat(index).doesNotContain(legacyRecipient.toString())
                    val envelope = rows.getBytes("session_record")
                    assertThat(BotSessionRecordCipher.isSealed(envelope)).isTrue()
                    assertThat(BotSessionRecordCipher.open(index, rows.getInt("device_id"), envelope))
                        .isEqualTo(legacySession)
                }
            }
            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public'
                     AND table_name = 'bot_signal_session'
                     AND column_name = 'recipient_user_id'""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(0)
                }
            }

            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_name = 'users' AND column_name IN ('email', 'email_verified')"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(0)
                }
            }
            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'users'
                     AND column_name IN ('directory_token', 'directory_key_id')"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(2)
                }
            }
            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'users'
                     AND column_name = 'phone_hash'"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(0)
                }
            }
            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.tables
                   WHERE table_schema = 'public'
                     AND table_name IN ('group_members', 'audit_log')"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(0)
                }
            }
            conn.prepareStatement(
                """SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = 'public'
                     AND table_name IN ('one_time_prekeys', 'signed_prekeys')
                     AND column_name IN ('consumed_at', 'created_at')"""
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    assertThat(rows.next()).isTrue()
                    assertThat(rows.getInt(1)).isEqualTo(0)
                }
            }
        }
    }

    @Test
    fun `repository decrypts only through authenticated field bindings`() {
        val client = ApiClientRepository.findActiveByKid(kid)
        assertThat(client).isNotNull()
        assertThat(client!!.name).isEqualTo("Private automation")
        assertThat(client.allowList).containsExactly(
            "user:$legacyRecipient",
            "group:legacy-private-group"
        )
        assertThat(BotQueuePrivacy.blindIndex("signal-peer", legacyRecipient.toString()))
            .isEqualTo("Q9yhE-3QYfEAfTg_j5L8la0Z-eZjWvSv7suBOSCzb0Y")
    }

    @Test
    fun `credential lookup rechecks revocation and never serves a positive RAM cache`() {
        val cacheKid = ApiClientRepository.create(
            name = "Immediate revocation fixture",
            publicKey = ByteArray(32) { (it + 11).toByte() },
            allowList = listOf("user:$legacyRecipient"),
        )
        assertThat(ClientKeyCache.get(cacheKid)).isNotNull()

        assertThat(ApiClientRepository.revoke(cacheKid, "compromised")).isTrue()

        assertThat(ClientKeyCache.get(cacheKid)).isNull()
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
}
