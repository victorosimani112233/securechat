package com.securechat.botapi.health

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("HealthListener")

/**
 * 127.0.0.1:<healthPort> uzerinde calisan TCP listener.
 *  - GET /health   — basit canlilik kontrolu (DB + Redis ping)
 *  - GET /metrics  — Prometheus scrape endpoint
 *
 * Sadece localhost'a bind edilir — Prometheus container'i ayni Docker
 * network uzerinden eriste de, host disindan ulasilamaz (compose
 * "ports:" alaninda expose EDILMEZ).
 */
object HealthListener {

    fun start(): NettyApplicationEngine {
        val server = embeddedServer(Netty, host = "0.0.0.0", port = BotApiConfig.healthPort) {
            routing {
                get("/health") {
                    val dbOk = BotDatabase.isHealthy()
                    val redisOk = BotRedisManager.isHealthy()
                    if (dbOk && redisOk) {
                        call.respondText("""{"status":"ok"}""", ContentType.Application.Json)
                    } else {
                        call.respondText(
                            """{"status":"degraded","db":$dbOk,"redis":$redisOk}""",
                            ContentType.Application.Json,
                            HttpStatusCode.ServiceUnavailable
                        )
                    }
                }
                get("/metrics") {
                    call.respondText(BotMetrics.registry.scrape(), ContentType.Text.Plain)
                }
            }
        }.start(wait = false)
        log.info("[HealthListener] http://0.0.0.0:{}/health,/metrics", BotApiConfig.healthPort)
        return server
    }
}
