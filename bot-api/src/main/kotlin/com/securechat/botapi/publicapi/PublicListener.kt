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
 * Production'da Unix domain socket uzerinde dinler. NOT: Ilk implementasyon
 * TCP localhost'a bind ediyor; Unix socket entegrasyonu Task 13'te Docker
 * + socat sidecar veya Netty EpollServerDomainSocketChannel ile eklenecek.
 * Suanlik 127.0.0.1:<port>'ta — yaln izca container ici erisilebilir.
 *
 * Route agacinda SADECE POST /v1/send var. PathWhitelistInterceptor
 * defense-in-depth katmani: yanlislikla baska route eklenirse de 404 doner.
 */
object PublicListener {

    /** TCP localhost varsayilani — Unix socket Task 13'te. */
    private const val DEFAULT_TCP_PORT = 8091

    fun start(port: Int = DEFAULT_TCP_PORT): NettyApplicationEngine {
        val server = embeddedServer(Netty, host = "127.0.0.1", port = port) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true; isLenient = false })
            }
            PathWhitelistInterceptor.install(this)
            routing { sendRoute() }
        }.start(wait = false)
        log.info("[PublicListener] http://127.0.0.1:{}/v1/send (sadece POST)", port)
        log.info("[PublicListener] hedef: Unix socket {} (Task 13)", BotApiConfig.publicSocketPath)
        return server
    }
}
