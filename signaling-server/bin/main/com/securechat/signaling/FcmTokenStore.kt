package com.securechat.signaling

import java.util.concurrent.ConcurrentHashMap

/**
 * Kullanici FCM token'larini yoneten in-memory store.
 * userId -> fcmToken eslesmesini tutar.
 *
 * Not: Production'da Redis/PostgreSQL ile persist edilmeli.
 * Mevcut mimari (UserRegistry, ConnectionManager) ile tutarli olarak in-memory.
 */
class FcmTokenStore {

    // userId -> FCM registration token
    private val tokens = ConcurrentHashMap<String, String>()

    /**
     * Kullanicinin FCM token'ini kaydeder veya gunceller.
     */
    fun registerToken(userId: String, token: String) {
        tokens[userId] = token
        println("[FCM] Token kaydedildi: $userId")
    }

    /**
     * Kullanicinin FCM token'ini siler (logout durumunda).
     */
    fun removeToken(userId: String) {
        tokens.remove(userId)
        println("[FCM] Token silindi: $userId")
    }

    /**
     * Kullanicinin FCM token'ini getirir. Yoksa null doner.
     */
    fun getToken(userId: String): String? = tokens[userId]

    /**
     * Kayitli token sayisini doner.
     */
    fun getTokenCount(): Int = tokens.size
}
