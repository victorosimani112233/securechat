package com.securechat.botapi

import com.securechat.botapi.admin.AdminListener
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.db.ApiClientPrivacyMigration
import com.securechat.botapi.delivery.SignalingWsClient
import com.securechat.botapi.health.HealthListener
import com.securechat.botapi.publicapi.PublicListener
import com.securechat.botapi.listener.UnixSocketBridge
import com.securechat.botapi.signal.BotIdentityBootstrap
import com.securechat.botapi.signal.BotSessionPrivacyMigration
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("Application")

/**
 * Bot-api ana giris noktasi.
 *
 * Sirayla:
 *  1. Config yukle (fail-fast eksik secret'larda)
 *  2. DB ve Redis baglanti havuzlarini ac
 *  3. V3 schema kontrolu (BotDatabase.init icinde)
 *  4. 3 listener: public, admin, health (her biri ayri embeddedServer)
 *  5. Shutdown hook — sirali kapanma (listenerlar → DB/Redis)
 *
 * Listenerlar shutdown'da hook'tan once Thread.currentThread().join() ile
 * canli tutulur. SIGTERM ile docker stop sirasinda hook devreye girer.
 */
fun main() {
    // Load mandatory privacy/crypto material before the first log event.
    ProductionDeploymentPolicy.validate()
    BotApiConfig.load()

    log.info("============================================")
    log.info("  SecureChat Bot API baslatiliyor")
    log.info("============================================")

    // 2. DB + Redis
    BotDatabase.init()
    ApiClientPrivacyMigration.migrateAndVerify()
    BotSessionPrivacyMigration.migrateAndVerify()
    BotRedisManager.init()
    BotRedisManager.requireMemoryOnly()

    // 3. (DB schema kontrolu BotDatabase.init icinde)

    // 4. Bot identity hazirla + WS clienti baslat. API credential'lari her
    // requestte DB'den revoke/expiry kontrollu okunur; positive cache yoktur.
    BotIdentityBootstrap.ensureRegistered()
    SignalingWsClient.start()

    // 5. 3 listener
    val healthServer = HealthListener.start()
    val publicServer = PublicListener.start()
    val adminServer = AdminListener.start()

    // Public ve admin yuzu container disindan yalniz Unix domain socket
    // uzerinden erisilir. Socket dosyasi 0600'dur; ag uzerinden erisim yoktur.
    val publicBridge = UnixSocketBridge(
        socketPath = java.nio.file.Path.of(BotApiConfig.publicSocketPath),
        targetPort = PublicListener.DEFAULT_TCP_PORT,
        name = "public",
    ).also { it.start() }
    val adminBridge = UnixSocketBridge(
        socketPath = java.nio.file.Path.of(BotApiConfig.adminSocketPath),
        targetPort = AdminListener.DEFAULT_TCP_PORT,
        name = "admin",
    ).also { it.start() }

    // 5. Shutdown hook
    Runtime.getRuntime().addShutdownHook(Thread {
        log.info("[Shutdown] SIGTERM alindi, sirali kapanma basliyor")
        runCatching { publicBridge.close() }
        runCatching { adminBridge.close() }
        runCatching { publicServer.stop(2_000, 10_000) }
            .onFailure { log.warn("[Shutdown] public listener: {}", it.javaClass.simpleName) }
        runCatching { adminServer.stop(2_000, 10_000) }
            .onFailure { log.warn("[Shutdown] admin listener: {}", it.javaClass.simpleName) }
        runCatching { healthServer.stop(1_000, 5_000) }
            .onFailure { log.warn("[Shutdown] health listener: {}", it.javaClass.simpleName) }
        runCatching { SignalingWsClient.stop() }
        runCatching { BotRedisManager.close() }
        runCatching { BotDatabase.close() }
        log.info("[Shutdown] Tamam")
    })

    log.info("============================================")
    log.info("  Bot API hazir")
    log.info("============================================")

    // Process'i canli tut
    Thread.currentThread().join()
}
