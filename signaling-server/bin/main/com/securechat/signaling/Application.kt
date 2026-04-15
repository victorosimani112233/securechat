package com.securechat.signaling

import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.websocket.*
import kotlinx.serialization.json.Json
import java.time.Duration

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    val host = System.getenv("HOST") ?: "0.0.0.0"

    println("=== SecureChat Signaling Server ===")
    println("Baslatiliyor: $host:$port")

    embeddedServer(Netty, port = port, host = host) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                prettyPrint = true
            })
        }
        install(WebSockets) {
            pingPeriod = Duration.ofSeconds(30)
            timeout = Duration.ofSeconds(15)
            maxFrameSize = Long.MAX_VALUE
            masking = false
        }

        val connectionManager = ConnectionManager()
        val userRegistry = UserRegistry()

        configureWebSocket(connectionManager)
        configureRoutes(connectionManager, userRegistry)
    }.start(wait = true)
}
