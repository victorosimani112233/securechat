package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPrivateCrtKey
import java.sql.DriverManager
import java.util.Base64
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PrivateDirectoryRegistryIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_directory_privacy_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val legacyUserId = "123e4567-e89b-42d3-a456-426614174100"
    private val legacyHash = sha256Hex("+905551111111")
    private val legacyIndex: (String) -> String = { "legacy-$it" }
    private lateinit var directory: PrivateDirectoryOprf
    private lateinit var registry: UserRegistry
    private var started = false

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; private directory PostgreSQL testi atlandi",
        )
        postgres.start()
        started = true
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password).use {
            connection ->
            val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
            for (version in 1..LAST_MIGRATION) {
                val migration = Files.list(migrationDir).use { paths ->
                    paths.filter { it.fileName.toString().startsWith("V${version}__") }
                        .findFirst()
                        .orElseThrow()
                }
                connection.createStatement().use { statement ->
                    statement.execute(Files.readString(migration))
                }
            }
            connection.prepareStatement(
                """INSERT INTO users (user_id, directory_token, directory_key_id)
                   VALUES (?::uuid, ?, NULL)""",
            ).use { statement ->
                statement.setString(1, legacyUserId)
                statement.setString(2, legacyIndex(legacyHash))
                statement.executeUpdate()
            }
        }
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(3072)
        directory = PrivateDirectoryOprf.forTest(
            generator.generateKeyPair().private as RSAPrivateCrtKey,
        )
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        registry = UserRegistry(directory)
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        if (started) postgres.stop()
    }

    @Test
    fun `authenticated legacy owner migration leaves only current OPRF token`() {
        val migrated = registry.updateOwnDirectoryToken(
            legacyUserId,
            directory.tokenForPhoneHash(legacyHash),
        )

        assertEquals(directory.keyId, migrated.directoryKeyId)
        assertEquals(directory.tokenForPhoneHash(legacyHash), migrated.directoryToken)
        assertNotEquals(legacyIndex(legacyHash), migrated.directoryToken)
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT directory_token, directory_key_id
                   FROM users WHERE user_id = ?::uuid""",
            ).use { statement ->
                statement.setString(1, legacyUserId)
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertEquals(migrated.directoryToken, rows.getString("directory_token"))
                    assertEquals(directory.keyId, rows.getString("directory_key_id"))
                    assertFalse(rows.next())
                }
            }
        }
    }

    @Test
    fun `an authenticated account cannot claim another account directory token`() {
        val userId = UUID.randomUUID().toString()
        val attackerId = UUID.randomUUID().toString()
        val phoneHash = sha256Hex("+905552222222")

        val token = directory.tokenForPhoneHash(phoneHash)
        val created = registry.registerUser(userId)
        registry.updateOwnDirectoryToken(userId, token)
        registry.registerUser(attackerId)

        assertEquals(userId, created.userId)
        assertThrows(IllegalArgumentException::class.java) {
            registry.updateOwnDirectoryToken(attackerId, token)
        }
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM users WHERE directory_token = ?",
            ).use { statement ->
                statement.setString(1, token)
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    assertEquals(1, rows.getInt(1))
                }
            }
        }
    }

    @Test
    fun `v22 final schema structurally forbids legacy social and identity links`() {
        Database.getConnection().use { connection ->
            val tables = connection.prepareStatement(
                """SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'public' AND table_type = 'BASE TABLE'""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    buildSet {
                        while (rows.next()) add(rows.getString(1))
                    }
                }
            }
            assertEquals(
                setOf(
                    "users",
                    "fcm_tokens",
                    "signed_prekeys",
                    "one_time_prekeys",
                    "api_client",
                    "bot_identity",
                    "bot_signal_session",
                    "bot_one_time_prekey",
                    "bot_signed_prekey",
                    "bot_control",
                    "bot_peer_identity",
                    "registration_grant_use",
                    "directory_quota",
                    "modern_prekey_bundles",
                    "modern_one_time_prekeys",
                    "modern_last_resort_kyber_prekeys",
                    "sealed_sender_mailboxes",
                    // Emekli mailbox tombstone'u: yalniz HMAC indeksi ve sona
                    // erme zamani; hesap bagi tasimadigi icin sosyal grafik
                    // yuzeyi olusturmaz.
                    "sealed_sender_retired_mailboxes",
                ),
                tables,
            )
            // Tombstone hicbir kosulda bir hesaba geri baglanmamalidir.
            val retiredColumns = connection.prepareStatement(
                """SELECT column_name FROM information_schema.columns
                   WHERE table_schema = 'public'
                     AND table_name = 'sealed_sender_retired_mailboxes'""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    buildSet { while (rows.next()) add(rows.getString(1)) }
                }
            }
            assertEquals(setOf("mailbox_index", "retired_until"), retiredColumns)
            assertEquals(
                setOf(
                    "user_id",
                    "directory_token",
                    "directory_key_id",
                    "identity_public_key",
                    "registration_id",
                    "credential_epoch",
                    "refresh_generation",
                ),
                columns(connection, "users"),
            )
            assertEquals(
                setOf("id", "user_index", "token", "registered_on"),
                columns(connection, "fcm_tokens"),
            )
            assertEquals(
                setOf("recipient_index", "device_id", "session_record"),
                columns(connection, "bot_signal_session"),
            )
            assertEquals(
                setOf("user_id", "mailbox_index", "write_key_index", "protocol_version", "generation"),
                columns(connection, "sealed_sender_mailboxes"),
            )
            assertEquals(
                setOf("user_id", "key_id", "public_key", "signature"),
                columns(connection, "signed_prekeys"),
            )
            assertEquals(
                setOf("id", "user_id", "key_id", "public_key"),
                columns(connection, "one_time_prekeys"),
            )
            assertEquals(
                setOf(
                    "client_id",
                    "kid",
                    "name",
                    "public_key",
                    "allow_list",
                    "rate_per_hour",
                    "per_recipient_per_day",
                    "expires_at",
                    "revoked_at",
                    "revoke_reason",
                    "created_at",
                    "updated_at",
                ),
                columns(connection, "api_client"),
            )
            assertEquals(
                setOf(
                    "id",
                    "bot_user_id",
                    "registration_id",
                    "identity_public_key",
                    "identity_private_key_enc",
                    "identity_private_key_nonce",
                    "created_at",
                    "rotated_at",
                ),
                columns(connection, "bot_identity"),
            )
            assertEquals(
                setOf(
                    "key_id",
                    "public_key",
                    "private_key_enc",
                    "private_key_nonce",
                    "consumed_at",
                    "created_at",
                ),
                columns(connection, "bot_one_time_prekey"),
            )
            assertEquals(
                setOf(
                    "key_id",
                    "public_key",
                    "private_key_enc",
                    "private_key_nonce",
                    "signature",
                    "created_at",
                ),
                columns(connection, "bot_signed_prekey"),
            )
            // Operator kontrolu; hesap, zaman veya iliski verisi tasimaz.
            assertEquals(
                setOf("id", "emergency_stop"),
                columns(connection, "bot_control"),
            )
            // Identity pini: blind index + muhurlu public anahtar; ham UUID
            // ve zaman damgasi yok.
            assertEquals(
                setOf("recipient_index", "device_id", "identity_key_sealed"),
                columns(connection, "bot_peer_identity"),
            )
            // Tek kullanimlik grant isareti: hesap/e-posta/telefon referansi
            // tasimaz, yalniz blind index ve replay penceresi.
            assertEquals(
                setOf("grant_index", "expires_at"),
                columns(connection, "registration_grant_use"),
            )
            // Rehber kotasi: blind index, gun kovasi ve sayac. Ham hesap
            // kimligi ya da istek zaman cizelgesi tutulmaz.
            assertEquals(
                setOf("account_index", "day_bucket", "used", "updated_at"),
                columns(connection, "directory_quota"),
            )
            // Modern libsignal tablolarinda yalniz public PQXDH materyali
            // bulunur; private key, ciphertext veya tuketim zaman cizelgesi yoktur.
            assertEquals(
                setOf(
                    "user_id",
                    "identity_public_key",
                    "registration_id",
                    "signed_prekey_id",
                    "signed_prekey_public",
                    "signed_prekey_signature",
                ),
                columns(connection, "modern_prekey_bundles"),
            )
            assertEquals(
                setOf(
                    "user_id",
                    "key_id",
                    "ec_public_key",
                    "kyber_public_key",
                    "kyber_signature",
                ),
                columns(connection, "modern_one_time_prekeys"),
            )
            assertEquals(
                setOf("user_id", "key_id", "public_key", "signature"),
                columns(connection, "modern_last_resort_kyber_prekeys"),
            )
            assertTrue("group_members" !in tables)
            assertTrue("audit_log" !in tables)
        }
    }

    @Test
    fun `retention removes expired and revoked bot policies without identity logs`() {
        Database.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.execute(
                    """INSERT INTO api_client
                       (kid, name, public_key, allow_list, expires_at, revoked_at)
                       VALUES
                       ('k_active', 'AC1:active', decode(repeat('01', 32), 'hex'), ARRAY[]::text[], NULL, NULL),
                       ('k_recent_revoked', 'AC1:recent', decode(repeat('02', 32), 'hex'), ARRAY[]::text[], NULL, NOW() - INTERVAL '1 day'),
                       ('k_old_revoked', 'AC1:old-r', decode(repeat('03', 32), 'hex'), ARRAY[]::text[], NULL, NOW() - INTERVAL '31 days'),
                       ('k_old_expired', 'AC1:old-e', decode(repeat('04', 32), 'hex'), ARRAY[]::text[], NOW() - INTERVAL '31 days', NULL)""",
                )
            }
        }
        val config = PrivacyConfig.fromEnvironment(
            mapOf(
                "PRIVACY_INDEX_KEY" to Base64.getEncoder().encodeToString(
                    ByteArray(32) { (it + 1).toByte() },
                ),
                "OFFLINE_QUEUE_ENCRYPTION_KEY" to Base64.getEncoder().encodeToString(
                    ByteArray(32) { (it + 71).toByte() },
                ),
                "API_CLIENT_RETENTION_DAYS" to "30",
            ),
        )

        val result = PrivacyRetentionWorker.runOnce(config)

        assertEquals(2, result.apiClientRows)
        Database.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("SELECT kid FROM api_client ORDER BY kid").use { rows ->
                    val remaining = buildList {
                        while (rows.next()) add(rows.getString(1))
                    }
                    assertEquals(listOf("k_active", "k_recent_revoked"), remaining)
                }
            }
        }
    }

    private fun columns(connection: java.sql.Connection, table: String): Set<String> =
        connection.prepareStatement(
            """SELECT column_name FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = ?""",
        ).use { statement ->
            statement.setString(1, table)
            statement.executeQuery().use { rows ->
                buildSet {
                    while (rows.next()) add(rows.getString(1))
                }
            }
        }

    private fun sha256Hex(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    companion object {
        /**
         * Migration sayisi kaynagindan okunur.
         *
         * Sabit bir sayi, yeni bir migration eklendiginde testleri sessizce
         * eski semaya karsi calistirirdi.
         */
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
    }
}
