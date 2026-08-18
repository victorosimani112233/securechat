package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.websocket.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.time.Duration
import java.util.concurrent.atomic.AtomicBoolean

private val log = LoggerFactory.getLogger("Application")

/** Sunucu kapanma surecinde mi */
val isShuttingDown = AtomicBoolean(false)

/** Maksimum es zamanli WebSocket baglanti sayisi */
const val MAX_CONNECTIONS = 6000

/** Graceful shutdown drain suresi (saniye) — env ile override edilebilir */
private val SHUTDOWN_DRAIN_SECONDS = System.getenv("SHUTDOWN_DRAIN_SECONDS")?.toLongOrNull() ?: 30L

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    val host = System.getenv("HOST") ?: "0.0.0.0"

    // Fail before opening a socket if privacy keys or retention bounds are
    // absent/unsafe. Logging uses the same mandatory redaction boundary.
    ProductionDeploymentPolicy.validate()
    // Artefaktin kaynagi kanitlanamiyorsa production baslamaz.
    BuildManifest.validate()
    // SFU medya sinirini kabul beyani olmadan production'da acmaz.
    SfuPolicy.validate()
    ServerPrivacy.initialize()
    PurposeSeparatedSecrets.validate()
    PrivateDirectory.initialize()
    MetricsAccess.initialize()

    log.info("=== SecureChat Signaling Server ===")
    log.info("Signaling listener baslatiliyor")

    // GUVENLIK: TURN_SECRET zorunlu — bos olamaz, production'da abuse'a yol acar
    val turnSecret = SecretSource.required("TURN_SECRET")
    if (turnSecret.length < 16) {
        log.warn("UYARI: TURN_SECRET kisa ({}). En az 32 karakter onerilir.", turnSecret.length)
    }

    // GUVENLIK: JWT_SECRET zorunlu — bos olamaz, fail-fast
    AuthService.initialize()
    // Credential iptali PostgreSQL'de tutulur; Redis kaybi iptal edilmis bir
    // token'i geri getiremez.
    CredentialState.initialize()
    // Registration is fail-closed: no SMTP means no server startup, never an
    // implicit OTP bypass.
    EmailService.initialize()

    // PostgreSQL baglantisi
    Database.init()
    Database.ensureSchema()

    // Redis baglantisi
    RedisManager.init()
    RedisManager.requireMemoryOnly()

    // Janus SFU baglantisi
    if (SfuPolicy.isEnabled()) {
        JanusOrchestrator.init()
        log.info("[Janus] SFU baglantisi baslatiliyor")
    } else {
        log.info("[Janus] SFU kapali — grup aramalari mesh modda kalir")
    }

    // Health check
    val dbOk = Database.isHealthy()
    val redisOk = RedisManager.isHealthy()
    log.info("[Health] PostgreSQL: {}, Redis: {}",
        if (dbOk) "OK" else "FAIL",
        if (redisOk) "OK" else "FAIL")
    if (!dbOk || !redisOk) {
        log.error("Baslangic dependency health check basarisiz; listener acilmayacak")
        Database.close()
        RedisManager.close()
        throw IllegalStateException("PostgreSQL ve Redis production icin zorunludur")
    }

    val fcmTokenStore = FcmTokenStore()
    val fcmPushSender = FcmPushSender(fcmTokenStore)
    val connectionManager = ConnectionManager(fcmPushSender)
    val userRegistry = UserRegistry()
    PrivacyRetentionWorker.start(fcmTokenStore) {
        connectionManager.closeAllConnections()
    }

    val server = embeddedServer(Netty, port = port, host = host) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                prettyPrint = false  // Production: prettyPrint kapali — bandwidth tasarrufu
            })
        }
        install(WebSockets) {
            pingPeriod = Duration.ofSeconds(60)  // Server her 60sn ping atar
            timeout = Duration.ofSeconds(90)     // 90sn pong gelmezse drop
            // GUVENLIK (M14 fix): 256 KB frame limit — saldirgan tek frame ile RAM tuketmesin.
            // Tek otoritatif limit; WebSocketRoutes.kt'de MAX_MESSAGE_BYTES ayni deger.
            // SDP Offer ~10 KB, encrypted envelope ~64 KB, file_transfer chunk 128 KB — limit yeterli.
            maxFrameSize = 256L * 1024L
            masking = false
        }

        // Metrics: online users gauge ConnectionManager'a bagla
        Metrics.registerOnlineUsersGauge { connectionManager.getOnlineCount() }

        configureWebSocket(connectionManager, userRegistry)
        configureRoutes(connectionManager, userRegistry, fcmTokenStore)

        // Graceful shutdown hook
        Runtime.getRuntime().addShutdownHook(Thread {
            log.info("[SHUTDOWN] SIGTERM alindi — graceful shutdown baslatiliyor...")
            isShuttingDown.set(true)

            runBlocking {
                // 1. Tum aktif client'lara SERVER_SHUTDOWN mesaji gonder
                connectionManager.broadcastServerShutdown()

                // 2. Mesaj drain suresi
                log.info("[SHUTDOWN] Mesaj drain bekleniyor ({}sn)...", SHUTDOWN_DRAIN_SECONDS)
                delay(SHUTDOWN_DRAIN_SECONDS * 1000)

                // 3. Janus room'lari kapat
                JanusOrchestrator.destroyAllRooms()

                // 4. Baglantilari kapat
                connectionManager.closeAllConnections()

                // 5. DB/Redis kapat
                PrivacyRetentionWorker.stop()
                Database.close()
                RedisManager.close()
                log.info("[SHUTDOWN] Graceful shutdown tamamlandi")
            }
        })
    }

    server.start(wait = true)
}
