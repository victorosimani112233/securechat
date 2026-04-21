package com.securechat.app.data

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
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
 * - onMessageReceived: Wake-up push geldiginde WebSocketDrainWorker'i tetikler
 */
@AndroidEntryPoint
class SecureChatFcmService : FirebaseMessagingService() {

    @Inject lateinit var fcmTokenManager: FcmTokenManager
    @Inject lateinit var userSession: UserSession

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

        Log.d("FcmService", "FCM push alindi: type=$type, sender=$senderId, msgType=$messageType")

        if (type == "new_message" && userSession.isLoggedIn) {
            // WebSocketDrainWorker'i tetikle — kisa sureli WS baglantisi kurup mesajlari ceker
            WebSocketDrainWorker.enqueue(applicationContext)
        }
    }
}
