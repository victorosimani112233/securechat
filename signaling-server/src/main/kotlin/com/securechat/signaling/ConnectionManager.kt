package com.securechat.signaling

import io.ktor.websocket.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

class ConnectionManager {

    // userId -> aktif WebSocket session
    private val connections = ConcurrentHashMap<String, WebSocketSession>()

    // Offline mesaj kuyrugu: recipientId -> mesaj listesi
    private val offlineQueue = ConcurrentHashMap<String, ConcurrentLinkedQueue<String>>()

    private val mutex = Mutex()

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
    }

    suspend fun routeMessage(senderId: String, recipientId: String, messageJson: String) {
        val recipientSession = connections[recipientId]

        if (recipientSession != null) {
            try {
                recipientSession.send(Frame.Text(messageJson))
                println("[>] Mesaj iletildi: $senderId -> $recipientId")
            } catch (e: Exception) {
                println("[!] Mesaj gonderilemedi: $senderId -> $recipientId: ${e.message}")
                queueOfflineMessage(recipientId, messageJson)
            }
        } else {
            println("[Q] Alici cevrimdisi, kuyruga eklendi: $senderId -> $recipientId")
            queueOfflineMessage(recipientId, messageJson)
        }
    }

    fun isOnline(userId: String): Boolean = connections.containsKey(userId)

    fun getOnlineUsers(): Set<String> = connections.keys.toSet()

    fun getOnlineCount(): Int = connections.size

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
