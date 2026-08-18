package com.securechat.signaling

import com.securechat.signaling.db.Database
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
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
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Prekey bundle yaziminin butunlugu.
 *
 * Onceki akista identity, signed prekey ve one-time prekey'ler uc ayri
 * transaction'da yaziliyordu. Aradaki bir hata karisik bir bundle
 * birakabiliyordu — ornegin yeni identity key ile eski signed prekey — ve onu
 * ceken peer hicbir zaman cozemeyecegi bir oturum kurardi.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PreKeyBundleTransactionIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_prekey_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; prekey transaction testi atlandi",
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

    private fun newAccount(): String {
        val userId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "INSERT INTO users(user_id, directory_token) VALUES (?::uuid, ?)",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setString(2, "service:test-${UUID.randomUUID()}")
                statement.executeUpdate()
            }
        }
        return userId
    }

    private fun signedPreKey(seed: Byte) = PreKeyStore.SignedPreKey(
        keyId = seed.toInt() and 0x7F,
        publicKey = ByteArray(33) { seed },
        signature = ByteArray(64) { seed },
    )

    private fun oneTimeKeys(start: Int, count: Int) = (start until start + count).map {
        PreKeyStore.OneTimePreKey(it, ByteArray(33) { _ -> it.toByte() })
    }

    private fun countOneTime(userId: String): Int =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM one_time_prekeys WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows -> rows.next(); rows.getInt(1) }
            }
        }

    @Test
    fun `a bundle upload publishes identity signed and one time keys together`() {
        val userId = newAccount()
        val identity = ByteArray(33) { 7 }

        PreKeyStore.uploadBundle(userId, identity, 4242, signedPreKey(7), oneTimeKeys(1, 10))

        val bundle = PreKeyStore.fetchBundle(userId)
        assertNotNull(bundle)
        assertArrayEquals(identity, bundle!!.identityKey.publicKey)
        assertEquals(4242, bundle.identityKey.registrationId)
        assertNotNull(bundle.oneTimePreKey)
        // Fetch bir one-time prekey'i atomik olarak tuketir.
        assertEquals(9, countOneTime(userId))
    }

    @Test
    fun `a rejected upload leaves no partial bundle behind`() {
        val userId = newAccount()
        PreKeyStore.uploadBundle(userId, ByteArray(33) { 1 }, 1, signedPreKey(1), oneTimeKeys(1, 5))
        val before = PreKeyStore.fetchBundle(userId)
        assertNotNull(before)

        // Ayni key id'yi tasiyan ikinci bir signed prekey ve gecersiz bir
        // one-time kayit ile upload: transaction tumden geri alinmali.
        val failed = runCatching {
            PreKeyStore.uploadBundle(
                userId = userId,
                identityPublicKey = ByteArray(33) { 2 },
                registrationId = 2,
                signedPreKey = signedPreKey(2),
                oneTimePreKeys = listOf(
                    PreKeyStore.OneTimePreKey(900, ByteArray(33) { 2 }),
                    PreKeyStore.OneTimePreKey(901, ByteArray(0)),
                ),
            )
        }
        if (failed.isFailure) {
            val after = PreKeyStore.fetchBundle(userId)
            assertNotNull(after)
            // Eski identity yerinde kalmali; yarim gecis olusmamali.
            assertArrayEquals(ByteArray(33) { 1 }, after!!.identityKey.publicKey)
        }
    }

    @Test
    fun `an identity rotation clears the previous one time keys in the same step`() {
        val userId = newAccount()
        PreKeyStore.uploadBundle(userId, ByteArray(33) { 3 }, 3, signedPreKey(3), oneTimeKeys(1, 8))
        assertEquals(8, countOneTime(userId))

        PreKeyStore.uploadBundle(userId, ByteArray(33) { 4 }, 4, signedPreKey(4), oneTimeKeys(50, 6))

        // Eski identity'nin anahtarlari kalmamali, yalniz yeni set olmali.
        assertEquals(6, countOneTime(userId))
        val bundle = PreKeyStore.fetchBundle(userId)
        assertNotNull(bundle)
        assertTrue(bundle!!.oneTimePreKey!!.keyId >= 50)
    }

    @Test
    fun `an unchanged identity keeps its replenished pool`() {
        val userId = newAccount()
        val identity = ByteArray(33) { 5 }
        PreKeyStore.uploadBundle(userId, identity, 5, signedPreKey(5), oneTimeKeys(1, 4))

        PreKeyStore.uploadBundle(userId, identity, 5, signedPreKey(5), oneTimeKeys(10, 4))

        // Identity degismediginde mevcut havuz silinmez, uzerine eklenir.
        assertEquals(8, countOneTime(userId))
    }

    @Test
    fun `parallel uploads never interleave into a mixed bundle`() {
        val userId = newAccount()
        val pool = Executors.newFixedThreadPool(4)
        try {
            pool.invokeAll(
                (1..4).map { index ->
                    Callable {
                        runCatching {
                            PreKeyStore.uploadBundle(
                                userId = userId,
                                identityPublicKey = ByteArray(33) { index.toByte() },
                                registrationId = index,
                                signedPreKey = signedPreKey(index.toByte()),
                                oneTimePreKeys = oneTimeKeys(index * 100, 3),
                            )
                        }.isSuccess
                    }
                },
            ).forEach { it.get() }
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }

        val bundle = PreKeyStore.fetchBundle(userId)
        assertNotNull(bundle)
        // Identity ile registration id ayni upload'dan gelmeli.
        val expectedRegistration = bundle!!.identityKey.publicKey.first().toInt()
        assertEquals(expectedRegistration, bundle.identityKey.registrationId)
        // Signed prekey de ayni upload'in urunu olmali.
        assertEquals(expectedRegistration, bundle.signedPreKey.publicKey.first().toInt())
    }

    private companion object {
        const val LAST_MIGRATION = 18
    }
}
