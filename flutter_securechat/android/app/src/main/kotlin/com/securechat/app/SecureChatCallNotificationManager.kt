package com.securechat.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

internal class SecureChatCallNotificationManager(
    private val context: Context
) {
    companion object {
        const val NOTIFICATION_ID = 1200
        const val INCOMING_CHANNEL_ID = "incoming_call_channel"
        const val ONGOING_CHANNEL_ID = "call_channel"
        const val ACTION_NOTIFICATION = "com.securechat.app.CALL_NOTIFICATION_ACTION"
        const val EXTRA_ACTION = "securechat.notification_call_action"
        const val EXTRA_CALL_ID = "securechat.notification_call_id"

        const val ACTION_ANSWER = "answer"
        const val ACTION_END = "end"
        const val ACTION_OPEN = "open"
    }

    fun ensureChannels() {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(INCOMING_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    INCOMING_CHANNEL_ID,
                    context.getString(R.string.incoming_call_channel_name),
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = context.getString(R.string.incoming_call_channel_description)
                    setSound(null, null)
                    enableLights(true)
                    enableVibration(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
            )
        }
        if (manager.getNotificationChannel(ONGOING_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    ONGOING_CHANNEL_ID,
                    context.getString(R.string.ongoing_call_channel_name),
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
            )
        }
    }

    fun showIncoming(info: NativeCallInfo) {
        ensureChannels()
        val person = person(info)
        val notification = NotificationCompat.Builder(context, INCOMING_CHANNEL_ID)
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    person,
                    actionPendingIntent(ACTION_END, info.callId, 1201),
                    actionPendingIntent(ACTION_ANSWER, info.callId, 1202)
                ).setIsVideo(info.hasVideo)
            )
            .setSmallIcon(R.drawable.notification_icon)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentTitle(context.getString(R.string.incoming_call_title))
            .setContentText(info.peerName)
            .setContentIntent(actionPendingIntent(ACTION_OPEN, info.callId, 1203))
            .setFullScreenIntent(actionPendingIntent(ACTION_OPEN, info.callId, 1204), true)
            .setTimeoutAfter(60_000)
            .addPerson(person)
            .build()
        notify(notification)
    }

    fun showConnecting(info: NativeCallInfo) {
        SecureChatCallService.start(context, info, connecting = true)
    }

    fun showEstablished(info: NativeCallInfo) {
        SecureChatCallService.start(context, info, connecting = false)
    }

    fun cancel() {
        SecureChatCallService.stop(context)
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    fun buildOngoing(info: NativeCallInfo, connecting: Boolean): android.app.Notification {
        ensureChannels()
        val person = person(info)
        return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
            .setStyle(
                NotificationCompat.CallStyle.forOngoingCall(
                    person,
                    SecureChatCallService.hangupPendingIntent(context, info.callId)
                ).setIsVideo(info.hasVideo)
            )
            .setSmallIcon(R.drawable.notification_icon)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentTitle(
                context.getString(
                    if (connecting) R.string.call_connecting_title
                    else R.string.call_in_progress_title
                )
            )
            .setContentText(info.peerName)
            .setContentIntent(actionPendingIntent(ACTION_OPEN, info.callId, 1206))
            .addPerson(person)
            .build()
    }

    private fun person(info: NativeCallInfo) = Person.Builder()
        .setName(info.peerName)
        .setImportant(true)
        .build()

    private fun actionPendingIntent(action: String, callId: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = ACTION_NOTIFICATION
            putExtra(EXTRA_ACTION, action)
            putExtra(EXTRA_CALL_ID, callId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun notify(notification: android.app.Notification) {
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Telecom remains usable when notification permission is denied.
        }
    }
}
