package com.securechat.media

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import com.securechat.media.model.CallSession
import com.securechat.network.model.CallType
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Tum arama bildirimlerini TEK NotificationCompat.CallStyle uzerinde update eden
 * singleton manager. Signal-Android `CallNotificationBuilder.java` patternine
 * dayanir.
 *
 * Tek [RINGING_NOTIFICATION_ID] ile cancel+notify yerine sadece notify
 * (ayni ID) yaparak heads-up dance yapilmadan kullanici acisindan gecisin
 * pürüzsüz olmasini saglar.
 *
 * Asamalar:
 * - [CallNotifType.INCOMING_RINGING]: Gelen arama caliyor (CallStyle.forIncomingCall)
 * - [CallNotifType.INCOMING_CONNECTING]: Kullanici kabul etti, peer connection kurulurken (CallStyle.forOngoingCall)
 * - [CallNotifType.ESTABLISHED]: Arama aktif, FGS ongoing notification (CallStyle.forOngoingCall + Hangup)
 * - [CallNotifType.ENDED]: Bildirimi temizle ([cancel])
 *
 * NOT: [com.securechat.media.IncomingCallHandler] backward compat icin
 * korunur ve bu manager'in metotlarini cagiracak sekilde refactor edildi.
 */
@Singleton
class CallNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        /** Tum aramalar icin TEK notification ID (incoming/connecting/active update). */
        const val RINGING_NOTIFICATION_ID = 1200

        const val INCOMING_CALL_CHANNEL_ID = "incoming_call_channel"
        const val ONGOING_CALL_CHANNEL_ID = "call_channel"

        const val ACTION_ACCEPT = "com.securechat.media.ACTION_ACCEPT"
        const val ACTION_REJECT = "com.securechat.media.ACTION_REJECT"
        const val ACTION_HANGUP = "com.securechat.media.ACTION_HANGUP"
        const val EXTRA_CALL_ID = "call_id"
    }

    enum class CallNotifType { INCOMING_RINGING, INCOMING_CONNECTING, ESTABLISHED, ENDED }

    /**
     * Iki notification kanalini olusturur (idempotent).
     * Ringing kanali sessiz — ses RingtonePlayer tarafindan calar.
     * Ongoing kanali sessiz — sadece persistent banner gosterir.
     */
    fun ensureChannels() {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(INCOMING_CALL_CHANNEL_ID) == null) {
            val ringChannel = NotificationChannel(
                INCOMING_CALL_CHANNEL_ID,
                "Gelen Arama",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
                enableLights(true)
                enableVibration(false)
                description = "Gelen arama bildirimleri - kilit ekranında görünür"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ringChannel)
        }
        if (nm.getNotificationChannel(ONGOING_CALL_CHANNEL_ID) == null) {
            val ongoingChannel = NotificationChannel(
                ONGOING_CALL_CHANNEL_ID,
                "Aktif Arama",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
            }
            nm.createNotificationChannel(ongoingChannel)
        }
    }

    /**
     * Tum durum gecislerini ayni ID uzerinden update eder.
     *
     * @param type Hedef durum
     * @param session Aktif CallSession (callId, peerId, callType)
     * @param peerName Gosterilecek arayan/aranan ismi
     * @param fullScreenActivityClass INCOMING_RINGING icin full-screen Activity sinifi
     */
    fun show(
        type: CallNotifType,
        session: CallSession,
        peerName: String,
        fullScreenActivityClass: Class<*>? = null
    ) {
        ensureChannels()
        val notification = when (type) {
            CallNotifType.INCOMING_RINGING ->
                buildIncomingNotification(session, peerName, fullScreenActivityClass)
            CallNotifType.INCOMING_CONNECTING ->
                buildConnectingNotification(session, peerName)
            CallNotifType.ESTABLISHED ->
                buildEstablishedNotification(session, peerName)
            CallNotifType.ENDED -> {
                cancel()
                return
            }
        }
        try {
            NotificationManagerCompat.from(context).notify(RINGING_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS izni yoksa sessizce devam et
        }
    }

    /** Ayni ID ile bildirimi siler — sadece arama tamamen bittiginde cagir. */
    fun cancel() {
        NotificationManagerCompat.from(context).cancel(RINGING_NOTIFICATION_ID)
    }

    // ---- Internal builders ----

    private fun buildIncomingNotification(
        session: CallSession,
        peerName: String,
        fullScreenActivityClass: Class<*>?
    ): android.app.Notification {
        val acceptPi = PendingIntent.getBroadcast(
            context, 0,
            Intent(ACTION_ACCEPT).apply {
                setPackage(context.packageName)
                putExtra(EXTRA_CALL_ID, session.callId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val rejectPi = PendingIntent.getBroadcast(
            context, 1,
            Intent(ACTION_REJECT).apply {
                setPackage(context.packageName)
                putExtra(EXTRA_CALL_ID, session.callId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isVideo = session.callType == CallType.VIDEO
        val caller = Person.Builder()
            .setName(peerName)
            .setImportant(true)
            .build()

        val callStyle = NotificationCompat.CallStyle.forIncomingCall(caller, rejectPi, acceptPi)
            .setIsVideo(isVideo)

        val builder = NotificationCompat.Builder(context, INCOMING_CALL_CHANNEL_ID)
            .setStyle(callStyle)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addPerson(caller)
            .setTimeoutAfter(45_000)

        if (fullScreenActivityClass != null) {
            val fullScreenIntent = Intent(context, fullScreenActivityClass).apply {
                putExtra("peer_id", session.peerId)
                putExtra("peer_name", peerName)
                putExtra("call_type", session.callType.name)
                putExtra("fcm_pending", session.callId.startsWith("fcm_pending_"))
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
            }
            val fullScreenPi = PendingIntent.getActivity(
                context, 2, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setFullScreenIntent(fullScreenPi, true)
            builder.setContentIntent(fullScreenPi)
        }

        return builder.build()
    }

    private fun buildConnectingNotification(
        session: CallSession,
        peerName: String
    ): android.app.Notification {
        val hangupPi = buildHangupPendingIntent()
        val caller = Person.Builder().setName(peerName).setImportant(true).build()
        val callStyle = NotificationCompat.CallStyle.forOngoingCall(caller, hangupPi)
            .setIsVideo(session.callType == CallType.VIDEO)

        return NotificationCompat.Builder(context, ONGOING_CALL_CHANNEL_ID)
            .setStyle(callStyle)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addPerson(caller)
            .setContentTitle("Bağlanıyor…")
            .setContentText(peerName)
            .build()
    }

    private fun buildEstablishedNotification(
        session: CallSession,
        peerName: String
    ): android.app.Notification {
        val hangupPi = buildHangupPendingIntent()
        val caller = Person.Builder().setName(peerName).setImportant(true).build()
        val callStyle = NotificationCompat.CallStyle.forOngoingCall(caller, hangupPi)
            .setIsVideo(session.callType == CallType.VIDEO)

        return NotificationCompat.Builder(context, ONGOING_CALL_CHANNEL_ID)
            .setStyle(callStyle)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addPerson(caller)
            .setContentTitle("Arama devam ediyor")
            .setContentText(peerName)
            .build()
    }

    private fun buildHangupPendingIntent(): PendingIntent {
        // Mevcut CallForegroundService HANGUP action'ini PendingIntent.getService ile
        // tetikler — boylece notification'dan kapatma akisi tek kanaldan yonetilir.
        val hangupIntent = Intent(context, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_HANGUP
        }
        return PendingIntent.getService(
            context, 3, hangupIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
