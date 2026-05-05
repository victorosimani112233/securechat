package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.securechat.app.IncomingCallActivity
import com.securechat.media.CallManager
import com.securechat.media.IncomingCallHandler
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Gelen arama bildirimi üzerindeki "Kabul Et" ve "Reddet" butonlarından
 * gelen broadcast intent'leri işleyen receiver.
 *
 * Bu receiver uygulama kapalıyken de çalışır ve arama aksiyonlarını
 * doğrudan IncomingCallActivity veya CallManager'a yönlendirir.
 */
@AndroidEntryPoint
class CallActionReceiver : BroadcastReceiver() {

    @Inject lateinit var callManager: CallManager
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var incomingCallHandler: IncomingCallHandler

    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("CallActionReceiver", "Action alındı: ${intent.action}")

        val userId = userSession.userId
        if (userId == null) {
            android.util.Log.e("CallActionReceiver", "User ID null, action ignore edildi")
            return
        }

        when (intent.action) {
            IncomingCallHandler.ACTION_ACCEPT -> {
                android.util.Log.d("CallActionReceiver", "Arama kabul edildi (bildirimden)")

                // Bildirimi ve zil sesini kaldir
                incomingCallHandler.dismissIncomingCall()
                try {
                    val ringtone = com.securechat.media.RingtonePlayer::class.java
                    // RingtonePlayer Singleton oldugu icin dogrudan stop edilmesi gerekir;
                    // Hilt Context'i Receiver'da yok, CallManager.acceptCall icinde de durdurulur.
                } catch (_: Exception) { }

                val session = callManager.currentSession
                if (session != null) {
                    // Normal akis — SDP gelmis, session mevcut
                    callManager.acceptCall(userId)

                    val activityIntent = Intent(context, IncomingCallActivity::class.java).apply {
                        putExtra("peer_id", session.peerId)
                        putExtra("peer_name", session.peerId)
                        putExtra("call_type", session.callType.name)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    context.startActivity(activityIntent)
                } else {
                    // FCM-pending — SDP henuz gelmedi, pending accept ayarla
                    // SDP geldiginde CallManager.handleIncomingCall otomatik kabul edecek
                    android.util.Log.d("CallActionReceiver", "Session null, pendingFcmAccept ayarlandi")
                    callManager.pendingFcmAccept = userId

                    // Kullaniciyi ana ekrana yonlendir — arama ekrani SDP gelince acilacak
                    val activityIntent = Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    context.startActivity(activityIntent)
                }
            }

            IncomingCallHandler.ACTION_REJECT -> {
                android.util.Log.d("CallActionReceiver", "Arama reddedildi (bildirimden)")

                incomingCallHandler.dismissIncomingCall()

                val session = callManager.currentSession
                if (session != null) {
                    callManager.rejectCall(userId)
                } else {
                    // FCM-pending — SDP henuz gelmedi, pending reject ayarla
                    android.util.Log.d("CallActionReceiver", "Session null, pendingFcmReject ayarlandi")
                    callManager.pendingFcmReject = userId
                }
            }
        }
    }
}