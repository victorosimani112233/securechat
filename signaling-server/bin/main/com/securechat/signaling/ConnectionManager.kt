package com.securechat.signaling

import io.ktor.websocket.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * WebSocket baglantilarini, mesaj yonlendirmesini ve presence yonetimini saglayan sinif.
 *
 * Presence sistemi subscription-based calisir:
 * - Sunucu her kullanicinin online/offline durumunu ve lastSeen zamanini tutar
 * - Istemci bir sohbet actiginda o kisi icin presence_subscribe gonderir
 * - Sunucu yalnizca subscribe olan kullanicilara presence degisikliklerini bildirir
 * - Broadcast YAPILMAZ — binlerce kullanicida olceklenir
 */
class ConnectionManager(
    private val fcmPushSender: FcmPushSender? = null
) {

    // userId -> aktif WebSocket session
    private val connections = ConcurrentHashMap<String, WebSocketSession>()

    // Offline mesaj kuyrugu: recipientId -> mesaj listesi
    private val offlineQueue = ConcurrentHashMap<String, ConcurrentLinkedQueue<String>>()

    private val mutex = Mutex()

    // --- Presence State ---
    // userId -> son cevrimdisi zamani
    private val lastSeenMap = ConcurrentHashMap<String, Long>()

    // Uygulama on planda olan kullanicilar (WS bagli + foreground)
    private val foregroundUsers = ConcurrentHashMap.newKeySet<String>()

    // targetUserId -> bu kullanicinin durumunu izleyen subscriber'lar
    private val presenceSubscribers = ConcurrentHashMap<String, MutableSet<String>>()

    suspend fun addConnection(userId: String, session: WebSocketSession) {
        mutex.withLock {
            // Eski baglanti varsa kapat
            connections[userId]?.close(CloseReason(CloseReason.Codes.NORMAL, "Yeni baglanti"))
            connections[userId] = session
            println("[+] Kullanici baglandi: $userId (toplam: ${connections.size})")
        }

        // Offline mesajlari ilet
        deliverOfflineMessages(userId, session)
    }

    suspend fun removeConnection(userId: String) {
        mutex.withLock {
            connections.remove(userId)
            println("[-] Kullanici ayrildi: $userId (toplam: ${connections.size})")
        }

        // Foreground'dan cikar ve lastSeen guncelle
        foregroundUsers.remove(userId)
        val now = System.currentTimeMillis()
        lastSeenMap[userId] = now

        // Subscriber'lara offline bildir
        notifyPresenceChange(userId, isOnline = false, lastSeen = now)

        // Bu kullanicinin subscribe'larini temizle
        cleanupSubscriptions(userId)
    }

    // --- Presence Subscription ---

    /**
     * Istemci bir sohbet actiginda cagirilir.
     * Subscriber listesine ekler ve aninda mevcut durumu doner.
     */
    suspend fun subscribePresence(subscriberId: String, targetUserId: String) {
        presenceSubscribers.getOrPut(targetUserId) { ConcurrentHashMap.newKeySet() }.add(subscriberId)
        // Aninda mevcut durumu gonder
        sendPresenceResponse(subscriberId, targetUserId)
        println("[S+] Presence subscribe: $subscriberId -> $targetUserId")
    }

    /**
     * Istemci sohbetten ciktiginda cagirilir.
     */
    fun unsubscribePresence(subscriberId: String, targetUserId: String) {
        presenceSubscribers[targetUserId]?.remove(subscriberId)
        println("[S-] Presence unsubscribe: $subscriberId -> $targetUserId")
    }

    /**
     * Istemciden gelen presence_update mesajini isler.
     * Broadcast YAPMAZ — sadece sunucu state'ini gunceller ve subscriber'lara bildirir.
     */
    suspend fun handlePresenceUpdate(userId: String, isOnline: Boolean) {
        if (isOnline) {
            foregroundUsers.add(userId)
        } else {
            foregroundUsers.remove(userId)
            lastSeenMap[userId] = System.currentTimeMillis()
        }
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[userId] ?: System.currentTimeMillis())
        notifyPresenceChange(userId, isOnline, lastSeen)
        println("[P] Presence guncellendi: $userId online=$isOnline (subscriber: ${presenceSubscribers[userId]?.size ?: 0})")
    }

    /**
     * Belirli bir kullanicinin mevcut durumunu talep edene gonderir.
     */
    private suspend fun sendPresenceResponse(requesterId: String, targetUserId: String) {
        val session = connections[requesterId] ?: return
        val isOnline = foregroundUsers.contains(targetUserId)
        val lastSeen = if (isOnline) System.currentTimeMillis() else (lastSeenMap[targetUserId] ?: 0)
        val json = buildPresenceJson(targetUserId, requesterId, isOnline, lastSeen)
        try {
            session.send(Frame.Text(json))
        } catch (e: Exception) {
            println("[!] Presence response gonderilemedi: $targetUserId -> $requesterId: ${e.message}")
        }
    }

    /**
     * Durum degisikligini yalnizca subscribe olmus kullanicilara bildirir.
     * Broadcast YAPMAZ — O(subscriber) karmasiklik.
     */
    private suspend fun notifyPresenceChange(userId: String, isOnline: Boolean, lastSeen: Long) {
        val subscribers = presenceSubscribers[userId] ?: return
        if (subscribers.isEmpty()) return
        val json = buildPresenceJson(userId, "subscriber", isOnline, lastSeen)
        for (subscriberId in subscribers) {
            val session = connections[subscriberId] ?: continue
            try {
                session.send(Frame.Text(json))
            } catch (_: Exception) { }
        }
    }

    private fun buildPresenceJson(senderId: String, recipientId: String, isOnline: Boolean, lastSeen: Long): String {
        val now = System.currentTimeMillis()
        return """{"type":"presence_update","senderId":"$senderId","recipientId":"$recipientId","timestamp":$now,"isOnline":$isOnline,"lastSeen":$lastSeen}"""
    }

    /**
     * Kullanici disconnect olunca, onun tum subscription'larini temizler.
     */
    private fun cleanupSubscriptions(userId: String) {
        // Bu kullaniciyi tum subscriber listelerinden cikar
        presenceSubscribers.values.forEach { subscribers ->
            subscribers.remove(userId)
        }
        // Kendi subscriber listesini de temizle (kimse bu kullaniciyi izlemiyor artik)
        // NOT: Bunu silmeyelim — diger kullanicilar hala izliyor olabilir
    }

    // --- Mesaj Yonlendirme ---

    /**
     * Mesaji aliciya yonlendirir.
     * Online ise WebSocket ile aninda iletir.
     * Offline ise kuyruga ekler ve FCM push ile cihazi uyandirir.
     */
    suspend fun routeMessage(senderId: String, recipientId: String, messageJson: String) {
        val recipientSession = connections[recipientId]

        if (recipientSession != null) {
            try {
                recipientSession.send(Frame.Text(messageJson))
                println("[>] Mesaj iletildi: $senderId -> $recipientId")
            } catch (e: Exception) {
                println("[!] Mesaj gonderilemedi: $senderId -> $recipientId: ${e.message}")
                queueAndNotify(senderId, recipientId, messageJson)
            }
        } else {
            println("[Q] Alici cevrimdisi, kuyruga eklendi: $senderId -> $recipientId")
            queueAndNotify(senderId, recipientId, messageJson)
        }
    }

    fun isOnline(userId: String): Boolean = connections.containsKey(userId)

    fun getOnlineUsers(): Set<String> = connections.keys.toSet()

    fun getOnlineCount(): Int = connections.size

    /**
     * Broadcast mesaji gonderenin disindaki tum online kullanicilara iletir.
     * Yalnizca typing_indicator icin kullanilir — presence icin KULLANILMAZ.
     */
    suspend fun broadcastMessage(senderId: String, messageJson: String) {
        connections.forEach { (userId, session) ->
            if (userId != senderId) {
                try {
                    session.send(Frame.Text(messageJson))
                } catch (_: Exception) { }
            }
        }
    }

    // FCM push'lari asenkron gondermek icin ayri scope — mesaj iletimini bloklamaz
    private val fcmScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Mesaji kuyruga ekler ve FCM push'i ASENKRON gonderir.
     * Gecici sinyaller (typing, presence) FCM'den gecmez — FcmPushSender filtreliyor.
     * FCM call mesaj yonlendirmesini BLOKLAMAZ — fire-and-forget.
     */
    private fun queueAndNotify(senderId: String, recipientId: String, messageJson: String) {
        val messageType = fcmPushSender?.extractMessageType(messageJson)

        // Gecici sinyaller offline kuyruga da eklenmez
        val transientTypes = setOf("typing_indicator", "presence_update", "presence_subscribe", "presence_unsubscribe", "audio_data", "video_data")
        if (messageType in transientTypes) {
            return
        }

        queueOfflineMessage(recipientId, messageJson)

        // FCM push'i arka planda gonder — mesaj iletimini bekletmez
        if (fcmPushSender != null && messageType != null) {
            fcmScope.launch {
                fcmPushSender.sendWakeUpPush(recipientId, senderId, messageType)
            }
        }
    }

    private fun queueOfflineMessage(recipientId: String, message: String) {
        offlineQueue.getOrPut(recipientId) { ConcurrentLinkedQueue() }.add(message)
        // Kuyruk boyutunu sinirla (maks 1000 mesaj)
        val queue = offlineQueue[recipientId]
        if (queue != null && queue.size > 1000) {
            queue.poll()
        }
    }

    private suspend fun deliverOfflineMessages(userId: String, session: WebSocketSession) {
        val queue = offlineQueue.remove(userId) ?: return
        var count = 0
        while (queue.isNotEmpty()) {
            val message = queue.poll() ?: break
            try {
                session.send(Frame.Text(message))
                count++
            } catch (e: Exception) {
                // Geri kuyruga ekle
                queueOfflineMessage(userId, message)
                break
            }
        }
        if (count > 0) {
            println("[D] $count offline mesaj iletildi: $userId")
        }
    }
}
