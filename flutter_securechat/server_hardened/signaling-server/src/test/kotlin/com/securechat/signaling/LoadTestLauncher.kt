package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import java.io.File
import java.util.UUID
import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.utility.DockerImageName

/**
 * Yerel yuk testi sunucusu — YALNIZ kapasite olcumu icin.
 *
 * [DummyServerLauncher] ile ayni uretim modulunu (`signalingModule`) gercek
 * PostgreSQL/Redis konteynerleriyle ayaga kaldirir; farki, tarama icin 3 degil
 * yuk testi icin N sentetik hesap uretmesi ve (userId, token) ciftlerini bir
 * CSV dosyasina yazmasidir. Hesaplar **surec icinde** `registerUser` ile
 * yaratilir; boylece RAM uye kaydinda bulunur ve mesaj yonlendirmesinde alici
 * olabilir (sonradan DB'ye yazilan satirlar bu onbellege girmez).
 *
 * Env:
 *   USER_COUNT      uretilecek hesap sayisi (vars. 6500)
 *   LOADTEST_CREDS  CSV cikti yolu (vars. build/loadtest-creds.csv)
 *   DUMMY_BIND_HOST / DUMMY_BIND_PORT  (vars. 0.0.0.0 / 8080)
 */
object LoadTestLauncher {

    @JvmStatic
    fun main(args: Array<String>) {
        val bindHost = System.getenv("DUMMY_BIND_HOST") ?: "0.0.0.0"
        val bindPort = System.getenv("DUMMY_BIND_PORT")?.toIntOrNull() ?: 8080
        val userCount = System.getenv("USER_COUNT")?.toIntOrNull() ?: 6500
        val credsPath = System.getenv("LOADTEST_CREDS") ?: "build/loadtest-creds.csv"

        val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
            withDatabaseName("securechat_load")
            withUsername("securechat")
            withPassword("securechat_load_password")
        }
        val redis = GenericContainer(DockerImageName.parse("redis:7-alpine"))
            .withExposedPorts(6379)

        println("[load] PostgreSQL ve Redis baslatiliyor...")
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
        PrivacyRetentionWorker.runOnce()

        println("[load] $userCount sentetik hesap uretiliyor...")
        val creds = File(credsPath)
        creds.parentFile?.mkdirs()
        creds.bufferedWriter().use { out ->
            out.write("userId,token\n")
            var made = 0
            repeat(userCount) {
                val userId = UUID.randomUUID().toString()
                // Yonlendirme icin RAM uye kaydi yeterli; directory token (OPRF)
                // yalniz kisi kesfi icindir, yuk testinde gereksiz.
                val ok = runCatching { userRegistry.registerUser(userId) }.isSuccess
                if (!ok) return@repeat
                val token = runCatching { AuthService.issueToken(userId) }.getOrNull()
                    ?: return@repeat
                out.write("$userId,$token\n")
                made++
                if (made % 500 == 0) println("[load]   $made hesap hazir")
            }
            println("[load] Toplam $made hesap yazildi: ${creds.absolutePath}")
        }

        val server = embeddedServer(Netty, host = bindHost, port = bindPort) {
            signalingModule(connectionManager, userRegistry, fcmTokenStore, fcmPushSender)
        }

        Runtime.getRuntime().addShutdownHook(
            Thread {
                println("[load] Kapatiliyor...")
                runCatching { RedisManager.close() }
                runCatching { Database.close() }
                runCatching { redis.stop() }
                runCatching { postgres.stop() }
            },
        )

        println("[load] READY host=$bindHost port=$bindPort users=$userCount")
        server.start(wait = true)
    }
}
