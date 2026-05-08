package com.securechat.media

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.securechat.media.model.CallSession
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Gelen arama bildirimlerini yoneten sinif.
 *
 * Sorumluluklari:
 * - Gelen arama icin notification channel olusturma
 * - Full-screen intent ile gelen arama bildirimi gosterme (kilit ekrani uzerinde)
 * - Kabul/Reddet aksiyonlari sunma
 * - Bildirim temizleme
 */
@Singleton
class IncomingCallHandler @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        const val INCOMING_CALL_NOTIFICATION_ID = 1200  // Daha guvenli aralik
        const val INCOMING_CALL_CHANNEL_ID = "incoming_call_channel"
        const val ACTION_ACCEPT = "com.securechat.media.ACTION_ACCEPT"
        const val ACTION_REJECT = "com.securechat.media.ACTION_REJECT"
        const val EXTRA_CALL_ID = "call_id"
    }

    /**
     * Gelen arama notification channel'ini olusturur.
     * Uygulama baslatildiginda bir kere cagrilmalidir.
     */
    fun initialize() {
        val channel = NotificationChannel(
            INCOMING_CALL_CHANNEL_ID,
            "Gelen Arama",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null)
            // Kritik: Bu kanal full-screen intent'leri destekler
            enableLights(true)
            enableVibration(true)
            description = "Gelen arama bildirimleri - kilit ekranında görünür"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    /**
     * Gelen arama bildirimi gosterir.
     * Full-screen intent ile kilit ekrani uzerinde IncomingCallActivity'yi acar.
     *
     * @param session Gelen arama oturumu bilgileri
     * @param peerName Arayan kisinin gorunen adi
     * @param fullScreenActivityClass IncomingCallActivity sinif referansi (app modulunden saglanir)
     */
    fun showIncomingCall(session: CallSession, peerName: String, fullScreenActivityClass: Class<*>?) {
        // ACCEPT: Android 10+ "background activity launch" kisitlamasi yuzunden
        // BroadcastReceiver'dan startActivity sessizce basarisiz olabiliyor
        // ("yukaridan kabul et" basinca arama ekrani acilmiyor sorunu).
        // Cozum: dogrudan SecureChatActivity'i PendingIntent.getActivity ile cagir;
        // activity onCreate/onNewIntent'te accept_call extra'sini gorup acceptCall +
        // navigate yapar. Notification action'i kullanici etkilesimi sayildigindan
        // PendingIntent.getActivity her zaman calisir.
        val acceptPi: PendingIntent = if (fullScreenActivityClass != null) {
            // SecureChatActivity'i bul: fullScreenActivity IncomingCallActivity, parent
            // package'da "SecureChatActivity" var. Burada string ile referans veriyoruz
            // ki :media modulu :app'e bagli olmasin.
            val activityClass = Class.forName("com.securechat.app.SecureChatActivity")
            val acceptActivityIntent = Intent(context, activityClass).apply {
                action = "ACCEPT_INCOMING_CALL"
                putExtra(EXTRA_CALL_ID, session.callId)
                putExtra("accept_call", true)
                putExtra("call_peer_id", session.peerId)
                putExtra("call_type", session.callType.name)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            PendingIntent.getActivity(
                context, 100, acceptActivityIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            // Fallback (test vs.) — BroadcastReceiver yolu
            val acceptIntent = Intent(ACTION_ACCEPT).apply {
                setPackage(context.packageName)
                putExtra(EXTRA_CALL_ID, session.callId)
            }
            PendingIntent.getBroadcast(
                context, 0, acceptIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val rejectIntent = Intent(ACTION_REJECT).apply {
            setPackage(context.packageName)
            putExtra(EXTRA_CALL_ID, session.callId)
        }
        val rejectPi = PendingIntent.getBroadcast(
            context, 1, rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, INCOMING_CALL_CHANNEL_ID)
            .setContentTitle("Gelen Arama")
            .setContentText("$peerName ariyor...")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .addAction(android.R.drawable.ic_menu_call, "Kabul Et", acceptPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Reddet", rejectPi)
            .setOngoing(true)
            .setAutoCancel(false)
            // Kritik: Bu bildirim heads-up olarak gösterilmeli
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setVibrate(longArrayOf(0, 1000, 500, 1000))
            .setSound(null) // Zil sesi RingtonePlayer'dan çalacak
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setTimeoutAfter(30_000) // 30 saniye sonra otomatik kaybolsun

        // Full-screen intent ekle — kilit ekraninda dogrudan Activity acar
        if (fullScreenActivityClass != null) {
            val fullScreenIntent = Intent(context, fullScreenActivityClass).apply {
                putExtra("peer_id", session.peerId)
                putExtra("peer_name", peerName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
            }
            val fullScreenPi = PendingIntent.getActivity(
                context, 2, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setFullScreenIntent(fullScreenPi, true)
        }

        try {
            NotificationManagerCompat.from(context).notify(INCOMING_CALL_NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS izni yoksa sessizce devam et
        }
    }

    /**
     * Gelen arama bildirimini kaldirir.
     * Arama kabul edildiginde, reddedildiginde veya sonlandirildiginda cagirilir.
     */
    fun dismissIncomingCall() {
        NotificationManagerCompat.from(context).cancel(INCOMING_CALL_NOTIFICATION_ID)
    }
}
