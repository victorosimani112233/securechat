package com.securechat.signaling

import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.server.plugins.*
import io.ktor.websocket.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("WebSocketRoutes")

private val sfuScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/** Maksimum WebSocket mesaj uzunlugu (karakter cinsinden). 256KB frame'e paralel. */
private const val MAX_MESSAGE_LENGTH = 256_000

fun Application.configureWebSocket(connectionManager: ConnectionManager) {
    routing {
        webSocket("/ws") {
            val claimedUserId = call.request.queryParameters["userId"]
            // Token query param'dan veya Authorization header'dan
            val token = call.request.queryParameters["token"]
                ?: call.request.headers["Authorization"]?.removePrefix("Bearer ")?.trim()

            val ip = call.request.origin.remoteAddress

            if (claimedUserId.isNullOrBlank()) {
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "userId gerekli"))
                return@webSocket
            }
            if (token.isNullOrBlank()) {
                Metrics.wsAuthFailures.increment()
                AuditLog.log(userId = claimedUserId, eventType = "WS_AUTH_MISSING", ipAddress = ip)
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Token gerekli"))
                return@webSocket
            }

            // GUVENLIK: Token'in sub claim'i userId ile eslesmeli — kimlik taklidi onlemi
            val tokenSub = AuthService.verifyToken(token)
            if (tokenSub == null) {
                Metrics.wsAuthFailures.increment()
                AuditLog.log(userId = claimedUserId, eventType = "WS_AUTH_INVALID", ipAddress = ip)
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Gecersiz token"))
                return@webSocket
            }
            if (tokenSub != claimedUserId) {
                Metrics.wsAuthFailures.increment()
                AuditLog.log(userId = claimedUserId, eventType = "WS_AUTH_MISMATCH", ipAddress = ip,
                    metadata = mapOf("token_sub" to tokenSub))
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "userId token ile eslesmiyor"))
                return@webSocket
            }

            // Auth basarili — userId yerine dogrulanmis tokenSub kullanilir
            val userId = tokenSub
            AuditLog.log(userId = userId, eventType = "WS_CONNECTION_ESTABLISHED", ipAddress = ip)
            connectionManager.addConnection(userId, this)

            try {
                for (frame in incoming) {
                    when (frame) {
                        is Frame.Text -> {
                            val text = frame.readText()
                            // GUVENLIK: Mesaj boyut limiti — frame size'a ek savunma katmani
                            if (text.length > MAX_MESSAGE_LENGTH) {
                                AuditLog.log(userId = userId, eventType = "WS_OVERSIZE_MSG", ipAddress = ip,
                                    metadata = mapOf("size" to text.length.toString()))
                                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Mesaj cok buyuk"))
                                return@webSocket
                            }
                            // WebSocket mesaj rate limit
                            if (!RateLimiter.allow("ws_message", userId)) {
                                AuditLog.log(userId = userId, eventType = "WS_RATE_LIMIT_DROP", ipAddress = ip)
                                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Rate limit asildi"))
                                return@webSocket
                            }
                            handleMessage(userId, text, connectionManager)
                        }
                        is Frame.Ping -> send(Frame.Pong(frame.data))
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                logger.warn("[!] WebSocket hatasi ($userId): ${e.message}")
            } finally {
                connectionManager.removeConnection(userId)
                AuditLog.log(userId = userId, eventType = "WS_CONNECTION_DROPPED", ipAddress = ip)
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

        when (type) {
            "presence_update" -> {
                val isOnline = element["isOnline"]?.jsonPrimitive?.booleanOrNull ?: return
                val hideLastSeen = element["hideLastSeen"]?.jsonPrimitive?.booleanOrNull ?: false
                connectionManager.handlePresenceUpdate(senderId, isOnline, hideLastSeen)
                return
            }
            "presence_subscribe" -> {
                if (!recipientId.isNullOrBlank()) {
                    connectionManager.subscribePresence(senderId, recipientId)
                }
                return
            }
            "presence_unsubscribe" -> {
                if (!recipientId.isNullOrBlank()) {
                    connectionManager.unsubscribePresence(senderId, recipientId)
                }
                return
            }
        }

        // --- SFU: Grup aramasi baslatildiginda VideoRoom olustur ---
        if (type == "group_call_invite") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val participants = element["participants"]?.jsonArray?.map { it.jsonPrimitive.content }
            if (groupId != null && participants != null && participants.size >= 4) {
                // 4+ katilimci → SFU mode
                sfuScope.launch {
                    try {
                        JanusOrchestrator.createVideoRoom(groupId, participants.size + 5)
                        val roomInfo = JanusOrchestrator.getRoomInfo(groupId)
                        if (roomInfo != null) {
                            // Tum katilimcilara SFU room bilgisini gonder
                            val sfuMsg = """{"type":"sfu_room_created","groupId":"$groupId","roomId":${roomInfo.roomId},"janusWsUrl":"${roomInfo.janusWsUrl}","apiSecret":"${roomInfo.apiSecret}","timestamp":${System.currentTimeMillis()}}"""
                            for (pid in participants) {
                                val s = connectionManager.connections()[pid]
                                if (s != null) {
                                    try { s.send(io.ktor.websocket.Frame.Text(sfuMsg)) } catch (_: Exception) { }
                                }
                            }
                            logger.info("[SFU] Room olusturuldu ve bildirildi: $groupId -> room=${roomInfo.roomId}")
                        }
                    } catch (e: Exception) {
                        logger.warn("[!] SFU room olusturma hatasi: ${e.message}")
                    }
                }
            }
        }

        // --- SFU: Grup aramasi bittiginde VideoRoom sil ---
        if (type == "call_control") {
            val action = element["action"]?.jsonPrimitive?.contentOrNull
            if (action == "HANGUP") {
                val groupCallId = element["groupCallId"]?.jsonPrimitive?.contentOrNull
                if (groupCallId != null && JanusOrchestrator.hasActiveRoom(groupCallId)) {
                    sfuScope.launch {
                        JanusOrchestrator.destroyVideoRoom(groupCallId)
                    }
                }
            }
            // 1-1 arama: HANGUP/REJECT/BUSY — HER IKI YONUN offline queue'sundaki
            // call sinyallerini (sdp_offer, ice_candidate, call_control) temizle.
            // Senaryo: A->B SDP_OFFER queued. B online geldi, kabul etti, konustu, HANGUP atti.
            //   Eski purge: SADECE recipient(A)'nin queue'sundaki B sinyallerini siliyordu.
            //   B'nin queue'sundaki A->B SDP_OFFER ASLA temizlenmiyordu → B reconnect olunca
            //   queue drain → B'de hayalet incoming call → otomatik geri arama gibi gozukuyordu.
            // Yeni: hem sender hem recipient queue'su temizlenir → hayalet call kalmaz.
            if (action in setOf("HANGUP", "REJECT", "BUSY") && !recipientId.isNullOrBlank()) {
                connectionManager.purgePendingCallSignals(recipientId, senderId)
                connectionManager.purgePendingCallSignals(senderId, recipientId)
            }
        }

        // --- GroupNotification: grup uyelik bilgisini sunucuya sync et ---
        if (type == "group_notification") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val membersArray = element["groupMembers"]?.jsonArray
            val action = element["action"]?.jsonPrimitive?.contentOrNull
            val targetMemberId = element["targetMemberId"]?.jsonPrimitive?.contentOrNull
            if (groupId != null && membersArray != null) {
                val members = membersArray.map { it.jsonPrimitive.content }
                when (action) {
                    "REMOVE_MEMBER", "LEAVE_GROUP" -> {
                        if (targetMemberId != null) GroupMemberStore.removeMember(groupId, targetMemberId)
                        else GroupMemberStore.setMembers(groupId, members)
                    }
                    "ADD_MEMBER" -> {
                        if (targetMemberId != null) GroupMemberStore.addMember(groupId, targetMemberId)
                        else GroupMemberStore.setMembers(groupId, members)
                    }
                    else -> GroupMemberStore.setMembers(groupId, members)
                }
            }
        }

        // --- GROUP_MESSAGE_FANOUT: sunucu tarafinda grup mesaj dagitimi ---
        if (type == "group_message_fanout") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val payloadsObj = element["recipientPayloads"]?.jsonObject
            val ts = element["timestamp"]?.jsonPrimitive?.longOrNull ?: System.currentTimeMillis()
            if (groupId.isNullOrBlank() || payloadsObj == null || payloadsObj.isEmpty()) {
                logger.warn("[!] group_message_fanout eksik alan: sender=$senderId")
                return
            }
            val payloads = payloadsObj.mapValues { (_, v) -> v.jsonPrimitive.content }
            connectionManager.handleGroupMessageFanout(senderId, groupId, payloads, ts)
            return
        }

        // --- Typing indicator grup fan-out ---
        if (type == "typing_indicator" && recipientId != null && recipientId.startsWith("group_")) {
            connectionManager.handleGroupTypingIndicator(senderId, recipientId, messageJson)
            return
        }

        if (recipientId.isNullOrBlank()) {
            logger.warn("[!] recipientId eksik, mesaj yoksayildi: $senderId")
            return
        }

        // GUVENLIK: "broadcast" recipientId disable edildi (DoS amplification onlemi)
        // Sadece sunucu ici cagrilar (broadcastServerShutdown) broadcast yapabilir.
        if (recipientId == "broadcast") {
            logger.warn("[!] Disabled broadcast attempt from {}", senderId)
            return
        }
        connectionManager.routeMessage(senderId, recipientId, messageJson)

    } catch (e: Exception) {
        logger.warn("[!] Mesaj parse hatasi ($senderId): ${e.message}")
    }
}
