package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotDatabase
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.MethodOrderer
import org.junit.jupiter.api.Order
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.junit.jupiter.api.TestMethodOrder
import org.junit.jupiter.api.assertThrows
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.time.Instant

/**
 * Bot bootstrap'inin final V1-V18 semasi uzerinde calistigini ve yarim kalan
 * adimlarin restart'ta tamamlandigini kanitlar.
 *
 * Testler tek container uzerinde sirayla calisir; her biri bir onceki
 * calistirmanin biraktigi durumu devralir. Bu, gercek restart senaryosunun
 * kendisidir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.OrderAnnotation::class)
class BotIdentityBootstrapIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_bootstrap_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    /**
     * Signaling `/api/v1/prekeys/upload` route'unun DB etkisini taklit eder:
     * identity replace, signed prekey replace, one-time prekey'ler
     * `ON CONFLICT DO NOTHING`.
     */
    private class FakePublisher : BotBundlePublisher {
        var publishCount = 0
        var publishedOneTimeIds = emptyList<Int>()
        var publishedSignedPreKeyId = 0
        var publishedSignedPreKey = ByteArray(0)
        var failNext = false

        override fun publish(bundle: PublishedBundle) {
            if (failNext) {
                failNext = false
                throw IllegalStateException("PreKey upload basarisiz: HTTP 503")
            }
            publishCount++
            publishedOneTimeIds = bundle.oneTimePreKeys.map { it.keyId }
            publishedSignedPreKeyId = bundle.signedPreKeyId
            publishedSignedPreKey = bundle.signedPreKey.copyOf()
            BotDatabase.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    conn.prepareStatement(
                        "UPDATE users SET identity_public_key = ?, registration_id = ? " +
                            "WHERE user_id = ?::uuid",
                    ).use { statement ->
                        statement.setBytes(1, bundle.identityPublicKey)
                        statement.setInt(2, bundle.registrationId)
                        statement.setString(3, bundle.botUserId)
                        statement.executeUpdate()
                    }
                    conn.prepareStatement(
                        "DELETE FROM signed_prekeys WHERE user_id = ?::uuid",
                    ).use { statement ->
                        statement.setString(1, bundle.botUserId)
                        statement.executeUpdate()
                    }
                    conn.prepareStatement(
                        "INSERT INTO signed_prekeys (user_id, key_id, public_key, signature) " +
                            "VALUES (?::uuid, ?, ?, ?)",
                    ).use { statement ->
                        statement.setString(1, bundle.botUserId)
                        statement.setInt(2, bundle.signedPreKeyId)
                        statement.setBytes(3, bundle.signedPreKey)
                        statement.setBytes(4, bundle.signedPreKeySignature)
                        statement.executeUpdate()
                    }
                    for (preKey in bundle.oneTimePreKeys) {
                        conn.prepareStatement(
                            "INSERT INTO one_time_prekeys (user_id, key_id, public_key) " +
                                "VALUES (?::uuid, ?, ?) ON CONFLICT (user_id, key_id) DO NOTHING",
                        ).use { statement ->
                            statement.setString(1, bundle.botUserId)
                            statement.setInt(2, preKey.keyId)
                            statement.setBytes(3, preKey.publicKey)
                            statement.executeUpdate()
                        }
                    }
                    conn.commit()
                } catch (e: Exception) {
                    conn.rollback()
                    throw e
                } finally {
                    conn.autoCommit = true
                }
            }
        }
    }

    private val publisher = FakePublisher()

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; bot bootstrap integration testi atlandi",
        )
        postgres.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password)
            .use { conn ->
                conn.autoCommit = true
                for (version in 1..LAST_MIGRATION) {
                    val migration = Files.list(migrationDir).use { paths ->
                        paths.filter { it.fileName.toString().startsWith("V${version}__") }
                            .findFirst()
                            .orElseThrow()
                    }
                    conn.createStatement().use { it.execute(Files.readString(migration)) }
                }
            }

        BotApiConfig.databaseUrl = postgres.jdbcUrl
        BotApiConfig.databaseUser = postgres.username
        BotApiConfig.databasePassword = postgres.password
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 7).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 47).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 97).toByte() }
        BotDatabase.init()
    }

    @AfterAll
    fun tearDown() {
        BotDatabase.close()
        postgres.stop()
    }

    @Test
    @Order(1)
    fun `remote publish failure leaves the bot un-ready instead of half registered`() {
        publisher.failNext = true

        assertThrows<IllegalStateException> {
            BotIdentityBootstrap.ensureRegistered(publisher)
        }

        assertThat(BotIdentity.isReady()).isFalse()
        assertThat(countRows("bot_identity")).isEqualTo(1)
        assertThat(countRows("users")).isEqualTo(1)
        // Kimlik commit edildi, yayin tamamlanmadi: server tarafi bos kalmali.
        assertThat(countRows("signed_prekeys")).isEqualTo(0)
        assertThat(countRows("one_time_prekeys")).isEqualTo(0)
    }

    @Test
    @Order(2)
    fun `restart reconciles the half finished bootstrap without a second identity`() {
        val identityBefore = singleBotUserId()

        BotIdentityBootstrap.ensureRegistered(publisher)

        assertThat(publisher.publishCount).isEqualTo(1)
        assertThat(singleBotUserId()).isEqualTo(identityBefore)
        assertThat(countRows("bot_identity")).isEqualTo(1)
        assertThat(countRows("users")).isEqualTo(1)
        assertThat(countRows("bot_signed_prekey")).isEqualTo(1)
        assertThat(countRows("bot_one_time_prekey")).isEqualTo(ONE_TIME_POOL)
        assertThat(countRows("signed_prekeys")).isEqualTo(1)
        assertThat(countRows("one_time_prekeys")).isEqualTo(ONE_TIME_POOL)
        assertThat(BotIdentity.isReady()).isTrue()
        assertThat(BotIdentity.get().botUserId).isEqualTo(identityBefore)
    }

    @Test
    @Order(3)
    fun `a fully provisioned bot republishes nothing on the next start`() {
        val identityBefore = singleBotUserId()

        BotIdentityBootstrap.ensureRegistered(publisher)

        assertThat(publisher.publishCount).isEqualTo(1)
        assertThat(singleBotUserId()).isEqualTo(identityBefore)
        assertThat(countRows("one_time_prekeys")).isEqualTo(ONE_TIME_POOL)
        assertThat(BotIdentity.isReady()).isTrue()
    }

    @Test
    @Order(4)
    fun `service account stays outside the private directory namespace`() {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("SELECT directory_token, directory_key_id FROM users")
                .use { statement ->
                    statement.executeQuery().use { rows ->
                        assertThat(rows.next()).isTrue()
                        val token = rows.getString("directory_token")
                        // OPRF tokenlari url-safe base64'tur ve ':' icermez.
                        // Ayri namespace bu satirin bir telefon kimligiyle
                        // karistirilmasini yapisal olarak imkansiz kilar.
                        assertThat(token).startsWith("service:")
                        // Snapshot yalniz aktif key id tasiyan satirlari yayinlar.
                        assertThat(rows.getString("directory_key_id")).isNull()
                        assertThat(rows.next()).isFalse()
                    }
                }
        }
    }

    @Test
    @Order(5)
    fun `keys consumed by a peer are never republished and the pool is refilled`() {
        // Bir peer bundle cekti: server tarafi o one-time prekey'i atomik sildi,
        // fakat bot henuz PreKeySignalMessage almadigi icin local satir hala
        // "unconsumed" gorunuyor. Bu anahtar ikinci kez yayinlanamaz.
        val consumed = lowestServerOneTimeKeyIds(3)
        deleteServerOneTimeKeys(consumed)
        val highestBefore = maxKeyId("bot_one_time_prekey")

        BotIdentityBootstrap.ensureRegistered(publisher)

        assertThat(publisher.publishCount).isEqualTo(2)
        assertThat(publisher.publishedOneTimeIds).containsNoneIn(consumed)
        assertThat(publisher.publishedOneTimeIds.min()).isGreaterThan(highestBefore)
        // Peer tarafindan cekilen anahtarlar local'de de tuketilmis sayilir.
        assertThat(unconsumedLocalIds()).containsNoneIn(consumed)
        assertThat(countRows("one_time_prekeys")).isEqualTo(ONE_TIME_POOL)
        assertThat(BotIdentity.isReady()).isTrue()
    }

    @Test
    @Order(6)
    fun `legacy private key envelopes migrate lazily to row-bound AEAD`() {
        val store = PgSignalProtocolStore()
        val identity = store.identityKeyPair
        val preKeyId = unconsumedLocalIds().first()
        val preKey = store.loadPreKey(preKeyId)
        val signedPreKeyId = queryInt("SELECT MIN(key_id) FROM bot_signed_prekey")
        val signedPreKey = store.loadSignedPreKey(signedPreKeyId)

        writeLegacyIdentity(identity.privateKey.serialize())
        writeLegacyPreKey(preKeyId, preKey.keyPair.privateKey.serialize())
        writeLegacySignedPreKey(signedPreKeyId, signedPreKey.keyPair.privateKey.serialize())

        assertThat(isBound("bot_identity", "identity_private_key_enc", "id = 1")).isFalse()
        assertThat(isBound("bot_one_time_prekey", "private_key_enc", "key_id = $preKeyId")).isFalse()
        assertThat(isBound("bot_signed_prekey", "private_key_enc", "key_id = $signedPreKeyId")).isFalse()

        store.identityKeyPair
        store.loadPreKey(preKeyId)
        store.loadSignedPreKey(signedPreKeyId)

        assertThat(isBound("bot_identity", "identity_private_key_enc", "id = 1")).isTrue()
        assertThat(isBound("bot_one_time_prekey", "private_key_enc", "key_id = $preKeyId")).isTrue()
        assertThat(isBound("bot_signed_prekey", "private_key_enc", "key_id = $signedPreKeyId")).isTrue()
    }

    @Test
    @Order(7)
    fun `signed prekey rotation retries exact material and retains the old key`() {
        val oldId = publisher.publishedSignedPreKeyId
        execute("UPDATE bot_signed_prekey SET created_at = NOW() - INTERVAL '8 days' WHERE key_id = $oldId")
        publisher.failNext = true
        val rotationTime = Instant.now()

        assertThrows<IllegalStateException> {
            BotIdentityBootstrap.ensureRegistered(publisher, rotationTime)
        }

        val pendingId = maxKeyId("bot_signed_prekey")
        val pendingPublic = signedPreKeyPublic(pendingId)
        assertThat(pendingId).isEqualTo(oldId + 1)
        assertThat(countRows("bot_signed_prekey")).isEqualTo(2)
        assertThat(serverSignedPreKeyId()).isEqualTo(oldId)

        BotIdentityBootstrap.ensureRegistered(publisher, rotationTime.plusSeconds(60))

        assertThat(publisher.publishedSignedPreKeyId).isEqualTo(pendingId)
        assertThat(publisher.publishedSignedPreKey).isEqualTo(pendingPublic)
        assertThat(serverSignedPreKeyId()).isEqualTo(pendingId)
        assertThat(countRows("bot_signed_prekey")).isEqualTo(2)
    }

    @Test
    @Order(8)
    fun `signed prekeys older than the delayed message window are removed`() {
        val activeId = publisher.publishedSignedPreKeyId
        execute(
            "UPDATE bot_signed_prekey SET created_at = NOW() - INTERVAL '31 days' " +
                "WHERE key_id <> $activeId",
        )

        BotIdentityBootstrap.ensureRegistered(publisher)

        assertThat(countRows("bot_signed_prekey")).isEqualTo(1)
        assertThat(maxKeyId("bot_signed_prekey")).isEqualTo(activeId)
    }

    private fun countRows(table: String): Int = queryInt("SELECT COUNT(*) FROM $table")

    private fun maxKeyId(table: String): Int =
        queryInt("SELECT COALESCE(MAX(key_id), 0) FROM $table")

    private fun serverSignedPreKeyId(): Int = queryInt("SELECT key_id FROM signed_prekeys")

    private fun signedPreKeyPublic(keyId: Int): ByteArray =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT public_key FROM bot_signed_prekey WHERE key_id = ?",
            ).use { statement ->
                statement.setInt(1, keyId)
                statement.executeQuery().use { rows ->
                    check(rows.next())
                    rows.getBytes(1)
                }
            }
        }

    private fun execute(sql: String) {
        BotDatabase.getConnection().use { connection ->
            connection.createStatement().use { statement -> statement.executeUpdate(sql) }
        }
    }

    private fun queryInt(sql: String): Int =
        BotDatabase.getConnection().use { conn ->
            conn.createStatement().use { statement ->
                statement.executeQuery(sql).use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }

    private fun lowestServerOneTimeKeyIds(count: Int): List<Int> =
        BotDatabase.getConnection().use { conn ->
            conn.createStatement().use { statement ->
                statement.executeQuery(
                    "SELECT key_id FROM one_time_prekeys ORDER BY key_id LIMIT $count",
                ).use { rows ->
                    buildList { while (rows.next()) add(rows.getInt("key_id")) }
                }
            }
        }

    private fun deleteServerOneTimeKeys(keyIds: List<Int>) {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("DELETE FROM one_time_prekeys WHERE key_id = ?")
                .use { statement ->
                    for (keyId in keyIds) {
                        statement.setInt(1, keyId)
                        statement.executeUpdate()
                    }
                }
        }
    }

    private fun writeLegacyIdentity(plaintext: ByteArray) {
        val legacy = KeyEncryptor.wrap(plaintext)
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "UPDATE bot_identity SET identity_private_key_enc = ?, " +
                    "identity_private_key_nonce = ? WHERE id = 1",
            ).use { statement ->
                statement.setBytes(1, legacy.ciphertext)
                statement.setBytes(2, legacy.nonce)
                statement.executeUpdate()
            }
        }
    }

    private fun writeLegacyPreKey(keyId: Int, plaintext: ByteArray) {
        val legacy = KeyEncryptor.wrap(plaintext)
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "UPDATE bot_one_time_prekey SET private_key_enc = ?, " +
                    "private_key_nonce = ? WHERE key_id = ?",
            ).use { statement ->
                statement.setBytes(1, legacy.ciphertext)
                statement.setBytes(2, legacy.nonce)
                statement.setInt(3, keyId)
                statement.executeUpdate()
            }
        }
    }

    private fun writeLegacySignedPreKey(keyId: Int, plaintext: ByteArray) {
        val legacy = KeyEncryptor.wrap(plaintext)
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "UPDATE bot_signed_prekey SET private_key_enc = ?, " +
                    "private_key_nonce = ? WHERE key_id = ?",
            ).use { statement ->
                statement.setBytes(1, legacy.ciphertext)
                statement.setBytes(2, legacy.nonce)
                statement.setInt(3, keyId)
                statement.executeUpdate()
            }
        }
    }

    private fun isBound(table: String, column: String, where: String): Boolean =
        BotDatabase.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("SELECT $column FROM $table WHERE $where").use { rows ->
                    rows.next()
                    KeyEncryptor.isBoundCiphertext(rows.getBytes(1))
                }
            }
        }

    private fun unconsumedLocalIds(): List<Int> =
        BotDatabase.getConnection().use { conn ->
            conn.createStatement().use { statement ->
                statement.executeQuery(
                    "SELECT key_id FROM bot_one_time_prekey WHERE consumed_at IS NULL",
                ).use { rows ->
                    buildList { while (rows.next()) add(rows.getInt("key_id")) }
                }
            }
        }

    private fun singleBotUserId(): String =
        BotDatabase.getConnection().use { conn ->
            conn.createStatement().use { statement ->
                statement.executeQuery("SELECT bot_user_id FROM bot_identity WHERE id = 1")
                    .use { rows ->
                        rows.next()
                        rows.getString("bot_user_id")
                    }
            }
        }

    private companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
        const val ONE_TIME_POOL = 100
    }
}
