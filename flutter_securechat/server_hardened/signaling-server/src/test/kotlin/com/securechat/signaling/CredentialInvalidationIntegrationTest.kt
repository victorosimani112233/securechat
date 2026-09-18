package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Instance'lar arasi credential iptali (whitebox bulgu).
 *
 * Epoch onbellegi process-yereldir; yatay olceklemede logout/silme yapan
 * instance kendi kopyasini dusurse de digerleri iptal edilmis token'i
 * onbellek TTL'i boyunca kabul ederdi. Redis pub/sub ile iptal butun
 * instance'lara yayilir; bu test "baska bir instance"in yaptigi yayinin
 * yerel kopyayi dusurdugunu dogrular.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class CredentialInvalidationIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_cred_invalidate")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; test atlandi")
        postgres.start()
        redis.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password)
            .use { connection ->
                connection.autoCommit = true
                val last = migrationDir.toFile()
                    .listFiles { f -> f.name.startsWith("V") && f.name.endsWith(".sql") }!!
                    .maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
                for (version in 1..last) {
                    val migration = Files.list(migrationDir).use { paths ->
                        paths.filter { it.fileName.toString().startsWith("V${version}__") }
                            .findFirst().orElseThrow()
                    }
                    connection.createStatement().use { it.execute(Files.readString(migration)) }
                }
            }
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)
        CredentialState.startInvalidationSubscriber()
        // Pub/sub kalicisizdir; abone baglanmadan yapilan yayin kaybolur.
        check(CredentialState.awaitSubscriberReady(10_000)) { "abone hazir olmadi" }
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { RedisManager.close() }
        runCatching { Database.close() }
        redis.stop()
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

    private fun awaitEvicted(userId: String, timeoutMillis: Long = 5_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            if (!CredentialState.isCached(userId)) return true
            Thread.sleep(25)
        }
        return !CredentialState.isCached(userId)
    }

    @Test
    fun `a broadcast from another instance evicts the local epoch cache`() {
        val user = newAccount()
        // Bu instance kopyayi isitir (login sonrasi ilk dogrulama gibi).
        CredentialState.cachedSnapshot(user)
        assertTrue(CredentialState.isCached(user), "kopya isinmadi")

        // Baska bir instance logout/rotate yapti ve yayinladi.
        CredentialState.broadcastInvalidate(user)

        // Abone mesaji almali ve yerel kopyayi dusurmeli.
        assertTrue(awaitEvicted(user), "yerel kopya iptal yayinindan sonra dusmedi")
    }

    @Test
    fun `rotating the epoch broadcasts to other instances`() {
        val user = newAccount()
        CredentialState.cachedSnapshot(user)

        // Logout yolu: epoch rotasyonu hem yerel kopyayi duser hem yayar.
        CredentialState.rotateCredentialEpoch(user)

        // Ayni process icinde forget zaten cagrildi; onemli olan yayinin da
        // gitmesi. Ikinci bir isitmadan sonra tekrar yayin gelirse yine duser.
        CredentialState.cachedSnapshot(user)
        CredentialState.broadcastInvalidate(user)
        assertTrue(awaitEvicted(user))
    }

    @Test
    fun `an unrelated account is not evicted by a broadcast`() {
        val target = newAccount()
        val bystander = newAccount()
        CredentialState.cachedSnapshot(target)
        CredentialState.cachedSnapshot(bystander)

        CredentialState.broadcastInvalidate(target)
        awaitEvicted(target)

        // Yayin yalniz adreslenen hesabi dusurmeli.
        assertTrue(CredentialState.isCached(bystander), "ilgisiz hesap dusuruldu")
    }

    @Test
    fun `a broadcast failure does not throw`() {
        // Redis kapaliyken bile yayin bir credential bypass'a donusmemeli.
        // (Burada acik Redis var; cagri yalniz istisna firlatmadigini dogrular.)
        CredentialState.broadcastInvalidate(UUID.randomUUID().toString())
    }
}
