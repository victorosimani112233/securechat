package com.securechat.signaling

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.ApnsConfig
import com.google.firebase.messaging.Aps
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
class FcmPushSender private constructor(
    /**
     * Bu sinifin token deposundan ihtiyaci olan tek yetenek. Dar kontrat,
     * push kapisinin veritabani olmadan da dogrulanabilmesini saglar.
     */
    private val tokenLookup: (String) -> String?,
    private val pushHintKeyLookup: (String) -> ByteArray?,
    /** Gecersiz oldugu FCM tarafindan bildirilen token'i siler. */
    private val tokenRemover: (String) -> Unit,
    /**
     * Servis hesabi dosyasinin yolu. Testler basarisiz baslatma yolunu
     * ancak bu deger disaridan verilebildiginde dogrulayabilir.
     */
    serviceAccountPath: String?,
) {
    constructor(
        tokenStore: FcmTokenStore,
        serviceAccountPath: String? = System.getenv("FIREBASE_SERVICE_ACCOUNT_PATH"),
    ) : this(
        { userId -> tokenStore.getToken(userId) },
        { userId -> tokenStore.getPushHintKey(userId) },
        { userId -> tokenStore.removeToken(userId) },
        serviceAccountPath,
    )


    private var initialized = false
    private val pushHintCipher = PushHintCipher()

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

    /** Zamanlama haritalarindan suresi gecmis girdileri atar. */
    private fun pruneRateLimitMaps(now: Long) {
        if (now - lastPrune < PRUNE_INTERVAL_MS) return
        lastPrune = now
        for (map in listOf(lastPushTime, lastCallPushTime)) {
            map.entries.removeIf { now - it.value > PRUNE_AFTER_MS }
        }
    }

    @Volatile
    private var lastPrune = 0L
    private val PRUNE_INTERVAL_MS = 60_000L
    private val PRUNE_AFTER_MS = 10 * 60_000L

    /** Baslatma denendi ve basarisiz olduysa hata sinifi. */
    @Volatile
    var initializationError: String? = null
        private set

    /** Push gercekten kullanilabilir durumda mi. */
    val isOperational: Boolean get() = initialized

    init {
        try {
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
            // Onceki davranista hata yutuluyordu ve health yalniz env
            // path'inin varligina bakip "enabled" diyordu: push hic
            // calismazken sistem saglikli gorunuyordu.
            initializationError = e.javaClass.simpleName
            log.error("[FCM] Firebase baslatma hatasi: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Push gonderilmeli mi — tek karar noktasi.
     *
     * Gecici sinyaller hic push uretmez. ICE candidate ve SDP answer de
     * uretmez: bunlar SDP Offer'den once cikabildigi icin rate-limiter'i
     * yakip asil "incoming_call" push'unu engelliyorlardi; Redis offline
     * kuyrugundan reconnect'te zaten teslim edilirler.
     *
     * Arama sinyalleri ayri bir haritada sayilir, aksi halde ayni 3 saniye
     * icinde gelen bir delivery_receipt cagri push'unu bloklardi.
     *
     * Haritalar ham UUID degil purpose-separated blind index tutar ve
     * periyodik olarak budanir; aksi halde process omru boyunca yalniz
     * buyurlerdi.
     */
    internal fun allowPush(
        recipientId: String,
        messageType: String,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        if (messageType in transientTypes) return false
        if (messageType in SELF_QUEUED_CALL_TYPES) return false

        val rateLimitMap = if (messageType in callSignalTypes) lastCallPushTime else lastPushTime
        val rateKey = ServerPrivacy.blindIndex("push-rate", recipientId)
        val lastTime = rateLimitMap[rateKey] ?: 0L
        if (now - lastTime < RATE_LIMIT_MS) return false
        rateLimitMap[rateKey] = now
        pruneRateLimitMaps(now)
        return true
    }

    /** Yalniz test: zamanlama haritalarindaki girdi sayisi. */
    internal fun rateMapSizes(): Pair<Int, Int> = lastPushTime.size to lastCallPushTime.size

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

        // Rate-limit: arama sinyalleri ve normal mesajlar AYRI map'ler kullanir
        // Boylece delivery_receipt/message_reaction gibi normal mesajlar
        // SDP Offer'in incoming_call push'unu bloklayamaz
        if (!allowPush(recipientId, messageType)) return false
        val isCallSignal = messageType in callSignalTypes

        val fcmToken = tokenLookup(recipientId) ?: return false
        val pushHintKey = pushHintKeyLookup(recipientId)

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
                .also { builder ->
                    if (pushHintKey != null) {
                        builder.putData(
                            "k",
                            pushHintCipher.seal(pushHintKey, pushHintKind(messageType)),
                        )
                    }
                }
                .setAndroidConfig(
                    AndroidConfig.builder()
                        .setPriority(priority)
                        .setTtl(if (isCallSignal) 30 * 1000 else 0) // Arama: 30sn TTL
                        .build()
                )
                // iOS icin explicit APNs yapilandirmasi. Yalniz AndroidConfig
                // kurulmus bir data-only push, kapali/arka plandaki bir iOS
                // istemcisini uyandirmaz.
                .setApnsConfig(
                    ApnsConfig.builder()
                        .putHeader("apns-push-type", "background")
                        // APNs, arka plan bildirimlerinde yalniz priority 5
                        // kabul eder; `background` + `10` kombinasyonu
                        // `BadPriority` ile reddedilir. Onceki deger yuksek
                        // oncelikli turlerde (mesaj, arama, dosya) 10
                        // gonderiyordu, yani tam da uyandirilmasi gereken
                        // durumlarda iOS push'u sessizce hic ulasmiyordu.
                        // Daha dusuk gecikme gerekirse dogru cozum VoIP ya da
                        // alert push'udur, oncelik yukseltmek degil.
                        .putHeader("apns-priority", APNS_BACKGROUND_PRIORITY)
                        .putHeader(
                            "apns-expiration",
                            if (isCallSignal) {
                                ((System.currentTimeMillis() / 1000) + 30).toString()
                            } else {
                                "0"
                            },
                        )
                        .setAps(
                            // content-available: veri tasiyan sessiz uyandirma.
                            // Alert/badge/sound yok; payload gizliligi korunur.
                            Aps.builder().setContentAvailable(true).build(),
                        )
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
                tokenRemover(recipientId)
                log.info("[FCM] Gecersiz token silindi")
            }
            false
        }
    }

    /**
     * Mesaj tipini JSON string'inden parse eder.
     * classDiscriminator = "type" kullanildigi icin "type" alanini okur.
     */
    fun extractMessageType(messageJson: String): String? = MessageTypes.extract(messageJson)

    companion object {
        private const val RATE_LIMIT_MS = 3000L

        /**
         * APNs arka plan bildirimlerinde zorunlu oncelik.
         *
         * Apple, `apns-push-type: background` ile yalniz `5` kabul eder;
         * `10` gonderilen istek `BadPriority` ile reddedilir.
         */
        internal const val APNS_BACKGROUND_PRIORITY = "5"

        /**
         * Yalniz test: token deposu olmadan yalniz kapi mantigini kurar.
         * Kapi kararinin veritabanina bagimliligi yoktur.
         */
        internal fun forGateTest(serviceAccountPath: String? = null) =
            FcmPushSender({ null }, { null }, {}, serviceAccountPath)

        internal fun pushHintKind(messageType: String): Char =
            if (messageType == "sdp_offer" || messageType == "group_call_invite") {
                PushHintCipher.CALL_KIND
            } else {
                PushHintCipher.MESSAGE_KIND
            }

        /** Kendi push'unu uretmeyen, kuyruktan teslim edilen arama sinyalleri. */
        private val SELF_QUEUED_CALL_TYPES = setOf("ice_candidate", "sdp_answer")
    }
}
