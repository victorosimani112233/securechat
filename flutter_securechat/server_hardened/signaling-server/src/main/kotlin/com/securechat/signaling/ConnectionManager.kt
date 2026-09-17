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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.slf4j.LoggerFactory
import java.security.SecureRandom
import java.util.Base64
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

    /**
     * @return baglanti kabul edildiyse true.
     *
     * Kapasite kontrolu kilit **icinde** yapilir; disarida yapildiginda iki
     * es zamanli baglanti ayni "yer var" okumasini paylasip limiti birlikte
     * asabiliyordu. Ayni kullanicinin onceki oturumu varsa kapatilir.
     */
    suspend fun addConnection(userId: String, session: WebSocketSession): Boolean {
        // Shutdown sirasinda yeni baglanti kabul etme
        if (isShuttingDown.get()) {
            session.close(CloseReason(CloseReason.Codes.GOING_AWAY, "Sunucu kapatiliyor"))
            return false
        }
        val previous = mutex.withLock {
            if (!connections.containsKey(userId) && connections.size >= MAX_CONNECTIONS) {
                null to false
            } else {
                val existing = connections.put(userId, session)
                log.info("[+] Kullanici baglandi (toplam: ${connections.size})")
                existing to true
            }
        }
        if (!previous.second) {
            session.close(
                CloseReason(CloseReason.Codes.TRY_AGAIN_LATER, "Sunucu kapasitesi doldu"),
            )
            log.warn("[!] Baglanti reddedildi — limit asildi")
            return false
        }
        previous.first?.close(CloseReason(CloseReason.Codes.NORMAL, "Yeni baglanti"))
        Metrics.wsConnections.increment()
        // Redis'ten offline mesajlari ilet
        deliverOfflineMessages(userId, session)
        return true
    }

    /**
     * Baglanti kapanisinda cagrilir.
     *
     * @param session kapanan oturum. Ayni kullanici yeniden baglandiginda
     *   eski soketin `finally` blogu bu metodu cagirir; kosulsuz `remove`
     *   o anda map'te duran **yeni** soketi silerdi ve kullanici bagliyken
     *   cevrimdisi gorunurdu. Compare-and-remove bunu engeller.
     */
    suspend fun removeConnection(userId: String, session: WebSocketSession? = null) {
        val removed = mutex.withLock {
            if (session == null) {
                connections.remove(userId) != null
            } else {
                connections.remove(userId, session)
            }
        }
        if (!removed) {
            // Yerini yeni bir baglanti almis; presence ve call temizligi
            // yapilmaz, aksi halde canli oturum bozulurdu.
            log.info("[-] Eski baglanti kapandi, yeni baglanti korunuyor")
            return
        }
        mutex.withLock {
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

    /** Bir abonenin izledigi hedef sayisi. Testler temizligi buradan gorur. */
    internal fun subscriptionCount(subscriberId: String): Int =
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
            try { session.send(Frame.Text(json)) } catch (_: Exception) { /* best-effort: kapali soket yut */ }
            return
        }
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[targetUserId] ?: 0)
        val json = buildPresenceJson(targetUserId, requesterId, isOnline, lastSeen)
        try { session.send(Frame.Text(json)) } catch (_: Exception) { /* best-effort: kapali soket yut */ }
    }

    private suspend fun notifyPresenceChange(userId: String, isOnline: Boolean, lastSeen: Long, hideLastSeen: Boolean = false) {
        val subscribers = presenceSubscribers[userId] ?: return
        if (subscribers.isEmpty()) return
        val json = buildPresenceJson(userId, "subscriber", isOnline, lastSeen, hideLastSeen)
        for (subscriberId in subscribers) {
            val session = connections[subscriberId] ?: continue
            try { session.send(Frame.Text(json)) } catch (_: Exception) { /* best-effort: kapali soket yut */ }
        }
    }

    private fun buildPresenceJson(senderId: String, recipientId: String, isOnline: Boolean, lastSeen: Long, hideLastSeen: Boolean = false): String {
        val now = System.currentTimeMillis()
        return buildJsonObject {
            put("type", "presence_update")
            put("senderId", senderId)
            put("recipientId", recipientId)
            put("timestamp", now)
            put("isOnline", isOnline)
            put("lastSeen", lastSeen)
            put("hideLastSeen", hideLastSeen)
        }.toString()
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
        val messageType = MessageTypes.extract(messageJson)
        if (messageType == RELIABLE_MESSAGE_TYPE) {
            val deliverable = queueReliableMessage(recipientId, messageJson) ?: return
            Metrics.messagesQueued.increment()
            val recipientSession = connections[recipientId]
            if (recipientSession == null) {
                log.info("[Q] Alici cevrimdisi, ACK kuyruguna eklendi")
                notifyWakeUp(recipientId, messageType)
                return
            }
            try {
                recipientSession.send(Frame.Text(deliverable))
                Metrics.messagesRouted.increment()
                log.info("[>] ACK bekleyen mesaj iletildi")
            } catch (e: Exception) {
                log.warn("[!] ACK bekleyen mesaj gonderilemedi: ${e.javaClass.simpleName}")
                notifyWakeUp(recipientId, messageType)
            }
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
                try { session.send(Frame.Text(messageJson)) } catch (_: Exception) { /* best-effort: kapali soket yut */ }
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
    private val deliveryRandom = SecureRandom()

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
            val callTypes = MessageTypes.PENDING_CALL
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
                    val msgType = MessageTypes.extract(msg) ?: continue
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

        // Siniflandirma push tasiyicisindan bagimsizdir. Onceden tur yalniz
        // `fcmPushSender` uzerinden okunuyordu; push yapilandirilmamissa tur
        // null kaliyor, gecici sinyaller kuyruga yaziliyor ve dosya
        // parcalari mesaj kovasina dusuyordu.
        val messageType = MessageTypes.extract(messageJson)
        if (messageType in MessageTypes.TRANSIENT) return

        if (messageType == RELIABLE_MESSAGE_TYPE) {
            if (queueReliableMessage(recipientId, messageJson) != null) {
                Metrics.messagesQueued.increment()
                notifyWakeUp(recipientId, messageType)
            }
            return
        }

        // GUVENLIK (H8 fix): file_transfer mesajlari AYRI bucket'a yonlendirilir.
        // Buyuk dosya chunk'lari ana mesaj queue'sunu doldurarak Redis OOM yaratamasin.
        if (messageType == MessageTypes.FILE_TRANSFER) {
            queueOfflineFileTransfer(recipientId, messageJson)
        } else {
            queueOfflineMessage(recipientId, messageJson)
        }
        Metrics.messagesQueued.increment()

        notifyWakeUp(recipientId, messageType)
    }

    private fun notifyWakeUp(recipientId: String, messageType: String?) {
        if (fcmPushSender != null && messageType != null) {
            fcmScope.launch {
                val ok = fcmPushSender.sendWakeUpPush(recipientId, messageType)
                if (ok) Metrics.fcmPushes.increment() else Metrics.fcmPushFailures.increment()
            }
        }
    }

    /**
     * Signal ciphertext'i alici ACK verene kadar RAM-only Redis'te tutar.
     * Gondericinin rastgele deliveryId'si server HMAC'i ile sender+recipient'a
     * baglanir; wire'da yalniz turetilmis, anlamsiz deliveryToken gorunur.
     */
    private fun queueReliableMessage(recipientId: String, messageJson: String): String? {
        return try {
            val original = Json.parseToJsonElement(messageJson).jsonObject
            val senderId = original["senderId"]?.jsonPrimitive?.contentOrNull
                ?.takeIf { it.isNotBlank() }
                ?: LEGACY_SENDER_ID
            val suppliedDeliveryId = original["deliveryId"]?.jsonPrimitive?.contentOrNull
            val deliveryId = suppliedDeliveryId
                ?.takeIf { DELIVERY_ID_REGEX.matches(it) }
                ?: newDeliveryId()
            val deliveryToken = ServerPrivacy.deliveryToken(recipientId, senderId, deliveryId)
            var deliverable = buildJsonObject {
                original.forEach { (key, value) ->
                    if (key != "deliveryId" && key != "deliveryToken") put(key, value)
                }
                put("deliveryToken", deliveryToken)
            }.toString()
            val indexKey = ServerPrivacy.queueKey("delivery", recipientId)
            val orderKey = ServerPrivacy.queueOrderKey("delivery", recipientId)
            val itemKey = ServerPrivacy.queueItemKey("delivery", recipientId, deliveryToken)
            val sealed = ServerPrivacy.sealQueue(recipientId, deliverable)
            RedisManager.use { jedis ->
                purgeExpiredReliable(jedis, recipientId, indexKey, orderKey, System.currentTimeMillis())
                @Suppress("UNCHECKED_CAST")
                val queued = jedis.eval(
                    ENQUEUE_RELIABLE_SCRIPT,
                    listOf(indexKey, itemKey, orderKey),
                    listOf(
                        deliveryToken,
                        sealed,
                        ServerPrivacy.config.offlineQueueTtlSeconds.toString(),
                    ),
                ) as? List<Any?> ?: error("Reliable queue script returned no result")
                val stored = queued.getOrNull(1)?.toString()
                    ?: error("Reliable queue script returned no payload")
                // Duplicate retries receive the first server envelope. The Lua
                // script returns before EXPIRE/ZADD, so retention is not renewed.
                deliverable = ServerPrivacy.openQueue(recipientId, stored)
                enforceReliableQueueLimits(jedis, recipientId, indexKey)
            }
            deliverable
        } catch (e: Exception) {
            // Kuyruga yazilamayan reliable frame sokete de yollanmaz. Aksi halde
            // socket send basarili gorunup process cokunce sessiz mesaj kaybi olur.
            log.warn("[!] Redis reliable delivery queue hatasi: ${e.javaClass.simpleName}")
            null
        }
    }

    fun acknowledgeDelivery(recipientId: String, deliveryToken: String): Boolean {
        if (!DELIVERY_ID_REGEX.matches(deliveryToken)) return false
        return try {
            val indexKey = ServerPrivacy.queueKey("delivery", recipientId)
            val orderKey = ServerPrivacy.queueOrderKey("delivery", recipientId)
            val itemKey = ServerPrivacy.queueItemKey("delivery", recipientId, deliveryToken)
            RedisManager.use { jedis ->
                val transaction = jedis.multi()
                val removedPayload = transaction.del(itemKey)
                val removedIndex = transaction.zrem(indexKey, deliveryToken)
                transaction.exec()
                val removed = (removedPayload.get() ?: 0L) > 0L || (removedIndex.get() ?: 0L) > 0L
                if (jedis.zcard(indexKey) == 0L) jedis.del(indexKey, orderKey)
                removed
            }
        } catch (e: Exception) {
            log.warn("[!] Delivery ACK Redis hatasi: ${e.javaClass.simpleName}")
            false
        }
    }

    private fun purgeExpiredReliable(
        jedis: redis.clients.jedis.Jedis,
        recipientId: String,
        indexKey: String,
        orderKey: String,
        nowMs: Long,
    ) {
        val cutoff = nowMs - ServerPrivacy.config.offlineQueueTtlSeconds * 1000L
        val expired = jedis.zrangeByScore(indexKey, "-inf", cutoff.toDouble().toString()) ?: emptySet()
        if (expired.isEmpty()) return
        val itemKeys = expired.map {
            ServerPrivacy.queueItemKey("delivery", recipientId, it)
        }.toTypedArray()
        if (itemKeys.isNotEmpty()) jedis.del(*itemKeys)
        jedis.zrem(indexKey, *expired.toTypedArray())
        if (jedis.zcard(indexKey) == 0L) jedis.del(indexKey, orderKey)
    }

    private fun enforceReliableQueueLimits(
        jedis: redis.clients.jedis.Jedis,
        recipientId: String,
        indexKey: String,
    ) {
        val ordered = jedis.zrange(indexKey, 0, -1)?.toMutableList() ?: return
        if (ordered.isEmpty()) return
        val itemKeys = ordered.map {
            ServerPrivacy.queueItemKey("delivery", recipientId, it)
        }
        val payloads = jedis.mget(*itemKeys.toTypedArray())
        var totalBytes = payloads.sumOf { it?.length?.toLong() ?: 0L }
        var removeCount = (ordered.size - OFFLINE_QUEUE_MAX_MESSAGES.toInt()).coerceAtLeast(0)
        for (index in 0 until removeCount) {
            totalBytes -= payloads[index]?.length?.toLong() ?: 0L
        }
        var cursor = removeCount
        while (totalBytes > OFFLINE_QUEUE_MAX_BYTES && cursor < ordered.size) {
            totalBytes -= payloads[cursor]?.length?.toLong() ?: 0L
            cursor++
        }
        removeCount = cursor
        if (removeCount <= 0) return
        val evicted = ordered.take(removeCount)
        jedis.del(*evicted.map {
            ServerPrivacy.queueItemKey("delivery", recipientId, it)
        }.toTypedArray())
        jedis.zrem(indexKey, *evicted.toTypedArray())
    }

    private fun newDeliveryId(): String = ByteArray(32)
        .also(deliveryRandom::nextBytes)
        .let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) }

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
        private const val RELIABLE_MESSAGE_TYPE = "encrypted_message"
        private const val LEGACY_SENDER_ID = "legacy"
        private val DELIVERY_ID_REGEX = Regex("^[A-Za-z0-9_-]{43}$")
        private val ENQUEUE_RELIABLE_SCRIPT = """
            local existing = redis.call('GET', KEYS[2])
            if existing then
              return {0, existing}
            end
            local server_time = redis.call('TIME')
            local score = tonumber(server_time[1]) * 1000 + tonumber(server_time[2]) / 1000
            local previous = tonumber(redis.call('GET', KEYS[3]) or '0')
            if score <= previous then
              score = previous + 0.001
            end
            local score_text = string.format('%.3f', score)
            redis.call('SET', KEYS[3], score_text, 'EX', ARGV[3])
            redis.call('SET', KEYS[2], ARGV[2], 'EX', ARGV[3])
            redis.call('ZADD', KEYS[1], score_text, ARGV[1])
            redis.call('EXPIRE', KEYS[1], ARGV[3])
            return {1, ARGV[2]}
        """.trimIndent()
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
            deliverReliableMessages(userId, session)
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
                    // Bayat SDP teklifi filtresi push tasiyicisina bagli
                    // olmamali; push kapaliyken eski teklifler teslim edilirdi.
                    val msgType = MessageTypes.extract(message)
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

    /** Reliable ciphertext kalici yerel isleme ACK'i gelene kadar silinmez. */
    private suspend fun deliverReliableMessages(userId: String, session: WebSocketSession) {
        val indexKey = ServerPrivacy.queueKey("delivery", userId)
        val orderKey = ServerPrivacy.queueOrderKey("delivery", userId)
        val stored = RedisManager.use { jedis ->
            purgeExpiredReliable(jedis, userId, indexKey, orderKey, System.currentTimeMillis())
            val tokens = jedis.zrange(indexKey, 0, -1)?.toList() ?: emptyList()
            val payloads = if (tokens.isEmpty()) emptyList() else jedis.mget(
                *tokens.map { ServerPrivacy.queueItemKey("delivery", userId, it) }.toTypedArray()
            )
            tokens to payloads
        }
        var delivered = 0
        for ((index, token) in stored.first.withIndex()) {
            val sealed = stored.second.getOrNull(index)
            if (sealed == null) {
                RedisManager.use { jedis -> jedis.zrem(indexKey, token) }
                continue
            }
            val message = try {
                ServerPrivacy.openQueue(userId, sealed)
            } catch (_: Exception) {
                RedisManager.use { jedis ->
                    jedis.del(ServerPrivacy.queueItemKey("delivery", userId, token))
                    jedis.zrem(indexKey, token)
                }
                continue
            }
            try {
                session.send(Frame.Text(message))
                delivered++
            } catch (_: Exception) {
                return
            }
        }
        if (delivered > 0) log.info("[D] $delivered ACK bekleyen ciphertext yeniden iletildi")
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
            val deliveryIndex = ServerPrivacy.queueKey("delivery", userId)
            val deliveryTokens = jedis.zrange(deliveryIndex, 0, -1) ?: emptySet()
            val itemKeys = deliveryTokens.map {
                ServerPrivacy.queueItemKey("delivery", userId, it)
            }.toTypedArray()
            if (itemKeys.isNotEmpty()) jedis.del(*itemKeys)
            jedis.del(
                ServerPrivacy.queueKey("message", userId),
                ServerPrivacy.queueKey("file", userId),
                deliveryIndex,
                // One-time cleanup for the pre-item-TTL reliable queue shape.
                ServerPrivacy.queuePayloadKey("delivery", userId),
                ServerPrivacy.queueOrderKey("delivery", userId),
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
        val shutdownMsg = buildJsonObject {
            put("type", "server_shutdown")
            put("timestamp", System.currentTimeMillis())
            put("message", "Sunucu yeniden baslatiliyor")
        }.toString()
        var count = 0
        connections.forEach { (_, session) ->
            try {
                session.send(Frame.Text(shutdownMsg))
                count++
            } catch (_: Exception) { /* best-effort: kapali soket yut */ }
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
            } catch (_: Exception) { /* best-effort: kapali soket yut */ }
        }
        log.info("[SHUTDOWN] ${connections.size} baglanti kapatildi")
        connections.clear()
    }
}
