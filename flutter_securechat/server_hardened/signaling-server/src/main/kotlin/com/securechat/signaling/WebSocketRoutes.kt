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

internal val PLAINTEXT_CHAT_CONTROL_TYPES = setOf(
    "delivery_receipt",
    "message_delete",
    "message_edit",
    "message_reaction",
    "message_pin",
    "typing_indicator",
    "disappearing_timer"
)

internal fun isPlaintextChatControlType(type: String?): Boolean =
    type in PLAINTEXT_CHAT_CONTROL_TYPES

internal const val SERVICE_MESSAGE_ACK_TYPE = "message_ack"

internal fun isServerOnlyFrameType(type: String?): Boolean =
    type == SERVICE_MESSAGE_ACK_TYPE

/**
 * Bir aramanin katilimci tavani.
 *
 * SFU'ya gecilemiyorsa mesh tavani gecerlidir: mesh'te her cihaz N-1 encode
 * ve N-1 upload yapar, tavanin ustunde arama kullanilamaz hale gelir.
 * Sessiz bozulma yerine ongorulebilir ret tercih edilir.
 */
internal fun groupCallCapacity(
    call: GroupCallSessionStore.ActiveCall,
    callType: String,
): Int = if (SfuPolicy.canPromote(call.mediaEndToEndEncrypted)) {
    SfuPolicy.MAX_PARTICIPANTS
} else {
    SfuPolicy.meshCapacity(callType)
}

fun Application.configureWebSocket(
    connectionManager: ConnectionManager,
    userRegistry: UserRegistry,
) {
    routing {
        webSocket("/ws") {
            if (!PrivacyRetentionWorker.isHealthy()) {
                close(
                    CloseReason(
                        CloseReason.Codes.TRY_AGAIN_LATER,
                        "Privacy retention unavailable"
                    )
                )
                return@webSocket
            }
            val claimedUserId = call.request.queryParameters["userId"]
            val ip = call.clientAddress()

            if (claimedUserId.isNullOrBlank()) {
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "userId gerekli"))
                return@webSocket
            }

            // Access token yalniz Authorization header'inda tasinabilir.
            // Query string proxy/WAF/APM loglarina girer; oradaki bir token
            // saatlerce hesap yetkisi verir.
            val token = when (
                val credentials = WebSocketCredentials.extract(
                    authorizationHeader = call.request.headers["Authorization"],
                    queryToken = call.request.queryParameters["token"],
                )
            ) {
                is WebSocketCredentials.Result.Accepted -> credentials.token
                WebSocketCredentials.Result.TokenInQuery -> {
                    Metrics.wsAuthFailures.increment()
                    AuditLog.log(eventType = "WS_AUTH_TOKEN_IN_QUERY", ipAddress = ip)
                    close(
                        CloseReason(
                            CloseReason.Codes.VIOLATED_POLICY,
                            "Token yalniz Authorization header ile gonderilir",
                        ),
                    )
                    return@webSocket
                }
                WebSocketCredentials.Result.MalformedHeader -> {
                    Metrics.wsAuthFailures.increment()
                    AuditLog.log(eventType = "WS_AUTH_MALFORMED", ipAddress = ip)
                    close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Gecersiz token"))
                    return@webSocket
                }
                WebSocketCredentials.Result.Missing -> {
                    Metrics.wsAuthFailures.increment()
                    AuditLog.log(eventType = "WS_AUTH_MISSING", ipAddress = ip)
                    close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "Token gerekli"))
                    return@webSocket
                }
            }

            // GUVENLIK: yeni WS baglanti rate limit — IP basina 10/sn.
            // Tek IP'den DoS aciligini engeller (bot floodu, reconnect storm).
            if (!RateLimiter.allow("ws_connect", ip)) {
                AuditLog.log(userId = claimedUserId, eventType = "WS_CONNECT_RATE_LIMIT", ipAddress = ip)
                close(CloseReason(CloseReason.Codes.TRY_AGAIN_LATER, "Cok hizli baglanti"))
                return@webSocket
            }

            // GUVENLIK: Token'in sub claim'i userId ile eslesmeli — kimlik taklidi onlemi.
            // Servis hesabi yalniz `ws.connect` kapsamli assertion ile ve yalniz
            // kendi saglanmis UUID'si adina baglanabilir.
            val userSubject = AuthService.verifyToken(token)
            val serviceSubject = if (userSubject == null) {
                ServiceAccounts.authenticate(token, ServiceAssertion.Scope.WS_CONNECT)
            } else {
                null
            }
            val tokenSub = userSubject ?: serviceSubject
            // Servis hesabi kuyrugunu ancak gercek bir ACK ile bosaltabilir;
            // `send()` yalniz soket tamponunu ifade eder.
            val isServiceAccount = serviceSubject != null
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
                    if (!PrivacyRetentionWorker.isHealthy()) {
                        close(
                            CloseReason(
                                CloseReason.Codes.TRY_AGAIN_LATER,
                                "Privacy retention unavailable"
                            )
                        )
                        return@webSocket
                    }
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
                            handleMessage(
                                userId,
                                text,
                                connectionManager,
                                userRegistry,
                                byteSize,
                                if (isServiceAccount) this else null,
                            )
                        }
                        is Frame.Ping -> send(Frame.Pong(frame.data))
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                logger.warn("[!] WebSocket hatasi: ${e.javaClass.simpleName}")
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
 * Grup aramasi sonlandi — yalnizca in-memory aktif arama katilimcilarina
 * isActive=false durum bildirimi gonder. Kalici bir grup sosyal grafigi yoktur.
 */
private suspend fun broadcastGroupCallEnded(
    groupId: String,
    members: Collection<String>,
    connectionManager: ConnectionManager
) {
    if (members.isEmpty()) return
    val ts = System.currentTimeMillis()
    val connections = connectionManager.connections()
    for (memberId in members) {
        val session = connections[memberId] ?: continue
        val msg = """{"type":"group_call_status_response","senderId":"server","recipientId":"$memberId","timestamp":$ts,"groupId":"$groupId","isActive":false,"participants":[]}"""
        try { session.send(io.ktor.websocket.Frame.Text(msg)) } catch (_: Exception) { }
    }
    logger.info("[GroupCall] Arama sonlandi broadcast: member_count=${members.size}")
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
                if (remaining.size <= 1) {
                    // <=1 kisi kaldi → aramayi tamamen sonlandir
                    GroupCallSessionStore.end(active.groupId)
                    if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                        sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                    }
                    broadcastGroupCallEnded(active.groupId, remaining, connectionManager)
                    logger.info("[GroupCall] Koordinator disconnect + <=1 uye — arama sonlandirildi")
                } else {
                    // GUVENLIK (H9 fix): Koordinator transfer ZORUNLU olarak online uyeye yapilir.
                    // Eskiden offline uyeye fallback vardi — bu kullaniciya orphan call yaratabilirdi.
                    // Online candidate yoksa transfer skip edilir, arama kalan online uyelerle devam,
                    // sonraki disconnect/heartbeat tekrar dener.
                    val onlineCandidate = remaining.firstOrNull { connectionManager.connections().containsKey(it) }
                    if (onlineCandidate == null) {
                        logger.warn("[!] Koordinator transfer atlandi: hicbir kalan uye online degil")
                        // Hicbir online uye yok → arama pratik olarak duzelmez, sonlandir.
                        GroupCallSessionStore.end(active.groupId)
                        if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                            sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                        }
                        broadcastGroupCallEnded(active.groupId, remaining, connectionManager)
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
                        logger.info("[GroupCall] Koordinator devir (kalan=${remaining.size})")
                    }
                }
            } else {
                logger.info("[GroupCall] Uye disconnect bildirimi (kalan=${remaining.size})")
                // <=1 kisi kaldiysa aramayi sonlandir. Onceden `remaining.isEmpty()` idi;
                // o zaman A coordinator + B+C uye, B disconnect, C disconnect → A yalniz
                // kaliyor (remaining=1) ama call canlı goruyordu, "bar gitmiyor" bug'i.
                // 1 kisi kalmasi pratik olarak bos call demek (kendisiyle konusamaz).
                if (remaining.size <= 1) {
                    GroupCallSessionStore.end(active.groupId)
                    if (JanusOrchestrator.hasActiveRoom(active.groupId)) {
                        sfuScope.launch { JanusOrchestrator.destroyVideoRoom(active.groupId) }
                    }
                    broadcastGroupCallEnded(active.groupId, remaining, connectionManager)
                    logger.info("[GroupCall] <=1 uye kaldi — arama temizlendi")
                }
            }
        }
    } catch (e: Exception) {
        logger.warn("[!] handleUserDisconnectFromGroupCalls hatasi: ${e.javaClass.simpleName}")
    }
}

private suspend fun handleMessage(
    senderId: String,
    rawMessageJson: String,
    connectionManager: ConnectionManager,
    userRegistry: UserRegistry,
    /**
     * Cerceve boyutu UTF-8 byte cinsindendir ve frame okunurken zaten
     * hesaplanmistir. String uzunlugu kullanmak cok byte'li karakterlerde
     * gercek boyutu oldugundan kucuk gosterir; byte kotasi bu yuzden
     * asilabiliyordu.
     */
    frameByteSize: Int = rawMessageJson.toByteArray(Charsets.UTF_8).size,
    /**
     * Yalniz servis hesabi baglantilarinda doludur. Bot kuyrugunu ancak
     * mesajin sunucu tarafindan gercekten kabul edildigi bilgisiyle
     * bosaltabilir; normal istemcilere bu cerceve gonderilmez.
     */
    serviceSession: io.ktor.websocket.WebSocketSession? = null,
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
            logger.warn("[!] Spoofing girisimi — senderId override edildi")
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
            logger.warn("[!] Timestamp skew asildi — server saatine esitlendi")
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

        // Bu frame yalniz server tarafindan ayni servis-account session'ina
        // uretilir. Client route'una izin verilirse bir kullanici botun
        // in-flight kaydini sahte ACK ile erken sildirebilir.
        if (isServerOnlyFrameType(type)) {
            logger.warn("[!] Server-only frame client tarafindan reddedildi")
            return
        }

        when (type) {
            "presence_update" -> {
                val isOnline = element["isOnline"]?.jsonPrimitive?.booleanOrNull ?: return
                val hideLastSeen = element["hideLastSeen"]?.jsonPrimitive?.booleanOrNull ?: false
                connectionManager.handlePresenceUpdate(senderId, isOnline, hideLastSeen)
                return
            }
            "presence_subscribe" -> {
                // Hedef gercek bir hesap olmali. Onceki davranista herhangi
                // bir metin kabul ediliyor ve her deger icin kalici bir
                // harita girdisi olusuyordu.
                if (recipientId.isNullOrBlank() || !userRegistry.exists(recipientId)) {
                    AuditLog.log(eventType = "PRESENCE_SUBSCRIBE_REJECTED")
                    return
                }
                if (!RateLimiter.allow("presence_subscribe", senderId)) {
                    AuditLog.log(eventType = "PRESENCE_SUBSCRIBE_RATE_LIMIT")
                    return
                }
                if (!connectionManager.subscribePresence(senderId, recipientId)) {
                    AuditLog.log(eventType = "PRESENCE_SUBSCRIBE_CAPACITY")
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

        // Mesaj kimlikleri, emoji, duzenlenmis icerik, okundu bilgisi,
        // yaziyor durumu ve kaybolan-mesaj suresi sosyal grafiği ve davranis
        // zaman cizelgesini aciga cikarir. Hardened istemci bunlari ordinary
        // encrypted_message icinde CHATCTRL:v2 olarak yollar. Eski plaintext
        // frame'ler uyumluluk ugruna kabul edilmez; gizlilik fail-closed'dur.
        if (isPlaintextChatControlType(type)) {
            logger.warn("[!] Plaintext legacy chat control reddedildi")
            return
        }

        // --- Grup aramasi: GroupCallSessionStore'a kaydet + (esik asilirsa) SFU room olustur ---
        // Esikler: 3-5K kullanici icin mesh-first stratejisi. Video bandwidth pahali oldugu
        // icin daha dusuk esik. 6+ kisi grup video pratikte nadir; bu konfig ile cogu grup
        // arama mesh kalir, server CPU/RAM tasarrufu.
        if (type == "group_call_invite") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val callId = element["callId"]?.jsonPrimitive?.contentOrNull
            val callType = element["callType"]?.jsonPrimitive?.contentOrNull
            // Istemci medya frame sifrelemesi yapabildigini bildirir. Alan
            // yoksa false kabul edilir: eski istemci SFU'ya sessizce
            // gecirilmez.
            val mediaE2ee = element["mediaE2ee"]?.jsonPrimitive?.booleanOrNull == true
            val tokenValid = groupId?.matches(Regex("^[A-Za-z0-9_-]{43}=?$")) == true
            val recipientValid = recipientId != null &&
                recipientId != senderId &&
                runCatching { java.util.UUID.fromString(recipientId) }.isSuccess
            val fieldsValid = tokenValid &&
                !callId.isNullOrBlank() && callId.length <= 128 &&
                callType in setOf("VOICE", "VIDEO") && recipientValid
            if (!fieldsValid) {
                logger.warn("[!] group_call_invite reddedildi: gecersiz opak routing paketi")
                return
            }

            val existing = GroupCallSessionStore.get(groupId!!)
            if (existing == null) {
                GroupCallSessionStore.start(
                    groupId = groupId,
                    callId = callId!!,
                    coordinatorId = senderId,
                    callType = callType!!,
                    // Yalnizca bu invite'in route uclari in-memory tutulur. Client'in
                    // tam grup listesi wire'a alinmaz ve PostgreSQL/Redis'e yazilmaz.
                    participants = listOf(senderId, recipientId!!),
                    mode = "MESH",
                    mediaE2eeParticipants = if (mediaE2ee) setOf(senderId) else emptySet(),
                )
            } else {
                if (existing.callId != callId ||
                    existing.coordinatorId != senderId ||
                    existing.callType != callType
                ) {
                    logger.warn("[!] group_call_invite reddedildi: aktif arama baglam uyusmazligi")
                    return
                }
                // Kapasite moda baglidir: SFU kullanilamiyorsa mesh tavani,
                // kullanilabiliyorsa protokol tavani. Sinirin ustunde arama
                // sessizce bozulmak yerine reddedilir.
                val capacity = groupCallCapacity(existing, callType!!)
                val joined = GroupCallSessionStore.addParticipant(
                    groupId = groupId,
                    userId = recipientId!!,
                    capacity = capacity,
                    mediaE2ee = mediaE2ee,
                )
                if (joined == GroupCallSessionStore.JoinResult.CAPACITY_REACHED) {
                    AuditLog.log(eventType = "GROUP_CALL_CAPACITY_REACHED")
                    logger.warn("[!] group_call_invite reddedildi: katilimci tavani")
                    return
                }
            }
            val activeCall = GroupCallSessionStore.get(groupId) ?: return
            // SFU'ya gecis iki kosula bagli: esik asilmis olmali ve medya
            // guven sinirinin disinda kalmali. Tum katilimcilar frame
            // sifrelemesi bildiriyorsa Janus yalniz ciphertext yonlendirir;
            // biri bile bildirmiyorsa gecis operator kabulu ister.
            val shouldCreateSfu =
                activeCall.participants.size > SfuPolicy.sfuThreshold(callType!!) &&
                    SfuPolicy.canPromote(activeCall.mediaEndToEndEncrypted) &&
                    GroupCallSessionStore.promoteToSfu(groupId)
            logger.info("[GroupCall] Ephemeral aktif arama kayit edildi: participant_count={}", activeCall.participants.size)

            if (shouldCreateSfu) {
                sfuScope.launch {
                    try {
                        JanusOrchestrator.createVideoRoom(groupId, activeCall.participants.size + 5)
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
                            for (pid in activeCall.participants) {
                                val s = connectionManager.connections()[pid]
                                if (s != null) {
                                    try { s.send(io.ktor.websocket.Frame.Text(sfuMsg)) } catch (_: Exception) { }
                                }
                            }
                            logger.info("[SFU] Room olusturuldu ve bildirildi")
                        } else {
                            GroupCallSessionStore.cancelSfuPromotion(groupId)
                        }
                    } catch (e: Exception) {
                        GroupCallSessionStore.cancelSfuPromotion(groupId)
                        logger.warn("[!] SFU room olusturma hatasi: ${e.javaClass.simpleName}")
                    }
                }
            }
        }

        // --- Aktif grup aramasi durum sorgusu ---
        if (type == "group_call_status_query") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            if (groupId != null) {
                if (!groupId.matches(Regex("^[A-Za-z0-9_-]{43}=?$"))) {
                    logger.warn("[!] group_call_status_query gecersiz token")
                    return
                }
                // Kalici grup dizini yok: yalnizca aktif aramaya daha once davet
                // edilmis/gecmis participant sorgulayabilir.
                val active = GroupCallSessionStore.get(groupId)
                if (active != null && senderId !in active.participants) {
                    logger.warn("[!] group_call_status_query yetki yok")
                    return
                }
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
                if (!groupId.matches(Regex("^[A-Za-z0-9_-]{43}=?$"))) {
                    logger.warn("[!] group_call_join_request gecersiz token")
                    return
                }
                val active = GroupCallSessionStore.get(groupId)
                if (active == null) {
                    logger.warn("[!] group_call_join_request: aktif arama yok")
                    return
                }
                // Late join sadece daha once bireysel invite ile bu ephemeral
                // call state'e alinmis kullanici icin kabul edilir.
                if (senderId !in active.participants) {
                    logger.warn("[!] group_call_join_request yetki yok")
                    return
                }
                if (recipientId != active.coordinatorId ||
                    element["callId"]?.jsonPrimitive?.contentOrNull != active.callId
                ) {
                    logger.warn("[!] group_call_join_request baglam uyusmazligi")
                    return
                }
                val joined = GroupCallSessionStore.addParticipant(
                    groupId = groupId,
                    userId = senderId,
                    capacity = groupCallCapacity(active, active.callType),
                    mediaE2ee = element["mediaE2ee"]?.jsonPrimitive?.booleanOrNull == true,
                )
                if (joined == GroupCallSessionStore.JoinResult.CAPACITY_REACHED) {
                    AuditLog.log(eventType = "GROUP_CALL_CAPACITY_REACHED")
                    logger.warn("[!] group_call_join_request reddedildi: katilimci tavani")
                    return
                }
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
                        if (senderId !in active.participants) {
                            logger.warn("[!] group call HANGUP yetkisiz")
                            return
                        }
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

                        if (remaining.size <= 1) {
                            // <=1 kisi kaldi → aramayi sonlandir; yalniz kalan kisinin de
                            // local session'i broadcast ile temizlenir
                            GroupCallSessionStore.end(hangupGroupId)
                            if (JanusOrchestrator.hasActiveRoom(hangupGroupId)) {
                                sfuScope.launch { JanusOrchestrator.destroyVideoRoom(hangupGroupId) }
                            }
                            broadcastGroupCallEnded(hangupGroupId, remaining, connectionManager)
                            logger.info("[GroupCall] HANGUP sonrasi <=1 uye — arama sonlandirildi")
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
                                logger.info("[GroupCall] HANGUP ile koordinator devir")
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

        // Sunucu kalici bir grup dizini tutmaz. Eski v2 sync bile tam uye
        // listesini wire'a ve veritabanina tasiyabildigi icin reddedilir.
        if (type == "group_directory_sync_v2") {
            logger.warn("[!] Persistent group directory sync reddedildi")
            return
        }

        // Legacy v1 exposes group name/full membership and could be persisted
        // in the offline queue. Hardened production is receive-incompatible by
        // design: Flutter sends recipient-specific E2EE GROUPCTRL:v2 instead.
        if (type == "group_notification") {
            logger.warn("[!] Plaintext legacy group notification reddedildi")
            return
        }

        // --- ADMIN_ENCRYPTED_LOG: zero-knowledge audit relay ---
        // Bir grup uyesinin export/copy gibi gizlilik etkileyen eylemini admin'lere
        // E2EE log olarak iletir. Server icerigi GOREMEZ, sadece relay yapar; PERSIST
        // ETMEZ — log dagitik bicimde sadece admin cihazlarinda durur.
        if (type == "admin_encrypted_log") {
            val groupId = element["groupId"]?.jsonPrimitive?.contentOrNull
            val payloadsObj = element["adminPayloads"]?.jsonObject
            val ts = element["timestamp"]?.jsonPrimitive?.longOrNull ?: System.currentTimeMillis()
            val eventType = element["eventType"]?.jsonPrimitive?.contentOrNull
            if (groupId.isNullOrBlank() ||
                eventType != "PRIVATE_EVENT" ||
                payloadsObj == null ||
                payloadsObj.size != 1
            ) {
                logger.warn("[!] admin_encrypted_log eksik alan")
                return
            }
            val payloads = payloadsObj.mapValues { (_, v) -> v.jsonPrimitive.content }
            connectionManager.handleAdminEncryptedLog(senderId, groupId, eventType, payloads, ts)
            return
        }

        // Legacy fanout tek frame'de tam recipient setini ve sabit grup token'ini
        // aciga cikariyordu. v3 her hedefe ayri ordinary encrypted_message yollar.
        if (type == "group_message_fanout") {
            logger.warn("[!] Linkable group_message_fanout reddedildi")
            return
        }

        if (recipientId.isNullOrBlank()) {
            logger.warn("[!] recipientId eksik, mesaj yoksayildi")
            return
        }

        // GUVENLIK: "broadcast" recipientId disable edildi (DoS amplification onlemi)
        // Sadece sunucu ici cagrilar (broadcastServerShutdown) broadcast yapabilir.
        if (recipientId == "broadcast") {
            logger.warn("[!] Disabled broadcast attempt")
            return
        }

        // GUVENLIK: file_transfer chunk'lari icin byte-rate limit (5 MB/dk per user).
        // Buyuk dosya gondermede mesaj boyutunu sayar; pencerede 5MB'i asarsa drop edilir.
        // Mesh modda fan-out sirasinda her chunk N kere bandwidth tuketir, bu yuzden kritik.
        if (type == "file_transfer") {
            val chunkSize = frameByteSize
            if (!RateLimiter.allowBytes("file_chunk_bytes", senderId, chunkSize)) {
                AuditLog.log(userId = senderId, eventType = "FILE_BYTE_RATE_LIMIT",
                    metadata = mapOf("chunk_bytes" to chunkSize.toString()))
                logger.warn("[!] File byte rate limit asildi: chunk=$chunkSize")
                return
            }
        }

        // Alici gercek bir hesap olmali. Aksi halde uydurulmus UUID'ler icin
        // offline kuyrukta kalici anahtarlar olusturulabiliyordu.
        if (!userRegistry.exists(recipientId)) {
            AuditLog.log(eventType = "ROUTE_UNKNOWN_RECIPIENT")
            logger.warn("[!] Bilinmeyen aliciya route reddedildi")
            return
        }
        connectionManager.routeMessage(recipientId, messageJson)
        // Servis hesabina, mesajin route edildigini bildiren ACK.
        if (serviceSession != null) {
            val ackedId = rawElement["messageId"]?.jsonPrimitive?.contentOrNull
                ?.takeIf { it.isNotBlank() && it.length <= 128 }
            if (ackedId != null) {
                val ack = buildJsonObject {
                    put("type", SERVICE_MESSAGE_ACK_TYPE)
                    put("messageId", ackedId)
                }.toString()
                runCatching { serviceSession.send(Frame.Text(ack)) }
            }
        }

    } catch (e: Exception) {
        logger.warn("[!] Mesaj parse hatasi: ${e.javaClass.simpleName}")
    }
}
