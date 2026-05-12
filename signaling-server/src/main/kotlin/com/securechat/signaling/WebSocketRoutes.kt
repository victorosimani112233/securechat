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

        // --- Grup aramasi: GroupCallSessionStore'a kaydet + (>=4 ise) SFU room olustur ---
        if (type == "group_call_invite") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val callId = element["callId"]?.jsonPrimitive?.contentOrNull
            val callType = element["callType"]?.jsonPrimitive?.contentOrNull
            val participants = element["participants"]?.jsonArray?.map { it.jsonPrimitive.content }
            val isSfu = participants != null && participants.size >= 4

            if (groupId != null && callId != null && callType != null && participants != null) {
                // Ilk invite ise store'a kaydet (ayni grup icin coklu davet idempotent)
                if (!GroupCallSessionStore.isActive(groupId)) {
                    GroupCallSessionStore.start(
                        groupId = groupId,
                        callId = callId,
                        coordinatorId = senderId,
                        callType = callType,
                        participants = participants,
                        mode = if (isSfu) "SFU" else "MESH"
                    )
                    logger.info("[GroupCall] Aktif arama kayit edildi: $groupId mode=${if (isSfu) "SFU" else "MESH"} coord=$senderId")
                }
            }

            if (groupId != null && participants != null && isSfu) {
                // 4+ katilimci → SFU mode
                sfuScope.launch {
                    try {
                        JanusOrchestrator.createVideoRoom(groupId, participants.size + 5)
                        val roomInfo = JanusOrchestrator.getRoomInfo(groupId)
                        if (roomInfo != null) {
                            GroupCallSessionStore.updateSfuInfo(
                                groupId = groupId,
                                sfuRoomId = roomInfo.roomId,
                                janusWsUrl = roomInfo.janusWsUrl,
                                apiSecret = roomInfo.apiSecret
                            )
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

        // --- Aktif grup aramasi durum sorgusu ---
        if (type == "group_call_status_query") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            if (groupId != null) {
                // Yetki: sorgulayan bu grubun uyesi olmali
                if (!GroupMemberStore.getMembers(groupId).contains(senderId)) {
                    logger.warn("[!] group_call_status_query yetki yok: $senderId / $groupId")
                    return
                }
                val active = GroupCallSessionStore.get(groupId)
                val response = if (active != null) {
                    val partsJson = active.participants.joinToString(",") { "\"$it\"" }
                    val sfuFields = if (active.mode == "SFU" && active.sfuRoomId != null) {
                        ""","sfuRoomId":${active.sfuRoomId},"janusWsUrl":"${active.janusWsUrl}","apiSecret":"${active.apiSecret}""""
                    } else ""
                    """{"type":"group_call_status_response","senderId":"server","recipientId":"$senderId","timestamp":${System.currentTimeMillis()},"groupId":"$groupId","isActive":true,"callId":"${active.callId}","coordinatorId":"${active.coordinatorId}","callType":"${active.callType}","participants":[$partsJson],"mode":"${active.mode}"$sfuFields}"""
                } else {
                    """{"type":"group_call_status_response","senderId":"server","recipientId":"$senderId","timestamp":${System.currentTimeMillis()},"groupId":"$groupId","isActive":false,"participants":[]}"""
                }
                try {
                    connectionManager.connections()[senderId]?.send(io.ktor.websocket.Frame.Text(response))
                } catch (_: Exception) { /* yutuldu */ }
                return
            }
        }

        // --- Aktif grup aramasina katilim istegi — koordinatore route, store'a participant ekle ---
        if (type == "group_call_join_request") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            if (groupId != null) {
                // Yetki: katilan bu grubun uyesi olmali
                if (!GroupMemberStore.getMembers(groupId).contains(senderId)) {
                    logger.warn("[!] group_call_join_request yetki yok: $senderId / $groupId")
                    return
                }
                val active = GroupCallSessionStore.get(groupId)
                if (active == null) {
                    logger.warn("[!] group_call_join_request: aktif arama yok $groupId")
                    return
                }
                GroupCallSessionStore.addParticipant(groupId, senderId)
                // recipientId koordinator'a zaten set edilmis durumda — normal route ile gidiyor
            }
        }

        // --- SDP_OFFER: aktif call session olustur (Redis), duplicate engelle ---
        if (type == "sdp_offer" && !recipientId.isNullOrBlank()) {
            // Mevcut active call session var mi? Varsa duplicate engellenebilir
            // (ama mesaji yine de route et — eski client'lar bunu beklemiyor;
            // server-side filtre opsiyonel ek savunma, mesaji bloklamiyoruz).
            if (connectionManager.hasActiveCallSession(senderId, recipientId)) {
                logger.info("[call] sdp_offer: aktif session zaten var — yine de route ediliyor (client tarafi idempotent)")
            }
            connectionManager.setActiveCallSession(senderId, recipientId)
        }

        // --- Grup aramasi bittiginde: koordinator HANGUP'i ise store'u clear et + SFU room sil ---
        if (type == "call_control") {
            val action = element["action"]?.jsonPrimitive?.contentOrNull
            if (action == "HANGUP") {
                val hangupGroupId = element["groupId"]?.jsonPrimitive?.contentOrNull
                if (hangupGroupId != null) {
                    val active = GroupCallSessionStore.get(hangupGroupId)
                    if (active != null && active.coordinatorId == senderId) {
                        // Koordinator hangup → tum arama biter
                        GroupCallSessionStore.end(hangupGroupId)
                        if (JanusOrchestrator.hasActiveRoom(hangupGroupId)) {
                            sfuScope.launch { JanusOrchestrator.destroyVideoRoom(hangupGroupId) }
                        }
                        logger.info("[GroupCall] Aktif arama sonlandirildi (koordinator hangup): $hangupGroupId")
                    } else if (active != null) {
                        // Uye hangup → sadece participant cikar
                        active.participants.remove(senderId)
                    }
                }
            }
            // 1-1 arama: ACCEPT geldigi anda aranan tarafin kuyruğundaki eski
            // caller->callee offer/ice artik gecersizdir. Sonraki HANGUP server'a
            // ulasamasa bile reconnect'te ayni offer tekrar drain edilmemeli.
            if (action == "ACCEPT" && !recipientId.isNullOrBlank()) {
                connectionManager.purgePendingCallSignals(senderId, recipientId)
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
                // Active call session state da temizle — orphan birakma
                connectionManager.clearActiveCallSession(senderId, recipientId)
            }

            // ACK gonder — client HANGUP/REJECT/BUSY/ACCEPT'i kaybetmedigini bilsin
            // (client tarafi gerekirse retry yapar).
            if (!action.isNullOrBlank()) {
                val msgId = element["messageId"]?.jsonPrimitive?.contentOrNull
                if (msgId != null) {
                    try {
                        val ackJson = """{"type":"call_control_ack","messageId":"$msgId","action":"$action","timestamp":${System.currentTimeMillis()}}"""
                        connectionManager.connections()[senderId]?.send(io.ktor.websocket.Frame.Text(ackJson))
                    } catch (_: Exception) { /* ack opsiyonel */ }
                }
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
