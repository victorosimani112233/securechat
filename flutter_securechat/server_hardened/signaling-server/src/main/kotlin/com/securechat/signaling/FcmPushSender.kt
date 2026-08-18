package com.securechat.signaling

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.AndroidConfig
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingException
import com.google.firebase.messaging.Message
import com.google.firebase.messaging.MessagingErrorCode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.util.concurrent.ConcurrentHashMap
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("FcmPushSender")

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

    // Rate-limit: userId -> son push zamani (ms) — normal mesajlar icin
    private val lastPushTime = ConcurrentHashMap<String, Long>()

    // Rate-limit: userId -> son CALL push zamani (ms) — normal mesajlardan bagimsiz
    // Sebep: delivery_receipt/message_reaction gibi tipler ayni 3sn icinde gelirse
    // SDP Offer push'u rate-limit'e takilip "incoming_call" yerine bildirim gosteriliyordu
    private val lastCallPushTime = ConcurrentHashMap<String, Long>()

    // Arama sinyali tipleri — kendi rate-limit map'ini kullanir
    private val callSignalTypes = setOf("sdp_offer", "call_control", "group_call_invite")

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
                log.info("[FCM] Firebase Admin SDK basariyla baslatildi")
            } else {
                log.info("[FCM] FIREBASE_SERVICE_ACCOUNT_PATH ayarlanmamis — FCM push devre disi")
            }
        } catch (e: Exception) {
            log.info("[FCM] Firebase baslatma hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Belirtilen kullaniciya wake-up push gonderir.
     * Sadece data payload icerir — bildirim gosterilmez, uygulama uyandirilir.
     *
     * @param recipientId Alici kullanici ID'si
     * @param messageType Mesaj tipi (encrypted_message, sdp_offer, vb.)
     * @return Push basariyla gonderildiyse true
     */
    suspend fun sendWakeUpPush(recipientId: String, messageType: String): Boolean {
        if (!initialized) return false

        // Gecici sinyaller FCM'den gecmez
        if (messageType in transientTypes) return false

        // ICE candidate ve SDP answer kendi FCM push'larini gondermez:
        // - ICE candidate'lar SDP Offer'den once uretilip gonderilir
        // - Eger ICE candidate push'i once giderse, rate-limiter SDP Offer push'ini engeller
        // - Bu sinyaller Redis offline kuyruguna eklenir ve WebSocket reconnect'te teslim edilir
        // - SDP Offer push'i cihazi uyandirmak icin yeterlidir
        if (messageType in setOf("ice_candidate", "sdp_answer")) return false

        // Rate-limit: arama sinyalleri ve normal mesajlar AYRI map'ler kullanir
        // Boylece delivery_receipt/message_reaction gibi normal mesajlar
        // SDP Offer'in incoming_call push'unu bloklayamaz
        val isCallSignal = messageType in callSignalTypes
        val rateLimitMap = if (isCallSignal) lastCallPushTime else lastPushTime
        val now = System.currentTimeMillis()
        val lastTime = rateLimitMap[recipientId] ?: 0L
        if (now - lastTime < RATE_LIMIT_MS) {
            return false
        }
        rateLimitMap[recipientId] = now

        val fcmToken = tokenStore.getToken(recipientId) ?: return false

        // FCM priority: arama ve mesaj -> HIGH, diger -> NORMAL
        val priority = when (messageType) {
            "encrypted_message", "sdp_offer", "sdp_answer", "ice_candidate",
            "call_control", "file_transfer", "prekey_bundle" -> AndroidConfig.Priority.HIGH
            else -> AndroidConfig.Priority.NORMAL
        }

        return try {
            // TUM push'lar data-only. Notification payload eklenmez cunku:
            // - Sistem auto-notif gruplanmaz (her mesaj icin ayri jenerik bildirim)
            // - Istemci IncomingMessageHandler.showMessageNotification zaten MessagingStyle +
            //   InboxStyle summary ile sohbet-basina grupluyor
            // - Cift bildirim (jenerik + grouplu) sorununu engeller
            // Data-only HIGH priority push, app process kapali olsa bile onMessageReceived'i
            // tetikler ve WebSocketDrainWorker offline kuyrugu drain eder.
            val messageBuilder = Message.builder()
                .setToken(fcmToken)
                // Push provider sees only a generic wake signal. Sender,
                // conversation, message kind and timestamp are learned after
                // authenticated WebSocket drain on the device.
                .putData("type", "securechat_wake_v2")
                .setAndroidConfig(
                    AndroidConfig.builder()
                        .setPriority(priority)
                        .setTtl(if (isCallSignal) 30 * 1000 else 0) // Arama: 30sn TTL
                        .build()
                )

            val message = messageBuilder.build()

            withContext(Dispatchers.IO) {
                FirebaseMessaging.getInstance().send(message)
            }
            log.info("[FCM] Generic wake push gonderildi")
            true
        } catch (e: Exception) {
            log.info("[FCM] Push gonderilemedi: {}", e.javaClass.simpleName)
            // Gecersiz token ise kaldir
            val messagingCode = (e as? FirebaseMessagingException)?.messagingErrorCode
            if (messagingCode == MessagingErrorCode.UNREGISTERED ||
                messagingCode == MessagingErrorCode.INVALID_ARGUMENT
            ) {
                tokenStore.removeToken(recipientId)
                log.info("[FCM] Gecersiz token silindi")
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
