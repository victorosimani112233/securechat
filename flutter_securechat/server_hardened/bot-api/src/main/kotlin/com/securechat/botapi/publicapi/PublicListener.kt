package com.securechat.botapi.publicapi

import com.securechat.botapi.BotApiConfig
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.routing.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("PublicListener")

/**
 * Public API listener — bot-api'nin disariya acik tek yuzu.
 *
 * Dis yuz gercek bir Unix domain socket'tir: `UnixSocketBridge` socket'i
 * 0600 izinle acar ve baglantilari bu container ici loopback listener'a
 * aktarir. Loopback yuzeyi container disindan erisilemez.
 *
 * Route agacinda SADECE POST /v1/send var. PathWhitelistInterceptor
 * defense-in-depth katmani: yanlislikla baska route eklenirse de 404 doner.
 */
object PublicListener {

    /** Container ici loopback portu; dis erisim yalniz Unix socket ile. */
    const val DEFAULT_TCP_PORT = 8091

    fun start(port: Int = DEFAULT_TCP_PORT): NettyApplicationEngine {
        val server = embeddedServer(Netty, host = "127.0.0.1", port = port) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true; isLenient = false })
            }
            PathWhitelistInterceptor.install(this)
            routing { sendRoute() }
        }.start(wait = false)
        log.info("[PublicListener] http://127.0.0.1:{}/v1/send (sadece POST)", port)
        log.info("[PublicListener] dis yuz: Unix socket {}", BotApiConfig.publicSocketPath)
        return server
    }
}
