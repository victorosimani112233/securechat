package com.securechat.app.data

import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.securechat.app.IncomingCallActivity
import com.securechat.media.IncomingCallHandler
import com.securechat.media.RingtonePlayer
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * FCM push mesajlarini alan servis.
 *
 * GUVENLIK: Bu servis mesaj icerigi ALMAZ.
 * FCM payload sadece "type", "senderId", "messageType" icerir.
 * Gercek mesaj icerigi WebSocket uzerinden offline kuyruktan cekilir.
 *
 * Gorevleri:
 * - onNewToken: Token yenilendiginde sunucuya bildirir
 * - onMessageReceived "new_message": WebSocketDrainWorker tetiklenir
 * - onMessageReceived "incoming_call": Hemen zil + bildirim + Activity, sonra WS drain
 */
@AndroidEntryPoint
class SecureChatFcmService : FirebaseMessagingService() {

    @Inject lateinit var fcmTokenManager: FcmTokenManager
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var incomingCallHandler: IncomingCallHandler
    @Inject lateinit var ringtonePlayer: RingtonePlayer

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FcmService", "Yeni FCM token alindi")
        scope.launch {
            fcmTokenManager.onTokenRefreshed(token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val type = message.data["type"] ?: return
        val senderId = message.data["senderId"] ?: ""
        val messageType = message.data["messageType"] ?: ""
        val sentAt = message.data["sentAt"]?.toLongOrNull()

        // Delivery time olc — eger 30sn+ ise kullanici banner gormeli
        if (sentAt != null) {
            val delayMs = System.currentTimeMillis() - sentAt
            Log.d("FcmService", "FCM push alindi: type=$type, sender=$senderId, msgType=$messageType, delay=${delayMs}ms")
            if (delayMs > 30_000) {
                getSharedPreferences("call_readiness_prefs", MODE_PRIVATE)
                    .edit()
                    .putLong("last_delayed_push_at", System.currentTimeMillis())
                    .putLong("last_delay_ms", delayMs)
                    // dismiss flag'ini sifirla — banner tekrar gorunsun
                    .remove("banner_dismissed_at")
                    .apply()
                Log.w("FcmService", "PUSH GECIKMESI: ${delayMs}ms — banner gosterilecek")
            }
        } else {
            Log.d("FcmService", "FCM push alindi: type=$type, sender=$senderId, msgType=$messageType")
        }

        if (!userSession.isLoggedIn) return

        when (type) {
            "new_message" -> {
                // Wake-up: kisa sureli WS baglantisi kurup mesajlari cek
                WebSocketDrainWorker.enqueue(applicationContext)
            }
            "incoming_call" -> {
                handleIncomingCallPush(senderId, messageType)
            }
        }
    }

    /**
     * "incoming_call" FCM push'u geldiginde:
     *  - Tek gorev: WS bagi kur (drain worker), gercek SDP Offer offline queue'dan gelsin.
     *  - UI ve ringtone TEK YERDEN tetiklenir: IncomingMessageHandler.handleIncomingCall →
     *    CallManager.handleIncomingCall (gercek SDP geldiginde).
     *  - Bu sayede "double-ring" sorunu cozulur (eski kod hem burada hem CallManager'da
     *    ringtone baslatip iki Activity acmaya calisiyordu).
     *  - Bildirim kanali idempotent olarak garanti edilir.
     */
    private fun handleIncomingCallPush(@Suppress("UNUSED_PARAMETER") senderId: String, @Suppress("UNUSED_PARAMETER") messageType: String) {
        // Foreground'daysa: WS zaten acik, SDP gelecek; ekstra is yok.
        if (IncomingMessageHandler.isAppInForeground) {
            Log.d("FcmService", "App foreground'da, FCM call push isleme atlandi")
            WebSocketDrainWorker.enqueue(applicationContext)
            return
        }

        // Bildirim kanali (idempotent) — gercek SDP geldiginde IncomingCallHandler kullanacak
        try {
            incomingCallHandler.initialize()
        } catch (e: Exception) {
            Log.w("FcmService", "Channel init hatasi: ${e.message}")
        }

        // WS drain — gercek SDP Offer offline queue'dan cekilir.
        // CallManager.handleIncomingCall ringtone + Activity + bildirimi tetikler.
        WebSocketDrainWorker.enqueue(applicationContext)
    }
}
