package com.securechat.signaling

import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.serialization.json.*

fun Application.configureWebSocket(connectionManager: ConnectionManager) {
    routing {
        webSocket("/ws") {
            // userId query parametresinden al
            val userId = call.request.queryParameters["userId"]
            if (userId.isNullOrBlank()) {
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "userId gerekli"))
                return@webSocket
            }

            connectionManager.addConnection(userId, this)

            try {
                for (frame in incoming) {
                    when (frame) {
                        is Frame.Text -> {
                            val text = frame.readText()
                            handleMessage(userId, text, connectionManager)
                        }
                        is Frame.Ping -> send(Frame.Pong(frame.data))
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                println("[!] WebSocket hatasi ($userId): ${e.message}")
            } finally {
                connectionManager.removeConnection(userId)
            }
        }
    }
}

private suspend fun handleMessage(
    senderId: String,
    messageJson: String,
    connectionManager: ConnectionManager
) {
    try {
        val json = Json { ignoreUnknownKeys = true }
        val element = json.parseToJsonElement(messageJson).jsonObject

        val recipientId = element["recipientId"]?.jsonPrimitive?.contentOrNull
        if (recipientId.isNullOrBlank()) {
            println("[!] recipientId eksik, mesaj yoksayildi: $senderId")
            return
        }

        // Mesaji oldugu gibi hedefe yonlendir
        connectionManager.routeMessage(senderId, recipientId, messageJson)

    } catch (e: Exception) {
        println("[!] Mesaj parse hatasi ($senderId): ${e.message}")
    }
}
