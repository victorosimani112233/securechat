package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
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
 * Olm prekey deposunun PostgreSQL davranisi.
 *
 * Buradaki testlerin cogu tek bir soruyu farkli aciklardan soruyor:
 * **sunucu bir prekey yazmasini sessizce yutabilir mi?** Yutabildigi her
 * yol, istemcinin yuklendigini sandigi bir anahtarin karsi tarafa hic
 * gitmemesi ve kurulan oturumun cozulememesi demek. Bu projede o sinif
 * daha once P0 uretti (2026-06-09).
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class OlmPreKeyStoreIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_olm_prekey_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private var started = false

    private fun key(seed: Int) = ByteArray(OlmPreKeyStore.KEY_LENGTH) { (seed + it).toByte() }
    private fun signature(seed: Int) =
        ByteArray(OlmPreKeyStore.SIGNATURE_LENGTH) { (seed + it).toByte() }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; Olm prekey PostgreSQL testi atlandi",
        )
        postgres.start()
        started = true
        DriverManager.getConnection(
            postgres.jdbcUrl,
            postgres.username,
            postgres.password,
        ).use { connection ->
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
        }
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        if (started) postgres.stop()
    }

    private fun account(): String {
        val userId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "INSERT INTO users(user_id, directory_token) VALUES (?::uuid, ?)",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setString(2, "token-${userId.take(8)}")
                statement.executeUpdate()
            }
        }
        return userId
    }

    private fun enrolled(): String = account().also {
        OlmPreKeyStore.setIdentity(it, key(1), key(2))
    }

    // ---------------- Kimlik ----------------

    @Test
    fun `identity is established once and may be re-sent unchanged`() {
        val user = enrolled()

        // Yeniden gondermek hata OLMAMALI: agi kopan bir istemci ayni
        // yuklemeyi tekrarlar ve kalici olarak tikanmamalidir.
        OlmPreKeyStore.setIdentity(user, key(1), key(2))

        assertTrue(OlmPreKeyStore.hasIdentity(user))
    }

    @Test
    fun `a different identity key is refused`() {
        val user = enrolled()

        assertThrows(IllegalStateException::class.java) {
            OlmPreKeyStore.setIdentity(user, key(9), key(2))
        }
    }

    @Test
    fun `a different signing key is refused even when the identity key matches`() {
        // Imza anahtari da kimligin parcasi: istemci ikisini BIRLIKTE
        // pinler. Yalniz kimlik anahtarini sabitleyip imza anahtarinin
        // degismesine izin vermek pinlemeyi anlamsiz kilardi.
        val user = enrolled()

        assertThrows(IllegalStateException::class.java) {
            OlmPreKeyStore.setIdentity(user, key(1), key(9))
        }
    }

    private fun recovered(pin: ByteArray, protocol: String): String = account().also {
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "UPDATE users SET recovery_identity_pin = ?, " +
                    "recovery_identity_protocol = ? WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setBytes(1, pin)
                statement.setString(2, protocol)
                statement.setString(3, it)
                statement.executeUpdate()
            }
        }
    }

    @Test
    fun `after recovery only the signing key signed for in recovery is accepted`() {
        val userId = recovered(key(40), "olm")
        assertThrows(OlmPreKeyStore.IdentityRecoveryRequiredException::class.java) {
            OlmPreKeyStore.setIdentity(userId, key(1), key(41))
        }
        assertFalse(OlmPreKeyStore.hasIdentity(userId))
        OlmPreKeyStore.setIdentity(userId, key(1), key(40))
        assertTrue(OlmPreKeyStore.hasIdentity(userId))
    }

    @Test
    fun `a legacy libsignal recovery pin does not block the first Olm upload`() {
        val userId = recovered(ByteArray(33) { 5 }, "v1")
        OlmPreKeyStore.setIdentity(userId, key(1), key(2))
        assertTrue(OlmPreKeyStore.hasIdentity(userId))
    }

    @Test
    fun `a libsignal type-prefixed key is refused instead of being trimmed`() {
        // 33 bayt libsignal'in tur onekli kodlamasi. Oneki kirpip kabul
        // etmek, istemcinin yanlislikla libsignal anahtari gonderdigi
        // durumda cozulemeyen mesaj ureten bir oturumla sonuclanirdi.
        val user = account()
        val prefixed = ByteArray(OlmPreKeyStore.KEY_LENGTH + 1) { it.toByte() }

        assertThrows(IllegalArgumentException::class.java) {
            OlmPreKeyStore.setIdentity(user, prefixed, key(2))
        }
    }

    @Test
    fun `an account without an identity has none`() {
        assertFalse(OlmPreKeyStore.hasIdentity(account()))
    }

    // ---------------- Tek kullanimlik anahtarlar ----------------

    @Test
    fun `one-time keys are stored and counted`() {
        val user = enrolled()

        OlmPreKeyStore.addOneTimeKeys(
            user,
            listOf(
                OlmPreKeyStore.OneTimeKey("k1", key(10)),
                OlmPreKeyStore.OneTimeKey("k2", key(20)),
            ),
        )

        assertEquals(2, OlmPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `re-uploading the same key id with the same material is idempotent`() {
        val user = enrolled()
        val keys = listOf(OlmPreKeyStore.OneTimeKey("k1", key(10)))

        OlmPreKeyStore.addOneTimeKeys(user, keys)
        OlmPreKeyStore.addOneTimeKeys(user, keys)

        assertEquals(1, OlmPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `re-uploading a key id with DIFFERENT material is refused, not swallowed`() {
        // Bu testin varlik sebebi somut: libsignal havuzu ayni durumu
        // `ON CONFLICT DO NOTHING` ile ele aliyor, yani eski anahtari tutup
        // basari donuyor. Istemci yeni anahtarin yuklendigini sanir, karsi
        // taraf eskisini ceker, oturum cozulemez. Sessizce yutmak yerine
        // catisma bildirilmeli.
        val user = enrolled()
        OlmPreKeyStore.addOneTimeKeys(user, listOf(OlmPreKeyStore.OneTimeKey("k1", key(10))))

        val conflict = assertThrows(OlmPreKeyStore.KeyConflictException::class.java) {
            OlmPreKeyStore.addOneTimeKeys(user, listOf(OlmPreKeyStore.OneTimeKey("k1", key(99))))
        }

        assertEquals("k1", conflict.keyId)
        // Catisan yukleme hicbir sey yazmamali.
        assertEquals(1, OlmPreKeyStore.unconsumedCount(user))
        val bundle = OlmPreKeyStore.fetchBundle(user)
        assertArrayEquals(key(10), bundle!!.oneTimeKey)
    }

    @Test
    fun `a conflict in one key rejects the whole upload`() {
        // Kismi yazma, istemcinin hangi anahtarlarin gectigini bilememesi
        // demek olurdu.
        val user = enrolled()
        OlmPreKeyStore.addOneTimeKeys(user, listOf(OlmPreKeyStore.OneTimeKey("k1", key(10))))

        assertThrows(OlmPreKeyStore.KeyConflictException::class.java) {
            OlmPreKeyStore.addOneTimeKeys(
                user,
                listOf(
                    OlmPreKeyStore.OneTimeKey("k2", key(20)),
                    OlmPreKeyStore.OneTimeKey("k1", key(99)),
                ),
            )
        }

        assertEquals(1, OlmPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `a duplicate key id inside one upload is refused`() {
        val user = enrolled()

        assertThrows(IllegalArgumentException::class.java) {
            OlmPreKeyStore.addOneTimeKeys(
                user,
                listOf(
                    OlmPreKeyStore.OneTimeKey("k1", key(10)),
                    OlmPreKeyStore.OneTimeKey("k1", key(20)),
                ),
            )
        }
    }

    // ---------------- Bundle ----------------

    @Test
    fun `fetching consumes exactly one key`() {
        val user = enrolled()
        OlmPreKeyStore.addOneTimeKeys(
            user,
            listOf(
                OlmPreKeyStore.OneTimeKey("k1", key(10)),
                OlmPreKeyStore.OneTimeKey("k2", key(20)),
            ),
        )

        assertNotNull(OlmPreKeyStore.fetchBundle(user)!!.oneTimeKey)

        assertEquals(1, OlmPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `an exhausted pool still hands out the signed fallback key`() {
        // Bu yol OLMASA havuz bosken bundle bos doner ve gonderen hic
        // oturum kuramaz — "No valid sessions" dongusunun sinifi tam budur.
        val user = enrolled()
        OlmPreKeyStore.setFallbackKey(
            user,
            OlmPreKeyStore.FallbackKey(key(30), signature(1)),
        )

        val bundle = OlmPreKeyStore.fetchBundle(user)

        assertNotNull(bundle)
        assertNull(bundle!!.oneTimeKey)
        assertArrayEquals(key(30), bundle.fallbackKey!!.publicKey)
        assertArrayEquals(signature(1), bundle.fallbackKey!!.signature)
    }

    @Test
    fun `the fallback key survives repeated fetches`() {
        // Fallback tuketilmez; tuketilseydi "last resort" olmazdi.
        val user = enrolled()
        OlmPreKeyStore.setFallbackKey(
            user,
            OlmPreKeyStore.FallbackKey(key(30), signature(1)),
        )

        repeat(3) { assertNotNull(OlmPreKeyStore.fetchBundle(user)!!.fallbackKey) }
    }

    @Test
    fun `the fallback key can be rotated`() {
        val user = enrolled()
        OlmPreKeyStore.setFallbackKey(
            user,
            OlmPreKeyStore.FallbackKey(key(30), signature(1)),
        )

        OlmPreKeyStore.setFallbackKey(
            user,
            OlmPreKeyStore.FallbackKey(key(40), signature(2)),
        )

        assertArrayEquals(key(40), OlmPreKeyStore.fetchBundle(user)!!.fallbackKey!!.publicKey)
    }

    @Test
    fun `a fallback signature of the wrong length is refused`() {
        val user = enrolled()

        assertThrows(IllegalArgumentException::class.java) {
            OlmPreKeyStore.setFallbackKey(
                user,
                OlmPreKeyStore.FallbackKey(key(30), ByteArray(32)),
            )
        }
    }

    @Test
    fun `an account with an identity but no keys at all hands out nothing`() {
        // Kimlik var ama ne tek kullanimlik anahtar ne fallback. Oturum
        // kurulamaz, bu yuzden bundle null donmeli; yarim bir bundle
        // dondurmek istemciyi cozulemeyen bir oturuma iterdi.
        assertNull(OlmPreKeyStore.fetchBundle(enrolled()))
    }

    @Test
    fun `an account without an identity hands out nothing`() {
        val user = account()
        // Kimlik olmadan anahtar eklemek de reddedilir, ama dogrudan
        // fetch de null donmeli.
        assertNull(OlmPreKeyStore.fetchBundle(user))
    }

    companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.mapNotNull { Regex("^V(\\d+)__").find(it.name)?.groupValues?.get(1)?.toIntOrNull() }
            ?.maxOrNull()
            ?: error("Migration bulunamadi")
    }
}
