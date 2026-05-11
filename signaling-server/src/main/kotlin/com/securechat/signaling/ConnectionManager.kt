package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import io.ktor.websocket.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.slf4j.LoggerFactory
import java.util.concurrent.ConcurrentHashMap

private val log = LoggerFactory.getLogger(ConnectionManager::class.java)

/**
 * WebSocket baglantilarini, mesaj yonlendirmesini ve presence yonetimini saglayan sinif.
 *
 * Offline mesaj kuyrugu Redis Sorted Set ile persist edilir.
 * Presence sistemi subscription-based calisir — broadcast YAPILMAZ.
 */
class ConnectionManager(
    private val fcmPushSender: FcmPushSender? = null
) {

    // userId -> aktif WebSocket session
    private val connections = ConcurrentHashMap<String, WebSocketSession>()

    private val mutex = Mutex()

    // --- Presence State ---
    private val lastSeenMap = ConcurrentHashMap<String, Long>()
    private val foregroundUsers = ConcurrentHashMap.newKeySet<String>()
    private val presenceSubscribers = ConcurrentHashMap<String, MutableSet<String>>()
    private val hideLastSeenUsers = ConcurrentHashMap.newKeySet<String>()

    suspend fun addConnection(userId: String, session: WebSocketSession) {
        // Connection limit kontrolu
        if (connections.size >= MAX_CONNECTIONS) {
            session.close(CloseReason(CloseReason.Codes.TRY_AGAIN_LATER, "Sunucu kapasitesi doldu"))
            log.warn("[!] Baglanti reddedildi — limit asildi: $userId (${connections.size}/$MAX_CONNECTIONS)")
            return
        }
        // Shutdown sirasinda yeni baglanti kabul etme
        if (isShuttingDown.get()) {
            session.close(CloseReason(CloseReason.Codes.GOING_AWAY, "Sunucu kapatiliyor"))
            return
        }
        mutex.withLock {
            connections[userId]?.close(CloseReason(CloseReason.Codes.NORMAL, "Yeni baglanti"))
            connections[userId] = session
            log.info("[+] Kullanici baglandi: $userId (toplam: ${connections.size})")
        }
        Metrics.wsConnections.increment()
        // Redis'ten offline mesajlari ilet
        deliverOfflineMessages(userId, session)
    }

    suspend fun removeConnection(userId: String) {
        mutex.withLock {
            connections.remove(userId)
            log.info("[-] Kullanici ayrildi: $userId (toplam: ${connections.size})")
        }
        foregroundUsers.remove(userId)
        val now = System.currentTimeMillis()
        lastSeenMap[userId] = now
        if (!hideLastSeenUsers.contains(userId)) {
            notifyPresenceChange(userId, isOnline = false, lastSeen = now)
        }
        cleanupSubscriptions(userId)
        // Bu kullaniciya ait active call session'lari temizle — orphan call'i engelle.
        // Network drop sirasinda HANGUP gonderememisse server burada zorla temizler.
        clearAllCallSessionsFor(userId)
    }

    // --- Presence Subscription ---

    suspend fun subscribePresence(subscriberId: String, targetUserId: String) {
        presenceSubscribers.getOrPut(targetUserId) { ConcurrentHashMap.newKeySet() }.add(subscriberId)
        sendPresenceResponse(subscriberId, targetUserId)
        log.info("[S+] Presence subscribe: $subscriberId -> $targetUserId")
    }

    fun unsubscribePresence(subscriberId: String, targetUserId: String) {
        presenceSubscribers[targetUserId]?.remove(subscriberId)
        log.info("[S-] Presence unsubscribe: $subscriberId -> $targetUserId")
    }

    suspend fun handlePresenceUpdate(userId: String, isOnline: Boolean, hideLastSeen: Boolean = false) {
        if (hideLastSeen) hideLastSeenUsers.add(userId) else hideLastSeenUsers.remove(userId)
        if (isOnline) {
            foregroundUsers.add(userId)
        } else {
            foregroundUsers.remove(userId)
            lastSeenMap[userId] = System.currentTimeMillis()
        }
        if (hideLastSeen) {
            notifyPresenceChange(userId, isOnline = false, lastSeen = 0, hideLastSeen = true)
            log.info("[P] Presence guncellendi: $userId online=$isOnline (GIZLI)")
            return
        }
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[userId] ?: System.currentTimeMillis())
        notifyPresenceChange(userId, isOnline, lastSeen)
        log.info("[P] Presence guncellendi: $userId online=$isOnline (subscriber: ${presenceSubscribers[userId]?.size ?: 0})")
    }

    private suspend fun sendPresenceResponse(requesterId: String, targetUserId: String) {
        val session = connections[requesterId] ?: return
        if (hideLastSeenUsers.contains(targetUserId)) {
            val json = buildPresenceJson(targetUserId, requesterId, isOnline = false, lastSeen = 0, hideLastSeen = true)
            try { session.send(Frame.Text(json)) } catch (_: Exception) { }
            return
        }
        val isOnline = foregroundUsers.contains(targetUserId)
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[targetUserId] ?: 0)
        val json = buildPresenceJson(targetUserId, requesterId, isOnline, lastSeen)
        try { session.send(Frame.Text(json)) } catch (_: Exception) { }
    }

    private suspend fun notifyPresenceChange(userId: String, isOnline: Boolean, lastSeen: Long, hideLastSeen: Boolean = false) {
        val subscribers = presenceSubscribers[userId] ?: return
        if (subscribers.isEmpty()) return
        val json = buildPresenceJson(userId, "subscriber", isOnline, lastSeen, hideLastSeen)
        for (subscriberId in subscribers) {
            val session = connections[subscriberId] ?: continue
            try { session.send(Frame.Text(json)) } catch (_: Exception) { }
        }
    }

    private fun buildPresenceJson(senderId: String, recipientId: String, isOnline: Boolean, lastSeen: Long, hideLastSeen: Boolean = false): String {
        val now = System.currentTimeMillis()
        return """{"type":"presence_update","senderId":"$senderId","recipientId":"$recipientId","timestamp":$now,"isOnline":$isOnline,"lastSeen":$lastSeen,"hideLastSeen":$hideLastSeen}"""
    }

    private fun cleanupSubscriptions(userId: String) {
        presenceSubscribers.values.forEach { subscribers -> subscribers.remove(userId) }
    }

    // --- Mesaj Yonlendirme ---

    suspend fun routeMessage(senderId: String, recipientId: String, messageJson: String) {
        val recipientSession = connections[recipientId]
        if (recipientSession != null) {
            try {
                recipientSession.send(Frame.Text(messageJson))
                Metrics.messagesRouted.increment()
                log.info("[>] Mesaj iletildi: $senderId -> $recipientId")
            } catch (e: Exception) {
                log.warn("[!] Mesaj gonderilemedi: $senderId -> $recipientId: ${e.message}")
                queueAndNotify(senderId, recipientId, messageJson)
            }
        } else {
            log.info("[Q] Alici cevrimdisi, kuyruga eklendi: $senderId -> $recipientId")
            queueAndNotify(senderId, recipientId, messageJson)
        }
    }

    fun isOnline(userId: String): Boolean = connections.containsKey(userId)
    fun getOnlineUsers(): Set<String> = connections.keys.toSet()
    fun getOnlineCount(): Int = connections.size
    fun connections(): Map<String, WebSocketSession> = connections

    suspend fun broadcastMessage(senderId: String, messageJson: String) {
        connections.forEach { (userId, session) ->
            if (userId != senderId) {
                try { session.send(Frame.Text(messageJson)) } catch (_: Exception) { }
            }
        }
    }

    /**
     * Grup mesajini sunucu tarafinda fan-out eder.
     * Sender tek mesaj gonderir, sunucu her uye icin ayri mesaj olusturur.
     *
     * @param senderId Gonderen kullanici
     * @param groupId Grup ID'si
     * @param recipientPayloads Her alici icin ayri sifrelenmis payload: {userId -> envelope}
     * @param timestamp Mesaj zaman damgasi
     */
    suspend fun handleGroupMessageFanout(
        senderId: String,
        groupId: String,
        recipientPayloads: Map<String, String>,
        timestamp: Long
    ) {
        // GUVENLIK: Sender grubun gercek uyesi mi? Authorization kontrolu.
        // Onceden hicbir kontrol yoktu — saldirgan herhangi bir gruba mesaj enjekte edebiliyordu.
        val members = GroupMemberStore.getMembers(groupId)
        if (members.isNotEmpty() && senderId !in members) {
            log.warn("[!] Yetkisiz grup fanout girisimi: $senderId -> $groupId (uye degil)")
            return
        }
        // GUVENLIK: Recipient'lar da gercek uye olmali — sender grup uye listesi degistirmemeli.
        val validRecipients = if (members.isNotEmpty()) {
            recipientPayloads.filterKeys { it in members }
        } else {
            // Grup uye listesi henuz sunucuda yoksa (yeni grup), tum recipient'lara izin ver.
            // group_notification mesaji ile uye listesi sync edilince siki kontrol baslar.
            recipientPayloads
        }
        if (validRecipients.size != recipientPayloads.size) {
            log.warn("[!] Grup fanout: ${recipientPayloads.size - validRecipients.size} yetkisiz alici filtrelendi")
        }

        // PERF: Recipient'lara concurrent gonder — slow consumer tum grubu bloklamasin.
        // Her bir send icin 2sn timeout — yavas client'in mesaji offline kuyruga atilir.
        var onlineCount = 0
        var offlineCount = 0

        coroutineScope {
            val deferreds = validRecipients.mapNotNull { (recipientId, envelope) ->
                if (recipientId == senderId) return@mapNotNull null

                val individualMessage = buildJsonObject {
                    put("type", "encrypted_message")
                    put("senderId", senderId)
                    put("recipientId", recipientId)
                    put("timestamp", timestamp)
                    put("envelope", envelope)
                }.toString()

                async {
                    val session = connections[recipientId]
                    if (session != null) {
                        // 2sn timeout: yavas client'in send'i tum fanout'u bloklamasin
                        val sent = withTimeoutOrNull(2000L) {
                            try {
                                session.send(Frame.Text(individualMessage))
                                true
                            } catch (e: Exception) {
                                false
                            }
                        } ?: false
                        if (sent) {
                            Triple(recipientId, individualMessage, true)
                        } else {
                            queueAndNotify(senderId, recipientId, individualMessage)
                            Triple(recipientId, individualMessage, false)
                        }
                    } else {
                        queueAndNotify(senderId, recipientId, individualMessage)
                        Triple(recipientId, individualMessage, false)
                    }
                }
            }
            val results = deferreds.awaitAll()
            onlineCount = results.count { it.third }
            offlineCount = results.count { !it.third }
        }

        // GUVENLIK: setMembers cagrisi KALDIRILDI.
        // Onceden sender'in payload key'leri ile grup uye listesi DELETE+INSERT yapiliyordu —
        // saldirgan istedigi gibi grup uyeligini degistirebiliyordu (grup hijack acigi).
        // Uye listesi yalnizca group_notification mesajlari uzerinden guncellenir.

        Metrics.groupFanouts.increment()
        log.info("[GF] Grup fanout: $senderId -> $groupId (online:$onlineCount, offline:$offlineCount)")
    }

    /**
     * Typing indicator'i grup uyelerine fan-out eder.
     * Sadece online uyelere gonderilir (transient mesaj, offline queue'ya girmez).
     */
    suspend fun handleGroupTypingIndicator(senderId: String, groupId: String, messageJson: String) {
        val members = GroupMemberStore.getMembers(groupId)
        var count = 0
        for (memberId in members) {
            if (memberId == senderId) continue
            val session = connections[memberId] ?: continue
            try {
                session.send(Frame.Text(messageJson))
                count++
            } catch (_: Exception) { }
        }
        if (count > 0) {
            log.info("[T] Typing fanout: $senderId -> $groupId ($count uye)")
        }
    }

    private val fcmScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * HANGUP/REJECT/BUSY signal'i geldiginde recipient'in offline kuyrugundaki
     * AYNI caller'a ait pending call sinyallerini (sdp_offer, ice_candidate, call_control)
     * temizler. Boylece aranan kullanici cevrimici oldugunda eski/iptal edilmis arama
     * tekrar tetiklenmez ("phantom incoming call" onleme).
     */
    // ---- Active Call Session State (Redis) ----

    /**
     * 1-1 arama icin aktif session key'i. A → B SDP_OFFER geldiginde set edilir.
     * HANGUP/REJECT/BUSY/disconnect ile silinir. TTL 5dk — orphan session'lar
     * sessizce expire eder, sonraki gercek call'i engellemez.
     * Boylece ayni cift icin duplicate offer + reconnect-replay senaryolari
     * server seviyesinde de filtrelenir.
     */
    fun setActiveCallSession(callerId: String, recipientId: String) {
        try {
            val key = "active_call:${minOf(callerId, recipientId)}:${maxOf(callerId, recipientId)}"
            RedisManager.use { jedis ->
                jedis.setex(key, 300, "$callerId>$recipientId|${System.currentTimeMillis()}")
            }
            log.info("[call] active session set: $callerId -> $recipientId")
        } catch (e: Exception) {
            log.warn("[!] setActiveCallSession hatasi: ${e.message}")
        }
    }

    /** Aktif session var mi (her iki yonde de bakar — A→B ve B→A ayni key). */
    fun hasActiveCallSession(userA: String, userB: String): Boolean {
        return try {
            val key = "active_call:${minOf(userA, userB)}:${maxOf(userA, userB)}"
            RedisManager.use { jedis -> jedis.exists(key) }
        } catch (e: Exception) {
            log.warn("[!] hasActiveCallSession hatasi: ${e.message}")
            false
        }
    }

    /** Session'i sil — HANGUP/REJECT/BUSY veya WS disconnect zamani. */
    fun clearActiveCallSession(userA: String, userB: String) {
        try {
            val key = "active_call:${minOf(userA, userB)}:${maxOf(userA, userB)}"
            RedisManager.use { jedis ->
                val deleted = jedis.del(key)
                if (deleted > 0) log.info("[call] active session cleared: $userA <-> $userB")
            }
        } catch (e: Exception) {
            log.warn("[!] clearActiveCallSession hatasi: ${e.message}")
        }
    }

    /**
     * Belirli kullaniciya ait tum aktif call session'lari sil — WS disconnect
     * zamani cagrilir, peer ile olan call'lar orphan kalmasin diye.
     */
    fun clearAllCallSessionsFor(userId: String) {
        try {
            RedisManager.use { jedis ->
                val keys = jedis.keys("active_call:*$userId*")
                if (!keys.isNullOrEmpty()) {
                    jedis.del(*keys.toTypedArray())
                    log.info("[call] WS disconnect ile ${keys.size} active session silindi: $userId")
                }
            }
        } catch (e: Exception) {
            log.warn("[!] clearAllCallSessionsFor hatasi: ${e.message}")
        }
    }

    fun purgePendingCallSignals(recipientId: String, callerSenderId: String) {
        try {
            val key = "offline_queue:$recipientId"
            val callTypes = setOf("sdp_offer", "ice_candidate", "call_control")
            val senderRegex = """"senderId"\s*:\s*"([^"]+)"""".toRegex()
            var purged = 0
            RedisManager.use { jedis ->
                val all = jedis.zrangeByScore(key, "-inf", "+inf") ?: return@use
                for (msg in all) {
                    val msgType = fcmPushSender?.extractMessageType(msg) ?: continue
                    if (msgType !in callTypes) continue
                    val sid = senderRegex.find(msg)?.groupValues?.get(1)
                    if (sid == callerSenderId) {
                        jedis.zrem(key, msg)
                        purged++
                    }
                }
            }
            if (purged > 0) {
                log.info("[purge] $callerSenderId -> $recipientId: $purged pending call sinyali silindi")
            }
        } catch (e: Exception) {
            log.warn("[!] purgePendingCallSignals hatasi: ${e.message}")
        }
    }

    private fun queueAndNotify(senderId: String, recipientId: String, messageJson: String) {
        val messageType = fcmPushSender?.extractMessageType(messageJson)
        val transientTypes = setOf("typing_indicator", "presence_update", "presence_subscribe", "presence_unsubscribe", "audio_data", "video_data")
        if (messageType in transientTypes) return

        // Redis Sorted Set'e ekle
        queueOfflineMessage(recipientId, messageJson)
        Metrics.messagesQueued.increment()

        if (fcmPushSender != null && messageType != null) {
            fcmScope.launch {
                val ok = fcmPushSender.sendWakeUpPush(recipientId, senderId, messageType)
                if (ok) Metrics.fcmPushes.increment() else Metrics.fcmPushFailures.increment()
            }
        }
    }

    /**
     * Offline mesaji Redis Sorted Set'e ekler.
     * Key: offline_queue:{userId}, Score: timestamp, Value: mesaj JSON
     * Max 1000 mesaj — en eski silinir. TTL: 14 gun.
     */
    private fun queueOfflineMessage(recipientId: String, message: String) {
        try {
            val key = "offline_queue:$recipientId"
            val score = System.currentTimeMillis().toDouble()
            RedisManager.use { jedis ->
                jedis.zadd(key, score, message)
                // Max 1000 mesaj — en eskileri sil
                val size = jedis.zcard(key)
                if (size > 1000) {
                    jedis.zremrangeByRank(key, 0, size - 1001)
                }
                // 14 gun TTL
                jedis.expire(key, 14 * 24 * 3600)
            }
        } catch (e: Exception) {
            log.warn("[!] Redis offline queue hatasi: ${e.message}")
        }
    }

    /**
     * Kullanici baglandiginda Redis'ten tum offline mesajlari iletir ve siler.
     *
     * Stale SDP Offer filtresi: 60sn'den eski sdp_offer mesajlari teslim EDILMEZ.
     * Sebep: Arayan vazgecmistir, eski offer ile arama baslatmak yanlis.
     * Diger mesaj tipleri (encrypted_message, file_transfer vb.) yas filtresi disinda.
     */
    private suspend fun deliverOfflineMessages(userId: String, session: WebSocketSession) {
        try {
            val key = "offline_queue:$userId"
            val messages = RedisManager.use { jedis ->
                val msgs = jedis.zrangeByScore(key, "-inf", "+inf")
                if (msgs.isNotEmpty()) {
                    jedis.del(key)
                }
                msgs
            }
            if (messages.isNullOrEmpty()) return

            val now = System.currentTimeMillis()
            val sdpOfferMaxAgeMs = 30_000L  // Caller'in ringback toleransi ~30sn
            var count = 0
            var droppedStale = 0
            for (message in messages) {
                // Stale SDP Offer filtresi: timestamp regex ile cek
                val msgType = fcmPushSender?.extractMessageType(message)
                if (msgType == "sdp_offer") {
                    val ts = extractTimestamp(message)
                    if (ts != null && (now - ts) > sdpOfferMaxAgeMs) {
                        droppedStale++
                        continue
                    }
                }
                try {
                    session.send(Frame.Text(message))
                    count++
                } catch (e: Exception) {
                    queueOfflineMessage(userId, message)
                    break
                }
            }
            if (count > 0) {
                log.info("[D] $count offline mesaj iletildi (Redis): $userId" +
                    if (droppedStale > 0) " — $droppedStale stale SDP atildi" else "")
            }
        } catch (e: Exception) {
            log.warn("[!] Redis offline delivery hatasi: ${e.message}")
        }
    }

    /** Mesaj JSON'undan timestamp alanini cek (regex ile, full parse maliyetinden kacin). */
    private fun extractTimestamp(messageJson: String): Long? {
        return try {
            val regex = """"timestamp"\s*:\s*(\d+)""".toRegex()
            regex.find(messageJson)?.groupValues?.get(1)?.toLong()
        } catch (_: Exception) {
            null
        }
    }

    // --- Graceful Shutdown ---

    /**
     * Tum aktif client'lara SERVER_SHUTDOWN mesaji gonderir.
     * Client bu mesaji alinca 5sn sonra reconnect dener.
     */
    suspend fun broadcastServerShutdown() {
        val shutdownMsg = """{"type":"server_shutdown","timestamp":${System.currentTimeMillis()},"message":"Sunucu yeniden baslatiliyor"}"""
        var count = 0
        connections.forEach { (_, session) ->
            try {
                session.send(Frame.Text(shutdownMsg))
                count++
            } catch (_: Exception) { }
        }
        log.info("[SHUTDOWN] $count client'a SERVER_SHUTDOWN mesaji gonderildi")
    }

    /**
     * Tum WebSocket baglantilarini kapatir.
     */
    suspend fun closeAllConnections() {
        connections.forEach { (_, session) ->
            try {
                session.close(CloseReason(CloseReason.Codes.GOING_AWAY, "Sunucu kapatiliyor"))
            } catch (_: Exception) { }
        }
        log.info("[SHUTDOWN] ${connections.size} baglanti kapatildi")
        connections.clear()
    }
}
