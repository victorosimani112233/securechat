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

                // Arama kabul et
                callManager.acceptCall(userId)

                // IncomingCallActivity'yi başlat (ana arama ekranına geçiş için)
                val callSession = callManager.currentSession
                if (callSession != null) {
                    val activityIntent = Intent(context, IncomingCallActivity::class.java).apply {
                        putExtra("peer_id", callSession.peerId)
                        putExtra("peer_name", callSession.peerId) // TODO: Resolve peer name
                        putExtra("call_type", callSession.callType.name)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
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