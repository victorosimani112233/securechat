package com.securechat.botapi.admin

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.Base64
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Admin yuzu, gercek Ktor motoruyla.
 *
 * Bu yuz bot istemcilerinin kimligini uretir ve iptal eder; buradaki bir
 * eksiklik dogrudan yetkisiz gonderim yetkisi verir. Token kapisi, alan
 * sinirlari ve rotate sirasi burada bir operatorun gordugu bicimde surulur.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AdminApiTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_admin_api")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379)

    private val adminToken = "admin-token-for-tests-0123456789abcdef"

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; admin testi atlandi")
        postgres.start()
        redis.start()
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
        BotApiConfig.databaseUrl = postgres.jdbcUrl
        BotApiConfig.databaseUser = postgres.username
        BotApiConfig.databasePassword = postgres.password
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 61).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 37).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 73).toByte() }
        BotApiConfig.botAdminToken = adminToken
        BotApiConfig.redisHost = redis.host
        BotApiConfig.redisPort = redis.getMappedPort(6379)
        BotApiConfig.redisPassword = null
        BotDatabase.init()
        BotRedisManager.init()
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { BotRedisManager.close() }
        runCatching { BotDatabase.close() }
        redis.stop()
        postgres.stop()
    }

    private fun admin(block: suspend ApplicationTestBuilder.() -> Unit) = testApplication {
        application { with(AdminListener) { adminModule() } }
        block()
    }

    private fun publicKey(seed: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(32) { (seed + it).toByte() })

    private fun addBody(
        name: String = "AC1:test",
        key: String = publicKey(1),
        allowList: List<String> = listOf("user:${UUID.randomUUID()}"),
        ratePerHour: Int? = null,
        perRecipientPerDay: Int? = null,
        expiresInDays: Int? = null,
    ): String {
        val entries = allowList.joinToString(",") { "\"$it\"" }
        val optional = buildString {
            if (ratePerHour != null) append(""","ratePerHour":$ratePerHour""")
            if (perRecipientPerDay != null) append(""","perRecipientPerDay":$perRecipientPerDay""")
            if (expiresInDays != null) append(""","expiresInDays":$expiresInDays""")
        }
        return """{"name":"$name","publicKey":"$key","allowList":[$entries]$optional}"""
    }

    private suspend fun ApplicationTestBuilder.create(
        body: String = addBody(),
        token: String? = adminToken,
    ): HttpResponse = client.post("/admin/clients") {
        header("Content-Type", "application/json")
        if (token != null) header("X-Admin-Token", token)
        setBody(body)
    }

    // ---------------- Token kapisi ----------------

    @Test
    fun `every admin route requires the admin token`() = admin {
        assertThat(client.get("/admin/ping").status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(client.get("/admin/clients").status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(create(token = null).status).isEqualTo(HttpStatusCode.Unauthorized)
        assertThat(client.delete("/admin/clients/k_x").status).isEqualTo(HttpStatusCode.Unauthorized)
    }

    @Test
    fun `a wrong admin token is refused`() = admin {
        assertThat(
            client.get("/admin/ping") { header("X-Admin-Token", "wrong") }.status,
        ).isEqualTo(HttpStatusCode.Unauthorized)
        // Prefix eslesmesi yetmemeli.
        assertThat(
            client.get("/admin/ping") { header("X-Admin-Token", adminToken.dropLast(1)) }.status,
        ).isEqualTo(HttpStatusCode.Unauthorized)
    }

    @Test
    fun `the correct token is accepted`() = admin {
        val response = client.get("/admin/ping") { header("X-Admin-Token", adminToken) }

        assertThat(response.status).isEqualTo(HttpStatusCode.OK)
    }

    // ---------------- Client olusturma ----------------

    @Test
    fun `a valid client is created and listed`() = admin {
        val name = "AC1:listed-${UUID.randomUUID()}"

        val created = create(addBody(name = name, key = publicKey(2)))
        assertThat(created.status).isEqualTo(HttpStatusCode.Created)

        val list = client.get("/admin/clients") { header("X-Admin-Token", adminToken) }
        assertThat(list.status).isEqualTo(HttpStatusCode.OK)
        assertThat(list.bodyAsText()).contains(name)
    }

    @Test
    fun `the listing never exposes private key material`() = admin {
        create(addBody(name = "AC1:private-${UUID.randomUUID()}", key = publicKey(3)))

        val body = client.get("/admin/clients") { header("X-Admin-Token", adminToken) }.bodyAsText()

        assertThat(body).doesNotContain("privateKey")
        assertThat(body).doesNotContain(publicKey(3))
    }

    @Test
    fun `a public key of the wrong size is refused`() = admin {
        val short = Base64.getEncoder().encodeToString(ByteArray(16))

        val response = create(addBody(key = short))

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
        // Karisik tipli map serialize edilemez ve bu yanit hic donmezdi.
        assertThat(response.bodyAsText()).contains("public_key_size")
    }

    @Test
    fun `an undecodable public key is refused`() = admin {
        val response = create(addBody(key = "!!! not base64 !!!"))

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
    }

    @Test
    fun `a malformed body is refused`() = admin {
        val response = create("{not json")

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
    }

    @Test
    fun `field bounds are enforced`() = admin {
        // Bos ad ya da cok uzun ad.
        assertThat(create(addBody(name = "")).bodyAsText()).contains("\"field\":\"name\"")
        assertThat(create(addBody(name = "x".repeat(129))).bodyAsText()).contains("\"field\":\"name\"")
        // Bos allow-list fail-closed olmali, "her seye izinli" degil.
        assertThat(create(addBody(allowList = emptyList())).bodyAsText()).contains("allow_list")
        // Sema disi girdi.
        assertThat(create(addBody(allowList = listOf("phone:+90555")))
            .bodyAsText()).contains("allow_list_scheme")
        // Tekrarli girdi.
        val duplicate = "user:${UUID.randomUUID()}"
        assertThat(create(addBody(allowList = listOf(duplicate, duplicate)))
            .bodyAsText()).contains("allow_list_duplicate")
        // Kota ve expiry sinirlari.
        assertThat(create(addBody(ratePerHour = 0)).bodyAsText()).contains("rate_per_hour")
        assertThat(create(addBody(ratePerHour = 10_001)).bodyAsText()).contains("rate_per_hour")
        assertThat(create(addBody(perRecipientPerDay = 0)).bodyAsText())
            .contains("per_recipient_per_day")
        assertThat(create(addBody(expiresInDays = 0)).bodyAsText()).contains("expires_in_days")
        assertThat(create(addBody(expiresInDays = 366)).bodyAsText()).contains("expires_in_days")
    }

    @Test
    fun `an oversized admin body is refused`() = admin {
        val huge = (1..2_000).joinToString(",") { "\"user:${UUID.randomUUID()}\"" }

        val response = create("""{"name":"AC1:big","publicKey":"${publicKey(4)}","allowList":[$huge]}""")

        assertThat(response.status).isAnyOf(
            HttpStatusCode.PayloadTooLarge,
            HttpStatusCode.BadRequest,
        )
    }

    // ---------------- Iptal ve rotate ----------------

    @Test
    fun `revoking an unknown kid is a not found`() = admin {
        val response = client.delete("/admin/clients/k_missing") {
            header("X-Admin-Token", adminToken)
        }

        assertThat(response.status).isEqualTo(HttpStatusCode.NotFound)
    }

    @Test
    fun `a created client can be revoked once`() = admin {
        val created = create(addBody(name = "AC1:revoke-${UUID.randomUUID()}", key = publicKey(5)))
        val kid = Regex(""""kid"\s*:\s*"([^"]+)"""").find(created.bodyAsText())!!.groupValues[1]

        val first = client.delete("/admin/clients/$kid") { header("X-Admin-Token", adminToken) }
        val second = client.delete("/admin/clients/$kid") { header("X-Admin-Token", adminToken) }

        assertThat(first.status).isEqualTo(HttpStatusCode.OK)
        // Ikinci iptal bir sey degistirmemeli.
        assertThat(second.status).isEqualTo(HttpStatusCode.NotFound)
    }

    @Test
    fun `rotate issues the new credential before revoking the old one`() = admin {
        val created = create(addBody(name = "AC1:rotate-${UUID.randomUUID()}", key = publicKey(6)))
        val oldKid = Regex(""""kid"\s*:\s*"([^"]+)"""").find(created.bodyAsText())!!.groupValues[1]

        val rotated = client.post("/admin/clients/$oldKid/rotate") {
            header("X-Admin-Token", adminToken)
            header("Content-Type", "application/json")
            setBody("""{"newPublicKey":"${publicKey(7)}"}""")
        }

        assertThat(rotated.status).isEqualTo(HttpStatusCode.OK)
        val body = rotated.bodyAsText()
        assertThat(body).contains(oldKid)
        val newKid = Regex(""""newKid"\s*:\s*"([^"]+)"""").find(body)!!.groupValues[1]
        assertThat(newKid).isNotEqualTo(oldKid)
    }

    @Test
    fun `rotating an unknown kid changes nothing`() = admin {
        val response = client.post("/admin/clients/k_missing/rotate") {
            header("X-Admin-Token", adminToken)
            header("Content-Type", "application/json")
            setBody("""{"newPublicKey":"${publicKey(8)}"}""")
        }

        assertThat(response.status).isEqualTo(HttpStatusCode.NotFound)
    }

    @Test
    fun `rotate refuses a key of the wrong size`() = admin {
        val created = create(addBody(name = "AC1:rotate-bad-${UUID.randomUUID()}", key = publicKey(9)))
        val kid = Regex(""""kid"\s*:\s*"([^"]+)"""").find(created.bodyAsText())!!.groupValues[1]

        val response = client.post("/admin/clients/$kid/rotate") {
            header("X-Admin-Token", adminToken)
            header("Content-Type", "application/json")
            setBody("""{"newPublicKey":"${Base64.getEncoder().encodeToString(ByteArray(31))}"}""")
        }

        assertThat(response.status).isEqualTo(HttpStatusCode.BadRequest)
    }

    // ---------------- Acil durdurma ----------------

    @Test
    fun `the emergency stop can be set and cleared through the admin surface`() = admin {
        val tripped = client.post("/admin/emergency/stop") { header("X-Admin-Token", adminToken) }
        assertThat(tripped.status).isEqualTo(HttpStatusCode.OK)
        assertThat(tripped.bodyAsText()).contains("true")

        val status = client.get("/admin/emergency/status") { header("X-Admin-Token", adminToken) }
        assertThat(status.bodyAsText()).contains("true")

        val cleared = client.post("/admin/emergency/resume") {
            header("X-Admin-Token", adminToken)
        }
        assertThat(cleared.status).isEqualTo(HttpStatusCode.OK)
        assertThat(cleared.bodyAsText()).contains("false")
    }

    companion object {
        val LAST_MIGRATION: Int = java.io.File(System.getProperty("serverMigrationDir"))
            .listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.maxOf { it.name.removePrefix("V").substringBefore("__").toInt() }
            ?: error("Migration dizini okunamadi")
    }
}
