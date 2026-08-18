package com.securechat.app.debug

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.securechat.app.NativeCallInfo
import com.securechat.app.NativeCallRegistry
import com.securechat.app.SecureChatCallNotificationManager

/** Debug APK-only ADB notification smoke hook. Never merged into release. */
class TestNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("kind") == "call") {
            showCallNotification(context, intent)
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = "elcim_debug_messages"
        manager.createNotificationChannel(
            NotificationChannel(channelId, "Elçim Debug", NotificationManager.IMPORTANCE_HIGH)
        )
        val hidden = intent.getBooleanExtra("hide_content", false)
        val sender = intent.getStringExtra("sender")?.take(80) ?: "Test User"
        val message = intent.getStringExtra("message")?.take(200) ?: "Test message"
        val conversationId = intent.getStringExtra("conversation_id")
            ?.take(128)
            ?.takeIf { it.isNotBlank() }
            ?: "debug-conversation"
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                // flutter_local_notifications launch-response contract.
                action = "SELECT_NOTIFICATION"
                putExtra("notificationId", 900001)
                putExtra("payload", if (hidden) null else conversationId)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                900001,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val builder = Notification.Builder(context, channelId)
        manager.notify(
            900001,
            builder
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(if (hidden) "Elçim" else sender)
                .setContentText(if (hidden) "1 yeni mesaj" else message)
                .setVisibility(if (hidden) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PRIVATE)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .build()
        )
    }

    private fun showCallNotification(context: Context, intent: Intent) {
        val callId = intent.getStringExtra("call_id")
            ?.take(128)
            ?.takeIf { it.isNotBlank() }
            ?: "debug-call-notification"
        val hidden = intent.getBooleanExtra("hide_content", true)
        val info = NativeCallInfo(
            callId = callId,
            peerId = if (hidden) "private" else "debug-peer",
            peerName = if (hidden) "Elçim araması" else
                intent.getStringExtra("sender")?.take(80) ?: "Debug Caller",
            hasVideo = intent.getBooleanExtra("has_video", false),
            redactIdentity = hidden
        )
        NativeCallRegistry.remember(
            info.callId,
            info.peerId,
            info.peerName,
            info.hasVideo,
            info.redactIdentity
        )
        val notifications = SecureChatCallNotificationManager(context.applicationContext)
        when (intent.getStringExtra("state")?.lowercase()) {
            "connecting" -> notifications.showConnecting(info)
            "active" -> notifications.showEstablished(info)
            "ended" -> notifications.cancel()
            else -> notifications.showIncoming(info)
        }
    }
}
