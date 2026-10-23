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
        setIdentityColumns(userId, libsignal = false, olm = true)
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
    fun `a new account takes its number back from an abandoned libsignal-only account`() {
        val legacyId = UUID.randomUUID().toString()
        val newId = UUID.randomUUID().toString()
        val token = directory.tokenForPhoneHash(sha256Hex("+905553333333"))
        registry.registerUser(legacyId)
        registry.updateOwnDirectoryToken(legacyId, token)
        setIdentityColumns(legacyId, libsignal = true, olm = false)
        registry.registerUser(newId)

        val claimed = registry.updateOwnDirectoryToken(newId, token)

        assertEquals(token, claimed.directoryToken)
        assertEquals(newId, tokenOwner(token))
        // Eski hesap numarasiz kalir; rehberde artik gorunmez.
        assertTrue(directoryTokenOf(legacyId).startsWith("pending:"))
        assertEquals(
            listOf(newId),
            registry.privateDirectorySnapshot()
                .filter { it.directoryToken == token }
                .map { it.userId },
        )
    }

    @Test
    fun `a number held by an account with an Olm identity or mid-recovery is not taken`() {
        val activeId = UUID.randomUUID().toString()
        val recoveringId = UUID.randomUUID().toString()
        val claimantId = UUID.randomUUID().toString()
        val activeToken = directory.tokenForPhoneHash(sha256Hex("+905554444444"))
        val recoveringToken = directory.tokenForPhoneHash(sha256Hex("+905555555555"))
        registry.registerUser(activeId)
        registry.updateOwnDirectoryToken(activeId, activeToken)
        setIdentityColumns(activeId, libsignal = true, olm = true)
        registry.registerUser(recoveringId)
        registry.updateOwnDirectoryToken(recoveringId, recoveringToken)
        // Kurtarma iki kimlik kolonunu bosaltir ve kurtarma pinini yazar.
        setIdentityColumns(recoveringId, libsignal = false, olm = false)
        setRecoveryPin(recoveringId)
        registry.registerUser(claimantId)

        assertThrows(IllegalArgumentException::class.java) {
            registry.updateOwnDirectoryToken(claimantId, activeToken)
        }
        assertThrows(IllegalArgumentException::class.java) {
            registry.updateOwnDirectoryToken(claimantId, recoveringToken)
        }
        assertEquals(activeId, tokenOwner(activeToken))
        assertEquals(recoveringId, tokenOwner(recoveringToken))
    }

    @Test
    fun `a re-registration takes the number back from its own abandoned attempt`() {
        val abandonedId = UUID.randomUUID().toString()
        val retryId = UUID.randomUUID().toString()
        val token = directory.tokenForPhoneHash(sha256Hex("+905556666666"))
        // Ilk deneme numarayi aldi ama anahtar yukleyemeden yarim kaldi.
        registry.registerUser(abandonedId)
        registry.updateOwnDirectoryToken(abandonedId, token)
        registry.registerUser(retryId)

        registry.updateOwnDirectoryToken(retryId, token)

        assertEquals(retryId, tokenOwner(token))
        assertTrue(directoryTokenOf(abandonedId).startsWith("pending:"))
    }

    @Test
    fun `a retry is not blocked by its abandoned attempt in the snapshot`() {
        val abandonedId = UUID.randomUUID().toString()
        val retryId = UUID.randomUUID().toString()
        val observerId = UUID.randomUUID().toString()
        val token = directory.tokenForPhoneHash(sha256Hex("+905557777777"))
        val label = directory.sealUserId(token, abandonedId).label
        registry.registerUser(abandonedId)
        registry.updateOwnDirectoryToken(abandonedId, token)
        registry.registerUser(retryId)
        registry.registerUser(observerId)
        DirectorySnapshotCache.invalidate()

        // Istemci numarayi listede baskasinda gorurse devir istemeden durur;
        // yarim kalan deneme bu yuzden listede olmamali.
        assertFalse(snapshotLabels(retryId).contains(label))

        registry.updateOwnDirectoryToken(retryId, token)

        // Yeni kayit kendini anahtar yuklemeden once gorur, baskasi gormez.
        assertTrue(snapshotLabels(retryId).contains(label))
        assertFalse(snapshotLabels(observerId).contains(label))
        setIdentityColumns(retryId, libsignal = false, olm = true)
        DirectorySnapshotCache.invalidate()
        assertTrue(snapshotLabels(observerId).contains(label))
        DirectorySnapshotCache.invalidate()
    }

    @Test
    fun `the snapshot etag follows meaning, not the sealed bytes`() {
        val readyId = UUID.randomUUID().toString()
        val keylessId = UUID.randomUUID().toString()
        val token = directory.tokenForPhoneHash(sha256Hex("+905558888888"))
        registry.registerUser(readyId)
        setIdentityColumns(readyId, libsignal = false, olm = true)
        DirectorySnapshotCache.invalidate()

        val first = DirectorySnapshotCache.snapshotFor(readyId, registry, directory)
        DirectorySnapshotCache.invalidate()
        val rebuilt = DirectorySnapshotCache.snapshotFor(readyId, registry, directory)
        assertTrue(first.etag != null)
        assertEquals(first.etag, rebuilt.etag)

        // Yeni bir numara rehbere girince ETag degisir.
        registry.registerUser(keylessId)
        registry.updateOwnDirectoryToken(keylessId, token)
        val changed = DirectorySnapshotCache.snapshotFor(readyId, registry, directory)
        assertNotEquals(first.etag, changed.etag)
        // Kendi kaydi eklenen anahtarsiz hesap paylasilan ETag'i almaz.
        assertEquals(
            null,
            DirectorySnapshotCache.snapshotFor(keylessId, registry, directory).etag,
        )
        DirectorySnapshotCache.invalidate()
    }

    private fun snapshotLabels(requesterId: String): Set<String> =
        DirectorySnapshotCache.entriesFor(requesterId, registry, directory)
            .map { it.label }
            .toSet()

    private fun setRecoveryPin(userId: String) {
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "UPDATE users SET recovery_identity_pin = ? WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setBytes(1, ByteArray(32) { 3 })
                statement.setString(2, userId)
                statement.executeUpdate()
            }
        }
    }

    private fun setIdentityColumns(userId: String, libsignal: Boolean, olm: Boolean) {
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """UPDATE users SET identity_public_key = ?, olm_identity_key = ?,
                       signing_public_key = ?
                   WHERE user_id = ?::uuid""",
            ).use { statement ->
                statement.setBytes(1, if (libsignal) ByteArray(33) { 5 } else null)
                statement.setBytes(2, if (olm) ByteArray(32) { 7 } else null)
                statement.setBytes(3, if (olm) ByteArray(32) { 9 } else null)
                statement.setString(4, userId)
                statement.executeUpdate()
            }
        }
    }

    private fun tokenOwner(token: String): String? =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT user_id::text FROM users WHERE directory_token = ?",
            ).use { statement ->
                statement.setString(1, token)
                statement.executeQuery().use { rows -> if (rows.next()) rows.getString(1) else null }
            }
        }

    private fun directoryTokenOf(userId: String): String =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT directory_token FROM users WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    check(rows.next())
                    rows.getString(1)
                }
            }
        }

    @Test
    fun `v23 schema allows protected recovery but forbids legacy social and plaintext identity links`() {
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
                    "registration_grant_use",
                    "directory_quota",
                    "olm_one_time_prekeys",
                    "olm_fallback_keys",
                    "account_recovery_bindings",
                    "account_recovery_challenges",
                    "account_recovery_quotas",
                    "account_recovery_receipts",
                    // V25: kotuye kullanim bildirimi. Icerik sutunu yok;
                    // bildiren yalniz blind index ile tutulur.
                    "abuse_reports",
                    "abuse_report_targets",
                ),
                tables,
            )
            assertEquals(
                setOf(
                    "report_id",
                    "reporter_index",
                    "kind",
                    "reason",
                    "note",
                    "created_at",
                    "closed_at",
                    "resolution",
                ),
                columns(connection, "abuse_reports"),
            )
            assertEquals(
                setOf("report_id", "target_user_id"),
                columns(connection, "abuse_report_targets"),
            )
            assertEquals(
                setOf(
                    "user_id",
                    "directory_token",
                    "directory_key_id",
                    "identity_public_key",
                    "registration_id",
                    "credential_epoch",
                    "refresh_generation",
                    "recovery_identity_pin",
                    "recovery_identity_protocol",
                    // Olm kimligi ve imza anahtari BURADA, libsignal
                    // kimligiyle ayni satirda: hesabin tek bir kimlik
                    // konumu olmali.
                    "olm_identity_key",
                    "signing_public_key",
                    // V30 kayit kilidi: PIN degil, istemci kanitinin sunucu
                    // anahtarli HMAC'i ve deneme sayaci.
                    "registration_lock_verifier",
                    "registration_lock_failures",
                    "registration_lock_until",
                ),
                columns(connection, "users"),
            )
            assertEquals(
                setOf("account_index", "email_index", "binding_version", "sealed_context"),
                columns(connection, "account_recovery_bindings"),
            )
            assertEquals(
                setOf("challenge_index", "purpose", "account_index", "email_index", "sealed_context", "proof_hash", "attempts", "expires_at"),
                columns(connection, "account_recovery_challenges"),
            )
            assertEquals(
                setOf("quota_index", "used", "expires_at"),
                columns(connection, "account_recovery_quotas"),
            )
            assertEquals(
                setOf("challenge_index", "account_index", "request_hash", "sealed_response", "expires_at"),
                columns(connection, "account_recovery_receipts"),
            )
            assertEquals(
                setOf("id", "user_index", "token", "registered_on"),
                columns(connection, "fcm_tokens"),
            )
            assertEquals(
                setOf("user_id", "key_id", "public_key", "signature"),
                columns(connection, "signed_prekeys"),
            )
            assertEquals(
                setOf("id", "user_id", "key_id", "public_key"),
                columns(connection, "one_time_prekeys"),
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
            // Olm tablolarinda yalniz public materyal bulunur; private key,
            // ciphertext veya tuketim zaman cizelgesi yoktur. `created_at`
            // yalniz satirin YAZILDIGI ani tasir, tuketildigi ani degil:
            // tek kullanimlik anahtar silinerek tuketilir, dolayisiyla
            // PostgreSQL'de bir haberlesme zaman cizgisi olusmaz.
            assertEquals(
                setOf("id", "user_id", "key_id", "public_key", "created_at"),
                columns(connection, "olm_one_time_prekeys"),
            )
            assertEquals(
                setOf("user_id", "public_key", "signature", "created_at"),
                columns(connection, "olm_fallback_keys"),
            )
            // Olm kimligi ve imza anahtari `users` satirinda durur: hesabin
            // TEK bir kimlik konumu olmali. Kaldirilan v2 yolunda kimlik
            // ikinci bir tabloda da tutulabiliyordu ve bu, "oteki
            // namespace'i baslat" saldirisini mumkun kiliyordu.
            assertTrue("olm_identity_key" in columns(connection, "users"))
            assertTrue("signing_public_key" in columns(connection, "users"))
            assertTrue("modern_prekey_bundles" !in tables)
            assertTrue("modern_one_time_prekeys" !in tables)
            assertTrue("modern_last_resort_kyber_prekeys" !in tables)
            assertTrue("group_members" !in tables)
            assertTrue("audit_log" !in tables)
            // Bot API kaldirildi (V29); tablolari geri gelmemeli.
            for (table in listOf(
                "api_client",
                "bot_identity",
                "bot_signal_session",
                "bot_one_time_prekey",
                "bot_signed_prekey",
                "bot_control",
                "bot_peer_identity",
            )) {
                assertTrue(table !in tables, table)
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
