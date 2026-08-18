package com.securechat.app

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat

class SecureChatCallService : Service() {
    companion object {
        private const val ACTION_START = "com.securechat.app.START_CALL_SERVICE"
        private const val ACTION_HANGUP = "com.securechat.app.HANGUP_CALL_SERVICE"
        private const val EXTRA_CALL_ID = "securechat.service_call_id"
        private const val EXTRA_PEER_ID = "securechat.service_peer_id"
        private const val EXTRA_PEER_NAME = "securechat.service_peer_name"
        private const val EXTRA_HAS_VIDEO = "securechat.service_has_video"
        private const val EXTRA_REDACT = "securechat.service_redact"
        private const val EXTRA_CONNECTING = "securechat.service_connecting"

        internal fun start(context: Context, info: NativeCallInfo, connecting: Boolean) {
            val intent = Intent(context, SecureChatCallService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CALL_ID, info.callId)
                putExtra(EXTRA_PEER_ID, info.peerId)
                putExtra(EXTRA_PEER_NAME, info.peerName)
                putExtra(EXTRA_HAS_VIDEO, info.hasVideo)
                putExtra(EXTRA_REDACT, info.redactIdentity)
                putExtra(EXTRA_CONNECTING, connecting)
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (error: RuntimeException) {
                Log.w("SecureChatCallService", "phoneCall foreground service could not start", error)
            }
        }

        internal fun stop(context: Context) {
            context.stopService(Intent(context, SecureChatCallService::class.java))
        }

        internal fun hangupPendingIntent(context: Context, callId: String): PendingIntent {
            val intent = Intent(context, SecureChatCallService::class.java).apply {
                action = ACTION_HANGUP
                putExtra(EXTRA_CALL_ID, callId)
            }
            return PendingIntent.getService(
                context,
                1207,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    private val notifications by lazy {
        SecureChatCallNotificationManager(applicationContext)
    }

    override fun onCreate() {
        super.onCreate()
        notifications.ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANGUP) {
            val callId = intent.getStringExtra(EXTRA_CALL_ID)
            if (!callId.isNullOrBlank()) NativeCallRegistry.emit("end", callId)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val info = intent?.toCallInfo()
        if (intent?.action != ACTION_START || info == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        NativeCallRegistry.remember(
            info.callId,
            info.peerId,
            info.peerName,
            info.hasVideo,
            info.redactIdentity
        )
        val notification = notifications.buildOngoing(
            info,
            connecting = intent.getBooleanExtra(EXTRA_CONNECTING, true)
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SecureChatCallNotificationManager.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(SecureChatCallNotificationManager.NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun Intent.toCallInfo(): NativeCallInfo? {
        val callId = getStringExtra(EXTRA_CALL_ID)?.takeIf { it.isNotBlank() } ?: return null
        val peerId = getStringExtra(EXTRA_PEER_ID)?.takeIf { it.isNotBlank() } ?: return null
        val peerName = getStringExtra(EXTRA_PEER_NAME)?.takeIf { it.isNotBlank() } ?: return null
        return NativeCallInfo(
            callId = callId,
            peerId = peerId,
            peerName = peerName,
            hasVideo = getBooleanExtra(EXTRA_HAS_VIDEO, false),
            redactIdentity = getBooleanExtra(EXTRA_REDACT, true)
        )
    }
}
