package com.securechat.app.data

import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.securechat.app.IncomingCallActivity
import com.securechat.media.IncomingCallHandler
import com.securechat.media.RingtonePlayer
import com.securechat.media.telecom.TelecomBridge
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
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
 * - incoming_call: Hemen zil caldirir, bildirim gosterir, WS drain baslatir
 */
@AndroidEntryPoint
class SecureChatFcmService : FirebaseMessagingService() {

    @Inject lateinit var fcmTokenManager: FcmTokenManager
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var incomingCallHandler: IncomingCallHandler
    @Inject lateinit var ringtonePlayer: RingtonePlayer
    @Inject lateinit var incomingMessageHandler: IncomingMessageHandler
    @Inject lateinit var telecomBridge: TelecomBridge

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

        when (type) {
            "new_message" -> {
                if (userSession.isLoggedIn) {
                    WebSocketDrainWorker.enqueue(applicationContext)
                }
            }
            "incoming_call" -> {
                if (userSession.isLoggedIn) {
                    handleIncomingCallPush(senderId, messageType)
                }
            }
        }
    }

    /**
     * FCM "incoming_call" push'i geldiginde hemen arama bildirimi gosterir.
     * WebSocket baglantisi beklenmez — kullanici hemen zil sesi duyar.
     * SDP offer WebSocket uzerinden ayri olarak cekilir.
     */
    private fun handleIncomingCallPush(senderId: String, messageType: String) {
        Log.d("FcmService", "Gelen arama push'i isleniyor: sender=$senderId, type=$messageType")

        // Foreground'da WS uzerinden SDP zaten gelecek — duplicate bildirim/Activity gosterme
        if (IncomingMessageHandler.isAppInForeground) {
            Log.d("FcmService", "App foreground'da, FCM push isleme atlandi")
            WebSocketDrainWorker.enqueue(applicationContext)
            return
        }

        // Bildirim kanalini olustur (idempotent)
        incomingCallHandler.initialize()

        val isGroupCall = messageType == "group_call_invite"

        // Gecici CallSession olustur — bildirim icin yeterli bilgi
        val tempSession = CallSession(
            callId = "fcm_pending_${senderId}_${System.currentTimeMillis()}",
            peerId = senderId,
            callType = CallType.VOICE,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            isGroupCall = isGroupCall
        )

        // Zil sesini hemen baslat — kullanici cevap verecegi anda ses calar
        ringtonePlayer.startRinging()
        // WebSocket'i parallel olarak baslat — gercek SDP'yi cek
        WebSocketDrainWorker.enqueue(applicationContext)

        // NOT: CallForegroundService burada baslatilmaz — Android 12+ kisitlamasi.
        // Foreground service IncomingCallActivity.onStart()'tan baslatilir.

        // ONCE peer name resolve et → notification ve Activity'i gercek isimle goster.
        // resolvePeerName senkron tamamlanir (DAO + opsiyonel network fetch).
        // Network gecikmeli olabilir — 1.5s timeout ile bekle, sonra "Bilinmeyen"
        // fallback'i kullan ve geri planda update et.
        scope.launch {
            val groupPrefix = if (isGroupCall) "Grup: " else ""
            val resolvedName = withTimeoutOrNull(1500L) {
                try {
                    val name = incomingMessageHandler.lookupPeerName(senderId)
                    if (name.isNotBlank() && name != senderId) name else null
                } catch (_: Exception) { null }
            }
            val displayName = resolvedName?.let { "$groupPrefix$it" } ?: "Bilinmeyen"
            Log.d("FcmService", "Peer name resolved: '$displayName' (resolved=${resolvedName != null})")

            // 1. ONCELIK: Telecom Framework (SELF_MANAGED) — sistem ringing UI
            // hemen cikar; Bridge.connectionListener.onShowIncomingCallUi
            // IncomingCallActivity'i kendi launch eder. CallStyle heads-up
            // bildirimi VE manuel startActivity ATLANIR — duplicate UI yok.
            //
            // Kullanici Telecom UI'da Kabul/Reddet'e basarsa:
            // - Bridge.onAnswer/onReject CallManager.pendingFcmAccept/Reject set eder
            // - SDP geldiginde CallManager.handleIncomingCall otomatik uygular
            val telecomTaken = try {
                telecomBridge.attemptIncoming(tempSession, displayName)
            } catch (t: Throwable) {
                Log.w("FcmService", "telecomBridge.attemptIncoming hatasi", t)
                false
            }

            if (telecomTaken) {
                Log.i("FcmService", "FCM-pending Telecom path basladi: $displayName")
                return@launch
            }

            // 2. FALLBACK: Telecom yok / kayit basarisiz — eski akis (CallStyle + Activity)
            incomingCallHandler.showIncomingCall(
                session = tempSession,
                peerName = displayName,
                fullScreenActivityClass = IncomingCallActivity::class.java
            )

            try {
                val intent = Intent(this@SecureChatFcmService, IncomingCallActivity::class.java).apply {
                    putExtra("peer_id", senderId)
                    putExtra("peer_name", displayName)
                    putExtra("call_type", "VOICE")
                    putExtra("fcm_pending", true)
                    if (isGroupCall) putExtra("is_group_call", true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                    addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("FcmService", "IncomingCallActivity baslatilamadi: ${e.message}")
            }

            // Eger ilk lookup zaman asimina dustuyse arka planda devam et,
            // bittiginde notification'i tekrar guncelle (resolved isim ile).
            if (resolvedName == null) {
                try {
                    val late = incomingMessageHandler.lookupPeerName(senderId)
                    if (late.isNotBlank() && late != senderId) {
                        val updatedName = "$groupPrefix$late"
                        incomingCallHandler.showIncomingCall(
                            session = tempSession,
                            peerName = updatedName,
                            fullScreenActivityClass = IncomingCallActivity::class.java
                        )
                        Log.d("FcmService", "Peer name geç güncellendi: $updatedName")
                    }
                } catch (e: Exception) {
                    Log.w("FcmService", "Geç peer name resolve edilemedi: ${e.message}")
                }
            }
        }
    }
}
