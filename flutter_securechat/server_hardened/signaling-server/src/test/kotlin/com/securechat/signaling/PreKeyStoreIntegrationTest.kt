package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

/**
 * Anahtar deposunun davranisi, gercek PostgreSQL ile.
 *
 * Bu depo X3DH'nin sunucu tarafidir. Yarim yazilmis bir bundle, tekrar
 * kullanilan bir one-time prekey ya da identity rotasyonundan sonra ayakta
 * kalan eski materyal dogrudan oturum kurulamamasi ya da daha kotusu yanlis
 * bir esle oturum kurulmasi demektir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PreKeyStoreIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_prekey_store")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private lateinit var registry: UserRegistry

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; prekey testi atlandi")
        postgres.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        ServerPrivacy.initialize()
        PrivateDirectory.initialize()
        registry = UserRegistry()
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { Database.close() }
        postgres.stop()
    }

    private fun sha256Hex(value: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun account(): String {
        val userId = UUID.randomUUID().toString()
        registry.registerUser(userId)
        return userId
    }

    private fun key(seed: Int, size: Int = 33) = ByteArray(size) { (seed + it).toByte() }

    private fun upload(
        userId: String,
        identitySeed: Int = 1,
        registrationId: Int = 4242,
        signedKeyId: Int = 7,
        oneTimeKeys: List<PreKeyStore.OneTimePreKey> = (1..5).map {
            PreKeyStore.OneTimePreKey(it, key(it + 40))
        },
    ) = PreKeyStore.uploadBundle(
        userId = userId,
        identityPublicKey = key(identitySeed),
        registrationId = registrationId,
        signedPreKey = PreKeyStore.SignedPreKey(signedKeyId, key(identitySeed + 10), key(identitySeed + 20, 64)),
        oneTimePreKeys = oneTimeKeys,
    )

    @Test
    fun `a fetched bundle carries the uploaded identity signed key and one one time key`() {
        val user = account()
        upload(user)

        val bundle = PreKeyStore.fetchBundle(user)

        assertNotNull(bundle)
        assertTrue(bundle!!.identityKey.publicKey.contentEquals(key(1)))
        assertEquals(4242, bundle.identityKey.registrationId)
        assertEquals(7, bundle.signedPreKey.keyId)
        assertNotNull(bundle.oneTimePreKey)
    }

    @Test
    fun `an account without an uploaded bundle has none to fetch`() {
        assertNull(PreKeyStore.fetchBundle(account()))
    }

    @Test
    fun `an unknown account cannot upload prekeys`() {
        var failed = false
        try {
            upload(UUID.randomUUID().toString())
        } catch (_: Exception) {
            failed = true
        }

        // Hesap yoksa yazma yapilmamalidir; aksi halde uydurulmus bir UUID
        // icin anahtar materyali birikirdi.
        assertTrue(failed)
    }

    @Test
    fun `each fetch consumes a distinct one time prekey`() {
        val user = account()
        upload(user, oneTimeKeys = (1..3).map { PreKeyStore.OneTimePreKey(it, key(it + 60)) })

        val consumed = (1..3).mapNotNull { PreKeyStore.fetchBundle(user)?.oneTimePreKey?.keyId }

        assertEquals(3, consumed.size)
        assertEquals(consumed.size, consumed.toSet().size, "ayni prekey iki kez verildi")
        assertEquals(0, PreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `the bundle is still usable after the one time keys run out`() {
        val user = account()
        upload(user, oneTimeKeys = listOf(PreKeyStore.OneTimePreKey(1, key(70))))
        PreKeyStore.fetchBundle(user)

        val bundle = PreKeyStore.fetchBundle(user)

        // Signed prekey ile oturum kurulabilir; yalniz forward secrecy
        // ozelligi zayiflar.
        assertNotNull(bundle)
        assertNull(bundle!!.oneTimePreKey)
    }

    @Test
    fun `concurrent fetches never hand out the same one time prekey twice`() {
        val user = account()
        val total = 20
        upload(user, oneTimeKeys = (1..total).map { PreKeyStore.OneTimePreKey(it, key(it + 80)) })
        val threads = 12
        val executor = Executors.newFixedThreadPool(threads)
        try {
            val tasks = (1..total).map {
                Callable { PreKeyStore.fetchBundle(user)?.oneTimePreKey?.keyId }
            }
            val handed = executor.invokeAll(tasks).mapNotNull { it.get() }

            assertEquals(total, handed.size)
            assertEquals(handed.size, handed.toSet().size, "ayni prekey birden fazla ese verildi")
        } finally {
            executor.shutdown()
            executor.awaitTermination(60, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `re uploading the same identity keeps the existing one time keys`() {
        val user = account()
        upload(user, identitySeed = 1, oneTimeKeys = (1..4).map { PreKeyStore.OneTimePreKey(it, key(it + 90)) })
        val before = PreKeyStore.unconsumedCount(user)

        // Ayni identity ile yeni signed prekey: sadece signed key degisir.
        upload(user, identitySeed = 1, signedKeyId = 9, oneTimeKeys = emptyList())

        assertEquals(before, PreKeyStore.unconsumedCount(user))
        assertEquals(9, PreKeyStore.fetchBundle(user)!!.signedPreKey.keyId)
    }

    @Test
    fun `ordinary uploads cannot rotate identity`() {
        val user = account()
        upload(user, identitySeed = 1, oneTimeKeys = (1..4).map { PreKeyStore.OneTimePreKey(it, key(it + 100)) })

        // Yeni identity: eski materyal ayakta kalirsa esler yanlis identity
        // ile X3DH yapmaya calisir ve "no valid sessions" dongusune girer.
        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException::class.java) {
            upload(user, identitySeed = 55, oneTimeKeys = listOf(PreKeyStore.OneTimePreKey(9, key(120))))
        }

        val bundle = PreKeyStore.fetchBundle(user)
        assertTrue(bundle!!.identityKey.publicKey.contentEquals(key(1)))
        assertEquals(3, PreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `an upload replaces the signed prekey rather than accumulating them`() {
        val user = account()
        upload(user, signedKeyId = 1, oneTimeKeys = emptyList())
        upload(user, signedKeyId = 2, oneTimeKeys = emptyList())

        val rows = Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM signed_prekeys WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, user)
                statement.executeQuery().use { r -> if (r.next()) r.getInt(1) else -1 }
            }
        }

        assertEquals(1, rows)
        assertEquals(2, PreKeyStore.fetchBundle(user)!!.signedPreKey.keyId)
    }

    @Test
    fun `additional one time keys can be appended`() {
        val user = account()
        upload(user, oneTimeKeys = (1..2).map { PreKeyStore.OneTimePreKey(it, key(it + 130)) })

        PreKeyStore.addOneTimePreKeys(user, (3..6).map { PreKeyStore.OneTimePreKey(it, key(it + 140)) })

        assertEquals(6, PreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `a duplicate one time key id does not create a second row`() {
        val user = account()
        upload(user, oneTimeKeys = listOf(PreKeyStore.OneTimePreKey(1, key(150))))

        PreKeyStore.addOneTimePreKeys(user, listOf(PreKeyStore.OneTimePreKey(1, key(160))))

        assertEquals(1, PreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `two accounts never see each other's key material`() {
        val first = account()
        val second = account()
        upload(first, identitySeed = 3, registrationId = 111)
        upload(second, identitySeed = 9, registrationId = 222)

        val firstBundle = PreKeyStore.fetchBundle(first)!!
        val secondBundle = PreKeyStore.fetchBundle(second)!!

        assertEquals(111, firstBundle.identityKey.registrationId)
        assertEquals(222, secondBundle.identityKey.registrationId)
        assertTrue(firstBundle.identityKey.publicKey.contentEquals(key(3)))
        assertTrue(secondBundle.identityKey.publicKey.contentEquals(key(9)))
    }

    @Test
    fun `consuming a prekey leaves no access timestamp behind`() {
        val user = account()
        upload(user)
        PreKeyStore.fetchBundle(user)

        // Tuketilmis satir ve erisim zamani bir iletisim zaman cizelgesi
        // olustururdu; satir silinir, iz birakmaz.
        val columns = Database.getConnection().use { connection ->
            connection.metaData.getColumns(null, null, "one_time_prekeys", null).use { rows ->
                buildSet { while (rows.next()) add(rows.getString("COLUMN_NAME")) }
            }
        }

        assertTrue(columns.none { it.contains("consumed", ignoreCase = true) }, columns.toString())
        assertTrue(columns.none { it.contains("accessed", ignoreCase = true) }, columns.toString())
    }
}
