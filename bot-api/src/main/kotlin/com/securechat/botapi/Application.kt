package com.securechat.botapi

import com.securechat.botapi.admin.AdminListener
import com.securechat.botapi.auth.ClientKeyCache
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import com.securechat.botapi.delivery.SignalingWsClient
import com.securechat.botapi.health.HealthListener
import com.securechat.botapi.publicapi.PublicListener
import com.securechat.botapi.signal.BotIdentityBootstrap
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("Application")

/**
 * Bot-api ana giris noktasi.
 *
 * Sirayla:
 *  1. Config yukle (fail-fast eksik secret'larda)
 *  2. DB ve Redis baglanti havuzlarini ac
 *  3. V3 schema kontrolu (BotDatabase.init icinde)
 *  4. ClientKeyCache pub/sub listener'i baslat
 *  5. 3 listener: public, admin, health (her biri ayri embeddedServer)
 *  6. Shutdown hook — sirali kapanma (listenerlar → DB/Redis)
 *
 * Listenerlar shutdown'da hook'tan once Thread.currentThread().join() ile
 * canli tutulur. SIGTERM ile docker stop sirasinda hook devreye girer.
 */
fun main() {
    log.info("============================================")
    log.info("  SecureChat Bot API baslatiliyor")
    log.info("============================================")

    // 1. Config
    BotApiConfig.load()

    // 2. DB + Redis
    BotDatabase.init()
    BotRedisManager.init()

    // 3. (DB schema kontrolu BotDatabase.init icinde)

    // 4. Client cache invalidate listener
    ClientKeyCache.startInvalidationListener()

    // 5. Bot identity hazirla + WS clienti baslat
    BotIdentityBootstrap.ensureRegistered()
    SignalingWsClient.start()

    // 6. 3 listener
    val healthServer = HealthListener.start()
    val publicServer = PublicListener.start()
    val adminServer = AdminListener.start()

    // 6. Shutdown hook
    Runtime.getRuntime().addShutdownHook(Thread {
        log.info("[Shutdown] SIGTERM alindi, sirali kapanma basliyor")
        runCatching { publicServer.stop(2_000, 10_000) }
            .onFailure { log.warn("[Shutdown] public listener: {}", it.message) }
        runCatching { adminServer.stop(2_000, 10_000) }
            .onFailure { log.warn("[Shutdown] admin listener: {}", it.message) }
        runCatching { healthServer.stop(1_000, 5_000) }
            .onFailure { log.warn("[Shutdown] health listener: {}", it.message) }
        runCatching { SignalingWsClient.stop() }
        runCatching { ClientKeyCache.stop() }
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
