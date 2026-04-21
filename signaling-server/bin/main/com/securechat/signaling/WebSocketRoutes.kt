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

        val type = element["type"]?.jsonPrimitive?.contentOrNull
        val recipientId = element["recipientId"]?.jsonPrimitive?.contentOrNull

        // Sunucu tarafinda islenen mesaj tipleri — peer'e YONLENDIRILMEZ
        when (type) {
            "presence_update" -> {
                // Istemci foreground/background bildiriyor — sunucu state'i guncelle
                val isOnline = element["isOnline"]?.jsonPrimitive?.booleanOrNull ?: return
                val hideLastSeen = element["hideLastSeen"]?.jsonPrimitive?.booleanOrNull ?: false
                connectionManager.handlePresenceUpdate(senderId, isOnline, hideLastSeen)
                return
            }
            "presence_subscribe" -> {
                // Istemci bir kisi icin presence subscribe istiyor
                if (!recipientId.isNullOrBlank()) {
                    connectionManager.subscribePresence(senderId, recipientId)
                }
                return
            }
            "presence_unsubscribe" -> {
                // Istemci presence unsubscribe istiyor
                if (!recipientId.isNullOrBlank()) {
                    connectionManager.unsubscribePresence(senderId, recipientId)
                }
                return
            }
        }

        if (recipientId.isNullOrBlank()) {
            println("[!] recipientId eksik, mesaj yoksayildi: $senderId")
            return
        }

        // Broadcast mesajlar (typing) tum online kullanicilara iletilir
        if (recipientId == "broadcast") {
            connectionManager.broadcastMessage(senderId, messageJson)
        } else {
            // Grup ID'sine gonderim tespit et — bu bir bug belirtisi
            if (recipientId.startsWith("group_")) {
                println("[!] UYARI: recipientId grup ID'si! type=$type, sender=$senderId, recipient=$recipientId")
            }
            connectionManager.routeMessage(senderId, recipientId, messageJson)
        }

    } catch (e: Exception) {
        println("[!] Mesaj parse hatasi ($senderId): ${e.message}")
    }
}
