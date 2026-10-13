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
        )
    }

    @AfterAll
    fun tearDown() {
        Database.close()
        postgres.stop()
    }

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
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString())

        val user = RegistrationGrants.claimAccount(claim, candidate, registry)

        assertNotNull(user)
        assertEquals(candidate.userId, user!!.userId)
    }

    @Test
    fun `replaying a consumed grant is refused even after a cache loss`() {
        val claim = grant()
        val first = registry.prepareRegistration(UUID.randomUUID().toString())
        assertNotNull(RegistrationGrants.claimAccount(claim, first, registry))

        // Redis tamamen kaybolsa bile karar degismez: isaret PostgreSQL'de.
        val second = registry.prepareRegistration(UUID.randomUUID().toString())
        assertNull(RegistrationGrants.claimAccount(claim, second, registry))
    }

    @Test
    fun `a rejected registration does not burn the grant`() {
        val claim = grant()
        val taken = registry.prepareRegistration(UUID.randomUUID().toString())
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

        val fresh = registry.prepareRegistration(UUID.randomUUID().toString())
        assertNotNull(RegistrationGrants.claimAccount(claim, fresh, registry))
    }

    @Test
    fun `parallel use of one grant elects a single winner`() {
        val claim = grant()
        val candidates = List(PARALLEL_ATTEMPTS) {
            registry.prepareRegistration(UUID.randomUUID().toString())
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
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString())
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

    private fun boundRecoveryEmails(userId: String): Int {
        val cipher = RecoveryRecordCipher.configured()!!
        return Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM account_recovery_bindings WHERE account_index = ?",
            ).use { statement ->
                statement.setString(1, cipher.index("account", userId))
                statement.executeQuery().use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }
    }

    private fun registerBinding(email: String?): Pair<RegisteredUser, Boolean> {
        val claim = AuthService.registrationGrantClaim(AuthService.issueRegistrationToken(email))!!
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString())
        var bound = false
        val user = RegistrationGrants.claimAccount(claim, candidate, registry) { connection ->
            bound = bindRegistrationRecoveryEmail(connection, claim, candidate.userId)
        }
        return user!! to bound
    }

    @Test
    fun `registration binds the OTP verified email for account recovery`() {
        val email = "kayit-${UUID.randomUUID()}@example.com"

        val (user, bound) = registerBinding(email)

        assertTrue(bound)
        assertEquals(1, boundRecoveryEmails(user.userId))
    }

    @Test
    fun `an email already bound elsewhere does not block registration`() {
        val email = "ortak-${UUID.randomUUID()}@example.com"
        val (first, firstBound) = registerBinding(email)
        assertTrue(firstBound)

        val (second, secondBound) = registerBinding(email)

        assertFalse(secondBound)
        assertEquals(1, boundRecoveryEmails(first.userId))
        assertEquals(0, boundRecoveryEmails(second.userId))
    }

    @Test
    fun `a grant without a verified email registers without a binding`() {
        val (user, bound) = registerBinding(null)

        assertFalse(bound)
        assertEquals(0, boundRecoveryEmails(user.userId))
    }

    @Test
    fun `the sealed email cannot be moved to another grant`() {
        val service = AccountRecovery.service!!
        val sealed = service.sealRegistrationEmail("grant-a", "tasima@example.com")

        assertEquals("tasima@example.com", service.openRegistrationEmail("grant-a", sealed))
        assertNull(service.openRegistrationEmail("grant-b", sealed))
        val forged = AuthService.RegistrationGrant("grant-b", Long.MAX_VALUE, sealed)
        val candidate = registry.prepareRegistration(UUID.randomUUID().toString())
        var bound = true
        Database.getConnection().use { connection ->
            bound = bindRegistrationRecoveryEmail(connection, forged, candidate.userId)
        }
        assertFalse(bound)
    }

    private companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
        const val PARALLEL_ATTEMPTS = 8
    }
}
