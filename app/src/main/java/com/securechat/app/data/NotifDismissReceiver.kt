package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Bildirim dismiss receiver — kullanici bildirimi swipe ile kapattiginda tetiklenir.
 *
 * Iki action destekler:
 * - NOTIF_DISMISS: tek bir konusmanin bildirimi kapatildi → o konusmanin sayacini sifirla
 * - NOTIF_DISMISS_ALL: summary bildirim kapatildi → tum sayaclari sifirla
 *
 * IncomingMessageHandler.showMessageNotification per-peer ve summary bildirimlerine
 * setDeleteIntent ile baglar.
 */
class NotifDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_DISMISS -> {
                val conversationId = intent.getStringExtra(EXTRA_CONVERSATION_ID) ?: return
                IncomingMessageHandler.clearConversationNotificationCount(conversationId)
            }
            ACTION_DISMISS_ALL -> {
                IncomingMessageHandler.clearNotificationCounts()
            }
        }
    }

    companion object {
        const val ACTION_DISMISS = "com.securechat.app.NOTIF_DISMISS"
        const val ACTION_DISMISS_ALL = "com.securechat.app.NOTIF_DISMISS_ALL"
        const val EXTRA_CONVERSATION_ID = "conversation_id"
    }
}
