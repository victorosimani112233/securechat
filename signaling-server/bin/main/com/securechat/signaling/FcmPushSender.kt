package com.securechat.signaling

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.AndroidConfig
import com.google.firebase.messaging.AndroidNotification
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.Message
import com.google.firebase.messaging.Notification
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Firebase Cloud Messaging uzerinden data-only push mesaji gonderen sinif.
 *
 * GUVENLIK: Mesaj icerigi (envelope, sdp, icerik) ASLA FCM payload'ina eklenmez.
 * FCM sadece "yeni mesaj var, uyan" sinyali gonderir. Gercek mesaj icerigini
 * cihaz WebSocket uzerinden offline kuyruktan ceker.
 *
 * Rate-limit: Ayni kullaniciya 3 saniyede birden fazla push gonderilmez.
 */
class FcmPushSender(private val tokenStore: FcmTokenStore) {

    private var initialized = false

    // Rate-limit: userId -> son push zamani (ms)
    private val lastPushTime = ConcurrentHashMap<String, Long>()

    // Push gonderilmemesi gereken gecici sinyal tipleri
    private val transientTypes = setOf(
        "typing_indicator",
        "presence_update",
        "audio_data",
        "video_data"
    )

    init {
        try {
            val serviceAccountPath = System.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
            if (serviceAccountPath != null) {
                val options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(FileInputStream(serviceAccountPath)))
                    .build()
                FirebaseApp.initializeApp(options)
                initialized = true
                println("[FCM] Firebase Admin SDK basariyla baslatildi")
            } else {
                println("[FCM] FIREBASE_SERVICE_ACCOUNT_PATH ayarlanmamis — FCM push devre disi")
            }
        } catch (e: Exception) {
            println("[FCM] Firebase baslatma hatasi: ${e.message}")
        }
    }

    /**
     * Belirtilen kullaniciya wake-up push gonderir.
     * Sadece data payload icerir — bildirim gosterilmez, uygulama uyandirilir.
     *
     * @param recipientId Alici kullanici ID'si
     * @param senderId Gonderen kullanici ID'si
     * @param messageType Mesaj tipi (encrypted_message, sdp_offer, vb.)
     * @return Push basariyla gonderildiyse true
     */
    suspend fun sendWakeUpPush(recipientId: String, senderId: String, messageType: String): Boolean {
        if (!initialized) return false

        // Gecici sinyaller FCM'den gecmez
        if (messageType in transientTypes) return false

        // Rate-limit: Ayni kullaniciya 3 saniyede birden fazla push yok
        val now = System.currentTimeMillis()
        val lastTime = lastPushTime[recipientId] ?: 0L
        if (now - lastTime < RATE_LIMIT_MS) {
            return false
        }
        lastPushTime[recipientId] = now

        val fcmToken = tokenStore.getToken(recipientId) ?: return false

        // FCM priority: arama ve mesaj -> HIGH, diger -> NORMAL
        val priority = when (messageType) {
            "encrypted_message", "sdp_offer", "sdp_answer", "ice_candidate",
            "call_control", "file_transfer", "prekey_bundle" -> AndroidConfig.Priority.HIGH
            else -> AndroidConfig.Priority.NORMAL
        }

        return try {
            // Notification payload — Oppo/Xiaomi gibi telefonlar data-only mesajlari
            // arka planda engelliyor. Notification ekleyince sistem mesaji gosterir ve
            // uygulamayi uyandirir. Icerik ASLA eklenmez.
            val notificationTitle = when (messageType) {
                "sdp_offer", "call_control" -> "Gelen arama"
                "file_transfer" -> "Yeni dosya"
                else -> "Yeni mesaj"
            }

            val message = Message.builder()
                .setToken(fcmToken)
                .putData("type", "new_message")
                .putData("senderId", senderId)
                .putData("messageType", messageType)
                .setNotification(
                    Notification.builder()
                        .setTitle(notificationTitle)
                        .setBody("Yeni bir mesajınız var")
                        .build()
                )
                .setAndroidConfig(
                    AndroidConfig.builder()
                        .setPriority(priority)
                        .setNotification(
                            AndroidNotification.builder()
                                .setChannelId("elcim_messages_v4")
                                .setClickAction("OPEN_CHAT")
                                .build()
                        )
                        .build()
                )
                .build()

            val messageId = withContext(Dispatchers.IO) {
                FirebaseMessaging.getInstance().send(message)
            }
            println("[FCM] Push gonderildi: $senderId -> $recipientId (type=$messageType, id=$messageId)")
            true
        } catch (e: Exception) {
            println("[FCM] Push gonderilemedi: $recipientId — ${e.message}")
            // Gecersiz token ise kaldir
            if (e.message?.contains("not a valid FCM registration token") == true ||
                e.message?.contains("Requested entity was not found") == true
            ) {
                tokenStore.removeToken(recipientId)
                println("[FCM] Gecersiz token silindi: $recipientId")
            }
            false
        }
    }

    /**
     * Mesaj tipini JSON string'inden parse eder.
     * classDiscriminator = "type" kullanildigi icin "type" alanini okur.
     */
    fun extractMessageType(messageJson: String): String? {
        return try {
            // Basit regex ile "type" alanini cek — full JSON parse gereksiz
            val regex = """"type"\s*:\s*"([^"]+)"""".toRegex()
            regex.find(messageJson)?.groupValues?.get(1)
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val RATE_LIMIT_MS = 3000L
    }
}
