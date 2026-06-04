package com.securechat.botapi.admin

import com.securechat.botapi.BotApiConfig
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.util.pipeline.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("AdminListener")

/**
 * Admin yonetim listener'i — sadece localhost erisimine kapali, host'ta
 * bind-mounted Unix socket uzerinden erisilir (Task 13). Suanlik TCP
 * 127.0.0.1:<port>; bot-admin-cli ile etkileiim icin.
 *
 * Tum istekler X-Admin-Token header'ini icermeli (BotApiConfig.botAdminToken).
 * Token yanlissa 401 doner.
 *
 * Route'lar Task 11'de doldurulacak (ClientCrudRoutes + EmergencyRoutes).
 */
object AdminListener {

    private const val DEFAULT_TCP_PORT = 8092

    fun start(port: Int = DEFAULT_TCP_PORT): NettyApplicationEngine {
        val server = embeddedServer(Netty, host = "127.0.0.1", port = port) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
            // Admin token gate — tum endpoint'lere uygulanir
            intercept(ApplicationCallPipeline.Plugins) {
                if (!validateAdminToken(call.request.header("X-Admin-Token"))) {
                    call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "X-Admin-Token gecersiz"))
                    finish()
                }
            }
            routing {
                clientCrudRoutes()
                emergencyRoutes()
                get("/admin/ping") {
                    call.respondText("""{"admin":"ok"}""", ContentType.Application.Json)
                }
            }
        }.start(wait = false)
        log.info("[AdminListener] http://127.0.0.1:{}/admin/* (X-Admin-Token zorunlu)", port)
        log.info("[AdminListener] hedef: Unix socket {} (Task 13)", BotApiConfig.adminSocketPath)
        return server
    }

    private fun validateAdminToken(provided: String?): Boolean {
        if (provided.isNullOrBlank()) return false
        // Constant-time compare
        return java.security.MessageDigest.isEqual(
            provided.toByteArray(Charsets.UTF_8),
            BotApiConfig.botAdminToken.toByteArray(Charsets.UTF_8)
        )
    }
}
