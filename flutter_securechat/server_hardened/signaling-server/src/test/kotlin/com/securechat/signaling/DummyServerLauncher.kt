package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import java.util.UUID
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Yerel "dummy" signaling sunucusu — YALNIZ guvenlik testi icin.
 *
 * Uretim `main()`'i PKCS#11 HSM, verify-full TLS PostgreSQL ve tam bir
 * uretim gizlilik kapisi ister; bunlar bir laboratuvarda kurulamaz. Bu
 * launcher ayni Ktor modulunu (`signalingModule`) gercek PostgreSQL ve
 * Redis konteynerleriyle, gercek bir portta ayaga kaldirir. Amac, taramanin
 * canli bir hedef gormesidir; uretim dagitimi degildir.
 *
 * Baglanti bilgileri (bir kac hesap + token) stdout'a "SCAN-CREDENTIALS"
 * on ekiyle yazilir, boylece tarayici kimlik dogrulamasi arkasindaki
 * yuzeyleri de gorebilir.
 */
object DummyServerLauncher {

    @JvmStatic
    fun main(args: Array<String>) {
        val bindHost = System.getenv("DUMMY_BIND_HOST") ?: "0.0.0.0"
        val bindPort = System.getenv("DUMMY_BIND_PORT")?.toIntOrNull() ?: 8080

        val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
            withDatabaseName("securechat_dummy")
            withUsername("securechat")
            withPassword("securechat_dummy_password")
        }
        val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
            .withExposedPorts(6379)

        println("[dummy] PostgreSQL ve Redis baslatiliyor...")
        postgres.start()
        redis.start()

        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), password = null)

        ServerPrivacy.initialize()
        PurposeSeparatedSecrets.validate()
        PrivateDirectory.initialize()
        MetricsAccess.initialize()
        AuthService.initialize()
        CredentialState.initialize()

        val fcmTokenStore = FcmTokenStore()
        val fcmPushSender = FcmPushSender(fcmTokenStore)
        val connectionManager = ConnectionManager(fcmPushSender)
        val userRegistry = UserRegistry()
        // WebSocket, retention saglikli olmadan acilmaz.
        PrivacyRetentionWorker.runOnce()

        // Tarama icin birkac gercek hesap.
        repeat(3) { index ->
            val userId = UUID.randomUUID().toString()
            val hash = java.security.MessageDigest.getInstance("SHA-256")
                .digest("+90555000$index$index$index$index".toByteArray())
                .joinToString("") { "%02x".format(it) }
            runCatching {
                userRegistry.registerUser(userId)
                userRegistry.updateOwnDirectoryToken(
                    userId,
                    PrivateDirectory.oprf.tokenForPhoneHash(hash),
                )
            }
            val token = AuthService.issueToken(userId)
            println("SCAN-CREDENTIALS user=$userId token=$token")
        }
        val metricsToken = System.getenv("METRICS_BEARER_TOKEN") ?: ""
        println("SCAN-CREDENTIALS metricsBearer=$metricsToken")

        val server = embeddedServer(Netty, host = bindHost, port = bindPort) {
            signalingModule(connectionManager, userRegistry, fcmTokenStore, fcmPushSender)
        }

        Runtime.getRuntime().addShutdownHook(
            Thread {
                println("[dummy] Kapatiliyor...")
                runCatching { RedisManager.close() }
                runCatching { Database.close() }
                runCatching { redis.stop() }
                runCatching { postgres.stop() }
            },
        )

        println("[dummy] Signaling sunucusu hazir: http://$bindHost:$bindPort")
        println("[dummy] Saglik: GET /health   Metrics: GET /metrics (Bearer)")
        server.start(wait = true)
    }
}
