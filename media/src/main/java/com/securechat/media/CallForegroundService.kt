package com.securechat.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.securechat.common.UserIdentityProvider
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Arama sirasinda arka planda calisan foreground service.
 *
 * Sorumluluklari:
 * - Aramanin arka planda devam etmesini saglar
 * - Surekli bildirim gosterir (arama devam ediyor)
 * - Proximity sensor ile kulak yakininda ekrani kapatir
 * - Kullaniciya bildirimden arama kapatma imkani sunar
 */
@AndroidEntryPoint
class CallForegroundService : Service() {

    @Inject lateinit var callManager: CallManager
    @Inject lateinit var userIdentityProvider: UserIdentityProvider

    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val CALL_NOTIFICATION_ID = 1100  // Daha guvenli aralik
        const val CHANNEL_ID = "call_channel"
        const val ACTION_HANGUP = "com.securechat.media.ACTION_HANGUP"

        /**
         * Foreground service'i baslatir.
         * API 26+ icin startForegroundService kullanilir.
         */
        fun start(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java)
            context.startForegroundService(intent)
        }

        /**
         * Foreground service'i durdurur.
         */
        fun stop(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANGUP) {
            // DoÄŸru user ID'yi UserIdentityProvider'dan al
            val currentUserId = userIdentityProvider.currentUserId ?: "unknown"
            callManager.endCall(currentUserId)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(CALL_NOTIFICATION_ID, createCallNotification())
        acquireProximityWakeLock()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
    }

    /**
     * Arama bildirimi icin notification channel olusturur.
     */
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Aktif Arama",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    /**
     * Devam eden arama icin bildirim olusturur.
     * "Kapat" aksiyonu ile arama sonlandirilebilir.
     */
    private fun createCallNotification(): Notification {
        val hangupIntent = Intent(this, CallForegroundService::class.java).apply {
            action = ACTION_HANGUP
        }
        val hangupPi = PendingIntent.getService(
            this, 0, hangupIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Aktif aramayi gosteren callback intent — bildirime tap → CallScreen acilir
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val tapPi = if (tapIntent != null) {
            PendingIntent.getActivity(
                this, 1, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        // Arayan kisi bilgisi (oturum varsa peerName, yoksa "Devam eden arama")
        val session = callManager.currentSession
        val peerName = session?.peerId ?: "Bilinmeyen"
        val callType = if (session?.callType?.name == "VIDEO") "Görüntülü arama" else "Sesli arama"
        val startTime = session?.startTime

        // Madde 8: NotificationCompat.CallStyle.forOngoingCall — WhatsApp tarzi yesil banner
        val person = androidx.core.app.Person.Builder()
            .setName(peerName)
            .setImportant(true)
            .build()

        val callStyle = NotificationCompat.CallStyle.forOngoingCall(person, hangupPi)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setStyle(callStyle)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setContentText(callType)

        // Sure sayaci — startTime varsa Chronometer goster (canli MM:SS)
        if (startTime != null) {
            builder.setUsesChronometer(true)
            builder.setWhen(startTime)
        }

        // Bildirime tap → arama ekranina don
        if (tapPi != null) {
            builder.setContentIntent(tapPi)
        }

        return builder.build()
    }

    /**
     * Proximity sensor wake lock alir.
     * Kullanici telefonu kulagina yaklaştirdiginda ekran kapanir.
     * Arama bitene kadar aktif kalir (suresiz).
     */
    private fun acquireProximityWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
            "SecureChat:CallProximity"
        ).apply {
            acquire() // Suresiz - service sonlandiginda serbest birakilir
        }
    }

    /**
     * Proximity sensor wake lock'u serbest birakir.
     */
    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
