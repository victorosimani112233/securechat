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
        var failNext = false

        override fun publish(bundle: PublishedBundle) {
            if (failNext) {
                failNext = false
                throw IllegalStateException("PreKey upload basarisiz: HTTP 503")
            }
            publishCount++
            publishedOneTimeIds = bundle.oneTimePreKeys.map { it.keyId }
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

    private fun countRows(table: String): Int = queryInt("SELECT COUNT(*) FROM $table")

    private fun maxKeyId(table: String): Int =
        queryInt("SELECT COALESCE(MAX(key_id), 0) FROM $table")

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
        const val LAST_MIGRATION = 18
        const val ONE_TIME_POOL = 100
    }
}
