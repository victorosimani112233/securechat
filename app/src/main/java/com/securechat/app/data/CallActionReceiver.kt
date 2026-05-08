package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.securechat.app.SecureChatActivity
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

        val callId = intent.getStringExtra(IncomingCallHandler.EXTRA_CALL_ID)
        val userId = userSession.userId

        if (userId == null) {
            android.util.Log.e("CallActionReceiver", "User ID null, action ignore edildi")
            return
        }

        when (intent.action) {
            IncomingCallHandler.ACTION_ACCEPT -> {
                android.util.Log.d("CallActionReceiver", "Arama kabul edildi (bildirimden)")

                // Bildirimi kaldır
                incomingCallHandler.dismissIncomingCall()

                // Arama kabul et — session ACTIVE olur
                callManager.acceptCall(userId)

                // KRITIK: IncomingCallActivity'i baslatMA. Cunku DisposableEffect'i
                // session.state == ACTIVE oldugunda finish() cagirir → activity hemen kapanir
                // ve kullanici hicbir UI gormez ("kabul ettim, hemen kapandi" sorunu).
                // Bunun yerine dogrudan SecureChatActivity'i navigate_to_call ile ac —
                // in-activity accept akisiyla ayni sonuc.
                val callSession = callManager.currentSession
                if (callSession != null) {
                    val activityIntent = Intent(context, SecureChatActivity::class.java).apply {
                        putExtra("navigate_to_call", callSession.peerId)
                        putExtra("call_type", callSession.callType.name)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    context.startActivity(activityIntent)
                }
            }

            IncomingCallHandler.ACTION_REJECT -> {
                android.util.Log.d("CallActionReceiver", "Arama reddedildi (bildirimden)")

                // Bildirimi kaldır
                incomingCallHandler.dismissIncomingCall()

                // Arama reddet
                callManager.rejectCall(userId)
            }
        }
    }
}