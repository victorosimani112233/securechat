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

    /** Bir kullanicinin izleyebilecegi en fazla hedef sayisi. */
    private val MAX_PRESENCE_SUBSCRIPTIONS = 512

    suspend fun addConnection(userId: String, session: WebSocketSession) {
        // Connection limit kontrolu
        if (connections.size >= MAX_CONNECTIONS) {
            session.close(CloseReason(CloseReason.Codes.TRY_AGAIN_LATER, "Sunucu kapasitesi doldu"))
            log.warn("[!] Baglanti reddedildi — limit asildi (${connections.size}/$MAX_CONNECTIONS)")
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
            log.info("[+] Kullanici baglandi (toplam: ${connections.size})")
        }
        Metrics.wsConnections.increment()
        // Redis'ten offline mesajlari ilet
        deliverOfflineMessages(userId, session)
    }

    suspend fun removeConnection(userId: String) {
        mutex.withLock {
            connections.remove(userId)
            log.info("[-] Kullanici ayrildi (toplam: ${connections.size})")
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

    /**
     * Presence aboneligi.
     *
     * Onceki davranista hicbir sinir yoktu: bir kullanici istedigi kadar
     * hedefe abone olabiliyor, abonelik haritalari process omru boyunca
     * buyuyordu. Abone basina tavan hem bellek buyumesini hem de toplu
     * izleme girisimini sinirlar.
     *
     * @return tavan asilmadiysa true.
     */
    suspend fun subscribePresence(subscriberId: String, targetUserId: String): Boolean {
        if (subscriptionCount(subscriberId) >= MAX_PRESENCE_SUBSCRIPTIONS) {
            log.warn("[S!] Presence abonelik tavani asildi")
            return false
        }
        presenceSubscribers.getOrPut(targetUserId) { ConcurrentHashMap.newKeySet() }.add(subscriberId)
        sendPresenceResponse(subscriberId, targetUserId)
        log.info("[S+] Presence aboneligi eklendi")
        return true
    }

    fun unsubscribePresence(subscriberId: String, targetUserId: String) {
        val subscribers = presenceSubscribers[targetUserId] ?: return
        subscribers.remove(subscriberId)
        // Bos kalan hedef anahtari birakilmaz; aksi halde harita yalniz
        // buyur ve hicbir zaman kuculmezdi.
        if (subscribers.isEmpty()) presenceSubscribers.remove(targetUserId, subscribers)
        log.info("[S-] Presence aboneligi kaldirildi")
    }

    private fun subscriptionCount(subscriberId: String): Int =
        presenceSubscribers.values.count { it.contains(subscriberId) }

    suspend fun handlePresenceUpdate(userId: String, isOnline: Boolean, hideLastSeen: Boolean = false) {
        if (hideLastSeen) hideLastSeenUsers.add(userId) else hideLastSeenUsers.remove(userId)
        if (isOnline) {
            foregroundUsers.add(userId)
        } else {
            foregroundUsers.remove(userId)
            lastSeenMap[userId] = System.currentTimeMillis()
        }
        if (hideLastSeen) {
            // BUGFIX: hideLastSeen=true iken isOnline DA gizleniyordu (her zaman false set edilirdi).
            // Bu yuzden kullanici "son gorulmeyi gizle" ayarini acinca cevrimici de kayboluyordu.
            // Dogru davranis: sadece lastSeen=0 gizlenir, isOnline GERCEKçi yayilir.
            notifyPresenceChange(userId, isOnline = isOnline, lastSeen = 0, hideLastSeen = true)
            log.info("[P] Presence guncellendi: online=$isOnline (lastSeen GIZLI)")
            return
        }
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[userId] ?: System.currentTimeMillis())
        notifyPresenceChange(userId, isOnline, lastSeen)
        log.info("[P] Presence guncellendi: online=$isOnline (subscriber: ${presenceSubscribers[userId]?.size ?: 0})")
    }

    private suspend fun sendPresenceResponse(requesterId: String, targetUserId: String) {
        val session = connections[requesterId] ?: return
        // BUGFIX: hideLastSeen kullanicilar icin de GERCEK isOnline doner — sadece lastSeen gizlenir.
        val isOnline = foregroundUsers.contains(targetUserId)
        if (hideLastSeenUsers.contains(targetUserId)) {
            val json = buildPresenceJson(targetUserId, requesterId, isOnline = isOnline, lastSeen = 0, hideLastSeen = true)
            try { session.send(Frame.Text(json)) } catch (_: Exception) { }
            return
        }
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

    /**
     * Routing'e izin verilmeyen sentinel ID'ler. Bunlar kullanici degil, protokol
     * placeholder'lari:
     *   - "SYSTEM": grup olaylari icin synthetic sender; client bunlara READ receipt
     *     yolladiginda yanlislikla offline_queue:SYSTEM olusuyordu (cop birikimi).
     *   - "server": istemcinin sunucuya yonlendirdigi mesajlarda kullanilir (presence
     *     subscribe vs.); recipient olarak gelmesi anlamsiz.
     *   - "broadcast": eskiden tum kullanicilara fanout icin kullaniliyordu, DoS
     *     amplification riski yuzunden disable edildi.
     */
    private val sentinelRecipients = setOf("SYSTEM", "server", "broadcast")

    suspend fun routeMessage(recipientId: String, messageJson: String) {
        // Sentinel ID'ler asla route edilmez, offline queue'ya da girmez — drop + log.
        if (recipientId in sentinelRecipients) {
            log.debug("[X] Sentinel recipient drop")
            return
        }
        val recipientSession = connections[recipientId]
        if (recipientSession != null) {
            try {
                recipientSession.send(Frame.Text(messageJson))
                Metrics.messagesRouted.increment()
                log.info("[>] Mesaj iletildi")
            } catch (e: Exception) {
                log.warn("[!] Mesaj gonderilemedi: ${e.javaClass.simpleName}")
                queueAndNotify(recipientId, messageJson)
            }
        } else {
            log.info("[Q] Alici cevrimdisi, kuyruga eklendi")
            queueAndNotify(recipientId, messageJson)
        }
    }

    fun isOnline(userId: String): Boolean = connections.containsKey(userId)
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
     * Admin-only encrypted log relay (zero-knowledge audit).
     *
     * Sender'in adminPayloads map'inde belirledigi her grup uyesine ayri sifrelenmis
     * payload gonderir. Sunucu icerigi cozemez, log persist etmez. Non-admin'ler de
     * mesaji alir ama adminPayloads'ta kendi userId'leri olmadigi icin decrypt edemez
     * — client tarafinda sessizce filtrelerler.
     *
     * Kalici grup dizini yoktur. Gercek admin yetkisi, her alicinin actigi
     * authenticated E2EE payload icinde cihaz tarafinda dogrulanir.
     */
    suspend fun handleAdminEncryptedLog(
        senderId: String,
        groupId: String,
        eventType: String,
        adminPayloads: Map<String, String>,
        timestamp: Long
    ) {
        val tokenValid = groupId.matches(Regex("^[A-Za-z0-9_-]{43}=?$"))
        val validPayloads = adminPayloads.filter { (recipientId, payload) ->
            recipientId != senderId &&
                runCatching { java.util.UUID.fromString(recipientId) }.isSuccess &&
                payload.isNotBlank() && payload.length <= 262_144
        }
        if (!tokenValid ||
            adminPayloads.size != 1 ||
            validPayloads.size != adminPayloads.size ||
            validPayloads.values.sumOf { it.toByteArray().size } > 2_097_152
        ) {
            log.warn("[!] admin_encrypted_log reddedildi: gecersiz opak routing paketi")
            return
        }

        var onlineCount = 0
        var offlineCount = 0
        coroutineScope {
            val deferreds = validPayloads.map { (recipientId, payload) ->
                async {
                    val individualMessage = buildJsonObject {
                        put("type", "admin_encrypted_log")
                        put("senderId", senderId)
                        put("recipientId", recipientId)
                        put("timestamp", timestamp)
                        put("groupId", groupId)
                        put("eventType", eventType)
                        // Tek alici icin sadece kendi payload'i — ihtimal sizinti engellenir,
                        // baska adminin payload'ini gormezler.
                        put("adminPayloads", buildJsonObject { put(recipientId, payload) })
                    }.toString()

                    val session = connections[recipientId]
                    if (session != null) {
                        val sent = withTimeoutOrNull(2000L) {
                            try {
                                session.send(Frame.Text(individualMessage))
                                true
                            } catch (_: Exception) { false }
                        } ?: false
                        if (sent) recipientId to true
                        else {
                            queueAndNotify(recipientId, individualMessage)
                            recipientId to false
                        }
                    } else {
                        queueAndNotify(recipientId, individualMessage)
                        recipientId to false
                    }
                }
            }
            val results = deferreds.awaitAll()
            onlineCount = results.count { it.second }
            offlineCount = results.count { !it.second }
        }

        log.info("[AL] admin_encrypted_log fanout (online:$onlineCount, offline:$offlineCount)")
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
            val key = ServerPrivacy.activeCallKey(callerId, recipientId)
            val callerIndex = ServerPrivacy.activeCallIndexKey(callerId)
            val recipientIndex = ServerPrivacy.activeCallIndexKey(recipientId)
            RedisManager.use { jedis ->
                jedis.setex(key, ACTIVE_CALL_TTL_SECONDS, "1")
                jedis.sadd(callerIndex, key)
                jedis.sadd(recipientIndex, key)
                jedis.expire(callerIndex, ACTIVE_CALL_TTL_SECONDS)
                jedis.expire(recipientIndex, ACTIVE_CALL_TTL_SECONDS)
            }
            log.info("[call] active session set")
        } catch (e: Exception) {
            log.warn("[!] setActiveCallSession hatasi: ${e.javaClass.simpleName}")
        }
    }

    /** Aktif session var mi (her iki yonde de bakar — A→B ve B→A ayni key). */
    fun hasActiveCallSession(userA: String, userB: String): Boolean {
        return try {
            val key = ServerPrivacy.activeCallKey(userA, userB)
            RedisManager.use { jedis -> jedis.exists(key) }
        } catch (e: Exception) {
            log.warn("[!] hasActiveCallSession hatasi: ${e.javaClass.simpleName}")
            false
        }
    }

    /** Session'i sil — HANGUP/REJECT/BUSY veya WS disconnect zamani. */
    fun clearActiveCallSession(userA: String, userB: String) {
        try {
            val key = ServerPrivacy.activeCallKey(userA, userB)
            val firstIndex = ServerPrivacy.activeCallIndexKey(userA)
            val secondIndex = ServerPrivacy.activeCallIndexKey(userB)
            RedisManager.use { jedis ->
                val deleted = jedis.del(key)
                jedis.srem(firstIndex, key)
                jedis.srem(secondIndex, key)
                if (deleted > 0) log.info("[call] active session cleared")
            }
        } catch (e: Exception) {
            log.warn("[!] clearActiveCallSession hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Belirli kullaniciya ait tum aktif call session'lari sil — WS disconnect
     * zamani cagrilir, peer ile olan call'lar orphan kalmasin diye.
     */
    fun clearAllCallSessionsFor(userId: String) {
        try {
            RedisManager.use { jedis ->
                val indexKey = ServerPrivacy.activeCallIndexKey(userId)
                val keys = jedis.smembers(indexKey)
                if (!keys.isNullOrEmpty()) {
                    jedis.del(*keys.toTypedArray())
                    log.info("[call] WS disconnect ile ${keys.size} active session silindi")
                }
                jedis.del(indexKey)
            }
        } catch (e: Exception) {
            log.warn("[!] clearAllCallSessionsFor hatasi: ${e.javaClass.simpleName}")
        }
    }

    fun purgePendingCallSignals(recipientId: String, callerSenderId: String) {
        try {
            val key = ServerPrivacy.queueKey("message", recipientId)
            val callTypes = setOf("sdp_offer", "ice_candidate", "call_control")
            val senderRegex = """"senderId"\s*:\s*"([^"]+)"""".toRegex()
            var purged = 0
            RedisManager.use { jedis ->
                val all = jedis.zrangeByScore(key, "-inf", "+inf") ?: return@use
                for (stored in all) {
                    val msg = try {
                        ServerPrivacy.openQueue(recipientId, stored)
                    } catch (_: Exception) {
                        jedis.zrem(key, stored)
                        continue
                    }
                    val msgType = fcmPushSender?.extractMessageType(msg) ?: continue
                    if (msgType !in callTypes) continue
                    val sid = senderRegex.find(msg)?.groupValues?.get(1)
                    if (sid == callerSenderId) {
                        jedis.zrem(key, stored)
                        purged++
                    }
                }
            }
            if (purged > 0) {
                log.info("[purge] $purged pending call sinyali silindi")
            }
        } catch (e: Exception) {
            log.warn("[!] purgePendingCallSignals hatasi: ${e.javaClass.simpleName}")
        }
    }

    private fun queueAndNotify(recipientId: String, messageJson: String) {
        // Defense in depth: sentinel ID'ler hicbir kosulda queue'lanmaz.
        // routeMessage zaten erken filtreliyor ama group fanout / direct call'lar da
        // queueAndNotify'a girebilir; burayi da kapatiyoruz.
        if (recipientId in sentinelRecipients) return

        val messageType = fcmPushSender?.extractMessageType(messageJson)
        val transientTypes = setOf("typing_indicator", "presence_update", "presence_subscribe", "presence_unsubscribe", "audio_data", "video_data")
        if (messageType in transientTypes) return

        // GUVENLIK (H8 fix): file_transfer mesajlari AYRI bucket'a yonlendirilir.
        // Buyuk dosya chunk'lari ana mesaj queue'sunu doldurarak Redis OOM yaratamasin.
        if (messageType == "file_transfer") {
            queueOfflineFileTransfer(recipientId, messageJson)
        } else {
            queueOfflineMessage(recipientId, messageJson)
        }
        Metrics.messagesQueued.increment()

        if (fcmPushSender != null && messageType != null) {
            fcmScope.launch {
                val ok = fcmPushSender.sendWakeUpPush(recipientId, messageType)
                if (ok) Metrics.fcmPushes.increment() else Metrics.fcmPushFailures.increment()
            }
        }
    }

    /**
     * Offline mesaji Redis Sorted Set'e ekler.
     * Key: offline_message_v2:{HMAC(userId)}, Score: timestamp, Value: server-AEAD zarf
     *
     * GUVENLIK (H8 fix): Iki kademe sinir uygulanir.
     * 1. Mesaj sayisi: Max 1000 mesaj/user (mevcut)
     * 2. Toplam byte: Max OFFLINE_QUEUE_MAX_BYTES per user (50 MB) — Redis OOM korumasi.
     *    Yeni mesaj eklendiginde toplam byte hesaplanir, asanlardan en eski silinir.
     *
     * TTL production gizlilik politikasiyla sinirlidir (varsayilan 15 dakika,
     * sert ust sinir 1 saat).
     * Redis key'i user ID icermez; deger AES-256-GCM ile server-storage katmaninda
     * ayrica sarilir. Client Signal ciphertext'i bu katmanin icinde kalir.
     */
    private fun queueOfflineMessage(recipientId: String, message: String) {
        try {
            val key = ServerPrivacy.queueKey("message", recipientId)
            val score = System.currentTimeMillis().toDouble()
            val sealed = ServerPrivacy.sealQueue(recipientId, message)
            RedisManager.use { jedis ->
                jedis.zadd(key, score, sealed)
                enforceQueueLimits(jedis, key, OFFLINE_QUEUE_MAX_BYTES)
                jedis.expire(key, ServerPrivacy.config.offlineQueueTtlSeconds)
            }
        } catch (e: Exception) {
            log.warn("[!] Redis offline queue hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * File transfer chunk'lari icin ayri bucket — varsayilan TTL 5 dakika,
     * sert ust sinir 15 dakika ve byte cap dusuk (10 MB/user).
     * Buyuk dosyalar offline kullaniciya hicbir zaman birikmez; gondericinin retry'sine bagli.
     */
    private fun queueOfflineFileTransfer(recipientId: String, message: String) {
        try {
            val key = ServerPrivacy.queueKey("file", recipientId)
            val score = System.currentTimeMillis().toDouble()
            val sealed = ServerPrivacy.sealQueue(recipientId, message)
            RedisManager.use { jedis ->
                jedis.zadd(key, score, sealed)
                enforceQueueLimits(jedis, key, OFFLINE_FILE_MAX_BYTES)
                jedis.expire(key, ServerPrivacy.config.offlineFileTtlSeconds)
            }
        } catch (e: Exception) {
            log.warn("[!] Redis offline file queue hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Queue limit enforcement: hem mesaj sayisi (1000) hem toplam byte cap.
     * Sirayla en eski mesajlari siler ta ki her iki sinir altina dusene kadar.
     */
    private fun enforceQueueLimits(jedis: redis.clients.jedis.Jedis, key: String, maxBytes: Long) {
        // Once mesaj sayisi sinirini uygula
        val size = jedis.zcard(key)
        if (size > OFFLINE_QUEUE_MAX_MESSAGES) {
            jedis.zremrangeByRank(key, 0, size - OFFLINE_QUEUE_MAX_MESSAGES - 1)
        }

        // Toplam byte sinirini uygula (en eski mesajlari siler)
        var iterations = 0
        while (iterations < 50) {  // defansif: en fazla 50 mesaj sil tek seferde
            val all = jedis.zrange(key, 0, -1) ?: break
            val totalBytes = all.sumOf { it.length.toLong() }
            if (totalBytes <= maxBytes) break
            // En eski %10'unu sil (toplu silme — tek tek silmek pahali)
            val toRemove = (all.size / 10).coerceAtLeast(1)
            jedis.zremrangeByRank(key, 0, (toRemove - 1).toLong())
            iterations++
        }
    }

    companion object {
        private const val ACTIVE_CALL_TTL_SECONDS = 300L
        /** Offline queue per-user mesaj sayisi limiti. */
        private const val OFFLINE_QUEUE_MAX_MESSAGES = 1000L
        /** Offline mesaj queue per-user toplam byte limiti (50 MB). Redis OOM korumasi. */
        private const val OFFLINE_QUEUE_MAX_BYTES = 50L * 1024 * 1024
        /** File transfer queue per-user toplam byte limiti (10 MB). */
        private const val OFFLINE_FILE_MAX_BYTES = 10L * 1024 * 1024
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
            val queues = listOf(
                ServerPrivacy.queueKey("message", userId),
                ServerPrivacy.queueKey("file", userId)
            )
            val now = System.currentTimeMillis()
            val sdpOfferMaxAgeMs = 30_000L  // Caller'in ringback toleransi ~30sn
            var count = 0
            var droppedStale = 0
            var droppedInvalid = 0
            for (key in queues) {
                val storedMessages = RedisManager.use { jedis ->
                    jedis.zrangeByScore(key, "-inf", "+inf") ?: emptyList()
                }
                for (stored in storedMessages) {
                    val message = try {
                        ServerPrivacy.openQueue(userId, stored)
                    } catch (_: Exception) {
                        RedisManager.use { jedis -> jedis.zrem(key, stored) }
                        droppedInvalid++
                        continue
                    }
                    val msgType = fcmPushSender?.extractMessageType(message)
                    if (msgType == "sdp_offer") {
                        val ts = extractTimestamp(message)
                        if (ts != null && (now - ts) > sdpOfferMaxAgeMs) {
                            RedisManager.use { jedis -> jedis.zrem(key, stored) }
                            droppedStale++
                            continue
                        }
                    }
                    try {
                        session.send(Frame.Text(message))
                        // Remove only after send. A crash between send/remove may
                        // duplicate once; client message-id dedup is safer than loss.
                        RedisManager.use { jedis -> jedis.zrem(key, stored) }
                        count++
                    } catch (_: Exception) {
                        return
                    }
                }
            }
            if (count > 0) {
                log.info("[D] $count offline mesaj iletildi (Redis)" +
                    if (droppedStale + droppedInvalid > 0)
                        " — $droppedStale stale, $droppedInvalid gecersiz zarf atildi"
                    else "")
            }
        } catch (e: Exception) {
            log.warn("[!] Redis offline delivery hatasi: ${e.javaClass.simpleName}")
        }
    }

    /** Account deletion boundary: socket, presence, call and all queue copies. */
    /**
     * Hesap silmede kullanilan gecici-durum temizligi uc bagimsiz adima
     * ayrildi. Tek blokta calisirken bir adimin hatasi kendinden sonrakileri
     * atliyordu; her biri ayri ayri tekrar calistirilabilir olmalidir.
     */
    suspend fun closeUserSocket(userId: String) {
        mutex.withLock {
            connections.remove(userId)?.close(
                CloseReason(CloseReason.Codes.NORMAL, "Account deleted")
            )
        }
    }

    fun forgetPresenceState(userId: String) {
        foregroundUsers.remove(userId)
        lastSeenMap.remove(userId)
        hideLastSeenUsers.remove(userId)
        presenceSubscribers.remove(userId)
        cleanupSubscriptions(userId)
        clearAllCallSessionsFor(userId)
    }

    fun purgeQueuedEnvelopes(userId: String) {
        RedisManager.use { jedis ->
            jedis.del(
                ServerPrivacy.queueKey("message", userId),
                ServerPrivacy.queueKey("file", userId),
                // One-time cutover cleanup for deployments upgrading from v1.
                "offline_queue:$userId",
                "offline_file:$userId"
            )
        }
    }

    suspend fun purgeUserState(userId: String) {
        closeUserSocket(userId)
        forgetPresenceState(userId)
        purgeQueuedEnvelopes(userId)
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
