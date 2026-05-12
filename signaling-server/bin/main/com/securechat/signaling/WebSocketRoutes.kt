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
/**
 * Mesaj boyut limiti — byte cinsinden, frame size limit ile tutarli (M14 fix).
 * Application.kt'de WebSockets.maxFrameSize = 256 KB; mesaj byte boyutu da ayni limit.
 * UTF-8'de char != byte (1-4 byte/char) — bu yuzden length yerine byte cinsinden olculur.
 */
private const val MAX_MESSAGE_BYTES = 256 * 1024  // 256 KB, frame size ile aynı

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

            // GUVENLIK: yeni WS baglanti rate limit — IP basina 10/sn.
            // Tek IP'den DoS aciligini engeller (bot floodu, reconnect storm).
            if (!RateLimiter.allow("ws_connect", ip)) {
                AuditLog.log(userId = claimedUserId, eventType = "WS_CONNECT_RATE_LIMIT", ipAddress = ip)
                close(CloseReason(CloseReason.Codes.TRY_AGAIN_LATER, "Cok hizli baglanti"))
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
                            // GUVENLIK (M14 fix): Byte cinsinden boyut kontrolu — frame size limit ile tutarli.
                            // Ktor maxFrameSize zaten buyuk frame'leri reddeder, bu ek savunma.
                            val byteSize = text.toByteArray(Charsets.UTF_8).size
                            if (byteSize > MAX_MESSAGE_BYTES) {
                                AuditLog.log(userId = userId, eventType = "WS_OVERSIZE_MSG", ipAddress = ip,
                                    metadata = mapOf("bytes" to byteSize.toString()))
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
                // Aktif grup aramalarinda participant ise digerlerine ayrildigini bildir.
                // Kullanici explicit HANGUP gondermeden app'i kapatirsa peer'lar bu yolla temizlenir.
                handleUserDisconnectFromGroupCalls(userId, connectionManager)

                connectionManager.removeConnection(userId)
                AuditLog.log(userId = userId, eventType = "WS_CONNECTION_DROPPED", ipAddress = ip)
            }
        }
    }
}

/**
 * WebSocket disconnect tespit edildiginde aktif grup aramalarini temizler.
 *
 * - Normal uye disconnect → digerlerine group_call_member_left broadcast, participants'tan cikar
 * - Koordinator disconnect:
 *   * Kalan online uye varsa → koordinatorluk ona devredilir, herkese
 *     group_call_coordinator_changed + member_left bildirilir; arama DEVAM eder
 *   * Hic kimse kalmadiysa → arama sonlandirilir (store.end + Janus destroy)
 *
 * Koordinator sadece yeni katilim/SDP-route icin onemli; mevcut P2P/SFU media
 * akisi koordinator yokken de calismaya devam eder.
 */
private suspend fun handleUserDisconnectFromGroupCalls(
    userId: String,
    connectionManager: ConnectionManager
) {
    try {
        val affectedCalls = GroupCallSessionStore.findActiveCallsForUser(userId)
        if (affectedCalls.isEmpty()) return

        for (active in affectedCalls) {
            val ts = System.currentTimeMillis()
            // Once participants'tan cikar — kalan listeyi temiz hesaplayabilelim
            GroupCallSessionStore.removeParticipant(active.groupId, userId)

            // ActiveCall snapshot'i mutable ConcurrentHashMap'in icinde
            // (removeParticipant gibi degisiklikleri biz yapiyoruz). Kalanlari yeniden cek.
            val refreshed = GroupCallSessionStore.get(active.groupId)
            val remaining = refreshed?.participants?.filterNot { it == userId } ?: emptyList()

            // Herkese (eski koordinator + diger uyeler haric) member_left bildir
            for (memberId in remaining) {
                val s = connectionManager.connections()[memberId] ?: continue
                val msg = """{"type":"group_call_member_left","senderId":"server","recipientId":"$memberId","timestamp":$ts,"groupCallId":"${active.callId}","groupId":"${active.groupId}","leftMemberId":"$userId"}"""
                try { s.send(io.ktor.websocket.Frame.Text(msg)) } catch (_: Exception) { }
            }

            val coordinatorLeft = active.coordinatorId == userId

            if (coordinatorLeft) {
                if (remaining.isEmpty()) {
                    // Kimse kalmadi → aramayi tamamen sonlandir
                    GroupCallSessionStore.end(active.groupId)
                    if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                        sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                    }
                    logger.info("[GroupCall] Koordinator+son uye disconnect — arama sonlandirildi: ${active.groupId}")
                } else {
                    // GUVENLIK (H9 fix): Koordinator transfer ZORUNLU olarak online uyeye yapilir.
                    // Eskiden offline uyeye fallback vardi — bu kullaniciya orphan call yaratabilirdi.
                    // Online candidate yoksa transfer skip edilir, arama kalan online uyelerle devam,
                    // sonraki disconnect/heartbeat tekrar dener.
                    val onlineCandidate = remaining.firstOrNull { connectionManager.connections().containsKey(it) }
                    if (onlineCandidate == null) {
                        logger.warn("[!] Koordinator transfer atlandi: groupId=${active.groupId} hicbir kalan uye online degil")
                        // Hicbir online uye yok → arama pratik olarak duzelmez, sonlandir.
                        GroupCallSessionStore.end(active.groupId)
                        if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                            sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                        }
                        continue
                    }
                    val transferred = GroupCallSessionStore.transferCoordinator(
                        active.groupId,
                        onlineCandidate,
                        onlineFilter = { connectionManager.connections().containsKey(it) }
                    )
                    if (transferred != null) {
                        val (prev, next) = transferred
                        for (memberId in remaining) {
                            val s = connectionManager.connections()[memberId] ?: continue
                            val msg = """{"type":"group_call_coordinator_changed","senderId":"server","recipientId":"$memberId","timestamp":$ts,"groupCallId":"${active.callId}","groupId":"${active.groupId}","newCoordinatorId":"$next","previousCoordinatorId":"$prev"}"""
                            try { s.send(io.ktor.websocket.Frame.Text(msg)) } catch (_: Exception) { }
                        }
                        logger.info("[GroupCall] Koordinator devir: groupId=${active.groupId} $prev → $next (kalan=${remaining.size})")
                    }
                }
            } else {
                logger.info("[GroupCall] Uye disconnect bildirimi: groupId=${active.groupId} left=$userId kalan=${remaining.size}")
                // Tum uyeler ayrildiysa (koordinator hala bagli AMA participants bos) — savunmaci temizlik
                if (remaining.isEmpty()) {
                    GroupCallSessionStore.end(active.groupId)
                    if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                        sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                    }
                    logger.info("[GroupCall] Tum uyeler ayrildi — arama temizlendi: ${active.groupId}")
                }
            }
        }
    } catch (e: Exception) {
        logger.warn("[!] handleUserDisconnectFromGroupCalls hatasi ($userId): ${e.message}")
    }
}

private suspend fun handleMessage(
    senderId: String,
    rawMessageJson: String,
    connectionManager: ConnectionManager
) {
    try {
        val json = Json { ignoreUnknownKeys = true }
        val rawElement = json.parseToJsonElement(rawMessageJson).jsonObject

        // GUVENLIK (H5 fix): client'tan gelen senderId'yi server-enforced degerle override et.
        // Bir kullanici WebSocket'e authenticate oldugunda token sub'undan senderId belirlenir;
        // mesaj JSON'unda farkli bir senderId varsa SPOOFING girisimidir. Sanitized JSON'i
        // tum downstream route/broadcast cagrilari kullanir.
        val clientSenderId = rawElement["senderId"]?.jsonPrimitive?.contentOrNull
        if (clientSenderId != null && clientSenderId != senderId) {
            logger.warn(
                "[!] Spoofing girisimi: authenticated={} ama JSON.senderId='{}' type='{}' — override edildi",
                senderId, clientSenderId, rawElement["type"]?.jsonPrimitive?.contentOrNull
            )
        }

        // GUVENLIK (M5 fix): Timestamp REPLAY attack korumasi.
        // Client tarafindan gonderilen timestamp guvensiz — saldirgan eski mesaji aynisiyla tekrar
        // gonderebilir veya gelecekteki timestamp ile delivery sirasini bozabilir.
        // Server timestamp'i otorite — drift toleransi olarak ±5 dakika kabul, disinda override.
        // Iletim sirasi ve TTL hesabi server timestamp'ine gore yapilir.
        val nowMs = System.currentTimeMillis()
        val clientTs = rawElement["timestamp"]?.jsonPrimitive?.longOrNull
        val skewMs = if (clientTs != null) Math.abs(nowMs - clientTs) else 0L
        val acceptableSkewMs = 5 * 60 * 1000L  // ±5 dk
        if (clientTs != null && skewMs > acceptableSkewMs) {
            logger.warn(
                "[!] Timestamp skew asildi: sender={} client_ts={} server_ts={} delta={}ms — server'a esitlendi",
                senderId, clientTs, nowMs, nowMs - clientTs
            )
        }

        val element = kotlinx.serialization.json.buildJsonObject {
            rawElement.forEach { (k, v) ->
                if (k != "senderId" && k != "timestamp") put(k, v)
            }
            put("senderId", kotlinx.serialization.json.JsonPrimitive(senderId))
            put("timestamp", kotlinx.serialization.json.JsonPrimitive(nowMs))
        }
        val messageJson = element.toString()

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

        // --- Grup aramasi: GroupCallSessionStore'a kaydet + (esik asilirsa) SFU room olustur ---
        // Esikler: 3-5K kullanici icin mesh-first stratejisi. Video bandwidth pahali oldugu
        // icin daha dusuk esik. 6+ kisi grup video pratikte nadir; bu konfig ile cogu grup
        // arama mesh kalir, server CPU/RAM tasarrufu.
        if (type == "group_call_invite") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val callId = element["callId"]?.jsonPrimitive?.contentOrNull
            val callType = element["callType"]?.jsonPrimitive?.contentOrNull
            val participants = element["participants"]?.jsonArray?.map { it.jsonPrimitive.content }
            val sfuThreshold = if (callType == "VIDEO") 6 else 10
            val isSfu = participants != null && participants.size > sfuThreshold

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
                                janusWsUrl = roomInfo.janusWsUrl
                            )
                            // Tum katilimcilara SFU room bilgisini gonder.
                            // GUVENLIK: apiSecret artik gonderilmiyor (C2 fix).
                            val sfuMsg = """{"type":"sfu_room_created","groupId":"$groupId","roomId":${roomInfo.roomId},"janusWsUrl":"${roomInfo.janusWsUrl}","timestamp":${System.currentTimeMillis()}}"""
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
                        // GUVENLIK: apiSecret artik gonderilmiyor (C2 fix).
                        ""","sfuRoomId":${active.sfuRoomId},"janusWsUrl":"${active.janusWsUrl}""""
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

        // --- Grup aramasi HANGUP: explicit ayrilis (disconnect handler ile ayni semantik) ---
        // Client per-peer HANGUP'i da fan-out olarak gonderiyor (eski client compat icin);
        // bu route'da N kere participant cikarmamak icin SADECE server-yonlendirilmis
        // (recipientId="server", groupId set) HANGUP'larda devir/broadcast yapilir.
        if (type == "call_control") {
            val action = element["action"]?.jsonPrimitive?.contentOrNull
            if (action == "HANGUP" && recipientId == "server") {
                val hangupGroupId = element["groupId"]?.jsonPrimitive?.contentOrNull
                if (hangupGroupId != null) {
                    val active = GroupCallSessionStore.get(hangupGroupId)
                    if (active != null) {
                        // Kullanici (koordinator olsun veya olmasin) aramadan ayriliyor.
                        // Davranis disconnect handler ile ayni: katilimcilari bilgilendir,
                        // koordinatorse devret, kimse kalmazsa kapat.
                        GroupCallSessionStore.removeParticipant(hangupGroupId, senderId)
                        val refreshed = GroupCallSessionStore.get(hangupGroupId)
                        val remaining = refreshed?.participants?.filterNot { it == senderId } ?: emptyList()
                        val ts = System.currentTimeMillis()

                        for (memberId in remaining) {
                            val s = connectionManager.connections()[memberId] ?: continue
                            val msg = """{"type":"group_call_member_left","senderId":"server","recipientId":"$memberId","timestamp":$ts,"groupCallId":"${active.callId}","groupId":"${active.groupId}","leftMemberId":"$senderId"}"""
                            try { s.send(io.ktor.websocket.Frame.Text(msg)) } catch (_: Exception) { }
                        }

                        if (remaining.isEmpty()) {
                            GroupCallSessionStore.end(hangupGroupId)
                            if (JanusOrchestrator.hasActiveRoom(hangupGroupId)) {
                                sfuScope.launch { JanusOrchestrator.destroyVideoRoom(hangupGroupId) }
                            }
                            logger.info("[GroupCall] Son uye HANGUP — arama sonlandirildi: $hangupGroupId")
                        } else if (active.coordinatorId == senderId) {
                            // Koordinator ayrildi → online kalan biri devralir
                            val newCoordinator = remaining.firstOrNull { connectionManager.connections().containsKey(it) }
                                ?: remaining.first()
                            val transferred = GroupCallSessionStore.transferCoordinator(hangupGroupId, newCoordinator)
                            if (transferred != null) {
                                val (prev, next) = transferred
                                for (memberId in remaining) {
                                    val s = connectionManager.connections()[memberId] ?: continue
                                    val msg = """{"type":"group_call_coordinator_changed","senderId":"server","recipientId":"$memberId","timestamp":$ts,"groupCallId":"${active.callId}","groupId":"${active.groupId}","newCoordinatorId":"$next","previousCoordinatorId":"$prev"}"""
                                    try { s.send(io.ktor.websocket.Frame.Text(msg)) } catch (_: Exception) { }
                                }
                                logger.info("[GroupCall] HANGUP ile koordinator devir: groupId=$hangupGroupId $prev → $next")
                            }
                        }
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

        // GUVENLIK: file_transfer chunk'lari icin byte-rate limit (5 MB/dk per user).
        // Buyuk dosya gondermede mesaj boyutunu sayar; pencerede 5MB'i asarsa drop edilir.
        // Mesh modda fan-out sirasinda her chunk N kere bandwidth tuketir, bu yuzden kritik.
        if (type == "file_transfer") {
            val chunkSize = messageJson.length // payload boyutu yakl. ≈ frame boyutu
            if (!RateLimiter.allowBytes("file_chunk_bytes", senderId, chunkSize)) {
                AuditLog.log(userId = senderId, eventType = "FILE_BYTE_RATE_LIMIT",
                    metadata = mapOf("chunk_bytes" to chunkSize.toString()))
                logger.warn("[!] File byte rate limit asildi: $senderId chunk=$chunkSize")
                return
            }
        }

        connectionManager.routeMessage(senderId, recipientId, messageJson)

    } catch (e: Exception) {
        logger.warn("[!] Mesaj parse hatasi ($senderId): ${e.message}")
    }
}
