package com.securechat.signaling

import com.securechat.signaling.db.Database
import org.junit.jupiter.api.AfterAll
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
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.sql.DriverManager
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Registration grant'in tek kullanimlik olusunun kalici ve hesap kaydiyla
 * atomik oldugunu kanitlar.
 *
 * Onceki isaret yalniz persistence'siz Redis'teydi; grant'in 15 dakikalik
 * omru icindeki bir restart veya eviction tuketilmis grant'i yeniden
 * oynatilabilir yapiyordu.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class RegistrationGrantIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_grant_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private lateinit var registry: UserRegistry

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; registration grant integration testi atlandi",
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
        val generator = java.security.KeyPairGenerator.getInstance("RSA")
        generator.initialize(3072)
        registry = UserRegistry(
            directory = PrivateDirectoryOprf.forTest(
                generator.generateKeyPair().private as java.security.interfaces.RSAPrivateCrtKey,
            ),
            legacyIndex = { "legacy-$it" },
        )
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        postgres.stop()
    }

    private fun phoneHash(seed: String): String =
        MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun grant(): AuthService.RegistrationGrant {
        val claim = AuthService.registrationGrantClaim(AuthService.issueRegistrationToken())
        assertNotNull(claim)
        return claim!!
    }

    private fun grantUseCount(): Int =
        Database.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("SELECT COUNT(*) FROM registration_grant_use").use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }

    @Test
    fun `a grant registers exactly one account`() {
        val claim = grant()
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("a"))

        val user = RegistrationGrants.claimAccount(claim, candidate, registry)

        assertNotNull(user)
        assertEquals(candidate.userId, user!!.userId)
    }

    @Test
    fun `replaying a consumed grant is refused even after a cache loss`() {
        val claim = grant()
        val first = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("b"))
        assertNotNull(RegistrationGrants.claimAccount(claim, first, registry))

        // Redis tamamen kaybolsa bile karar degismez: isaret PostgreSQL'de.
        val second = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("c"))
        assertNull(RegistrationGrants.claimAccount(claim, second, registry))
    }

    @Test
    fun `a rejected registration does not burn the grant`() {
        val claim = grant()
        val taken = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("d"))
        assertNotNull(RegistrationGrants.claimAccount(grant(), taken, registry))

        // Ayni directory kimligi baskasi tarafindan alinmis: kayit reddedilir
        // ve bu grant tuketilmemis kalmalidir.
        val duplicate = RegisteredUser(
            userId = UUID.randomUUID().toString(),
            directoryToken = taken.directoryToken,
            directoryKeyId = taken.directoryKeyId,
        )
        assertThrows(DirectoryIdentityAlreadyRegisteredException::class.java) {
            RegistrationGrants.claimAccount(claim, duplicate, registry)
        }

        val fresh = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("e"))
        assertNotNull(RegistrationGrants.claimAccount(claim, fresh, registry))
    }

    @Test
    fun `parallel use of one grant elects a single winner`() {
        val claim = grant()
        val candidates = List(PARALLEL_ATTEMPTS) {
            registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("parallel-$it"))
        }
        val pool = Executors.newFixedThreadPool(PARALLEL_ATTEMPTS)
        try {
            val winners = pool.invokeAll(
                candidates.map { candidate ->
                    Callable { RegistrationGrants.claimAccount(claim, candidate, registry) }
                },
            ).count { it.get() != null }
            assertEquals(1, winners)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `expired markers are purged and carry no account reference`() {
        val claim = grant()
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString(), phoneHash("f"))
        assertNotNull(RegistrationGrants.claimAccount(claim, candidate, registry))
        assertTrue(grantUseCount() > 0)

        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT grant_index FROM registration_grant_use",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    while (rows.next()) {
                        val index = rows.getString("grant_index")
                        assertFalse(index.contains(claim.grantId))
                        assertFalse(index.contains(candidate.userId))
                    }
                }
            }
            connection.createStatement().use {
                it.executeUpdate("UPDATE registration_grant_use SET expires_at = NOW() - INTERVAL '1 hour'")
            }
            assertTrue(RegistrationGrants.purgeExpired(connection) > 0)
        }
        assertEquals(0, grantUseCount())
    }

    private companion object {
        const val LAST_MIGRATION = 18
        const val PARALLEL_ATTEMPTS = 8
    }
}
