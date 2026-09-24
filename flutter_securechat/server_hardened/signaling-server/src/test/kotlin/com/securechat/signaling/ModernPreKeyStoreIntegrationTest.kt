package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ModernPreKeyStoreIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_modern_prekeys")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private lateinit var registry: UserRegistry

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; modern prekey testi atlandi")
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

    private fun account(): String = UUID.randomUUID().toString().also(registry::registerUser)
    private fun key(seed: Int, size: Int) = ByteArray(size) { (seed + it).toByte() }
    private fun pair(id: Int) = ModernPreKeyStore.OneTimePreKeyPair(
        id,
        key(id, 33),
        key(id + 1, 1568),
        key(id + 2, 64),
    )

    private fun upload(userId: String, identitySeed: Int = 1, ids: IntRange = 1..3) {
        ModernPreKeyStore.uploadBundle(
            userId = userId,
            identityPublicKey = key(identitySeed, 33),
            registrationId = 4242,
            signedPreKey = ModernPreKeyStore.SignedPreKey(
                7,
                key(identitySeed + 1, 33),
                key(identitySeed + 2, 64),
            ),
            oneTimePreKeys = ids.map(::pair),
            lastResortKyberPreKey = ModernPreKeyStore.KyberPreKey(
                0xFFFFFF,
                key(identitySeed + 3, 1568),
                key(identitySeed + 4, 64),
                true,
            ),
        )
    }

    @Test
    fun `EC and Kyber one time keys are consumed as one pair`() {
        val user = account()
        upload(user)

        val fetched = (1..3).map { ModernPreKeyStore.fetchBundle(user)!! }

        assertEquals(listOf(1, 2, 3), fetched.map { it.oneTimePreKey!!.keyId })
        fetched.forEach { bundle ->
            assertEquals(bundle.oneTimePreKey!!.keyId, bundle.kyberPreKey.keyId)
            assertFalse(bundle.kyberPreKey.lastResort)
        }
        assertEquals(0, ModernPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `last resort Kyber remains available without an EC one time key`() {
        val user = account()
        upload(user, ids = 1..1)
        ModernPreKeyStore.fetchBundle(user)

        val fallback = ModernPreKeyStore.fetchBundle(user)!!

        assertNull(fallback.oneTimePreKey)
        assertEquals(0xFFFFFF, fallback.kyberPreKey.keyId)
        assertTrue(fallback.kyberPreKey.lastResort)
    }

    @Test
    fun `concurrent fetches never return the same PQXDH pair`() {
        val user = account()
        upload(user, ids = 1..20)
        val executor = Executors.newFixedThreadPool(12)
        try {
            val tasks = (1..20).map {
                Callable { ModernPreKeyStore.fetchBundle(user)?.oneTimePreKey?.keyId }
            }
            val ids = executor.invokeAll(tasks).mapNotNull { it.get() }
            assertEquals(20, ids.size)
            assertEquals(ids.size, ids.toSet().size)
        } finally {
            executor.shutdown()
            executor.awaitTermination(60, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `ordinary identity rotation is rejected atomically`() {
        val user = account()
        upload(user, identitySeed = 1, ids = 1..4)

        org.junit.jupiter.api.Assertions.assertThrows(IllegalStateException::class.java) {
            upload(user, identitySeed = 40, ids = 90..90)
        }

        val bundle = ModernPreKeyStore.fetchBundle(user)!!
        assertTrue(bundle.identityKey.publicKey.contentEquals(key(1, 33)))
        assertEquals(1, bundle.oneTimePreKey!!.keyId)
        assertEquals(3, ModernPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `an ambiguous upload can retry the exact batch without consuming capacity`() {
        val user = account()
        upload(user, ids = 1..3)

        upload(user, ids = 1..3)

        assertEquals(3, ModernPreKeyStore.unconsumedCount(user))
        assertEquals(listOf(1, 2, 3), (1..3).map { ModernPreKeyStore.fetchBundle(user)!!.oneTimePreKey!!.keyId })
    }

    @Test
    fun `reusing a key ID with different material is refused atomically`() {
        val user = account()
        upload(user, ids = 1..1)
        val conflicting = pair(1).copy(ecPublicKey = key(99, 33))

        assertThrows(IllegalStateException::class.java) {
            ModernPreKeyStore.addOneTimePreKeys(user, listOf(conflicting))
        }

        val original = ModernPreKeyStore.fetchBundle(user)!!.oneTimePreKey!!
        assertTrue(original.ecPublicKey.contentEquals(pair(1).ecPublicKey))
        assertEquals(0, ModernPreKeyStore.unconsumedCount(user))
    }

    @Test
    fun `consumption leaves no timeline column or consumed row`() {
        val user = account()
        upload(user, ids = 1..1)
        ModernPreKeyStore.fetchBundle(user)

        val columns = Database.getConnection().use { connection ->
            connection.metaData.getColumns(null, null, "modern_one_time_prekeys", null).use { rows ->
                buildSet { while (rows.next()) add(rows.getString("COLUMN_NAME")) }
            }
        }
        assertTrue(columns.none { it.contains("time", ignoreCase = true) })
        assertEquals(0, ModernPreKeyStore.unconsumedCount(user))
    }
}
