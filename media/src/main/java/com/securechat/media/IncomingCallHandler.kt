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
     * Idempotent — birden fazla cagri guvenli, kanali silmez.
     *
     * NOT: deleteNotificationChannel ASLA cagrilmaz cunku FCM push akisinda
     * SecureChatFcmService her gelen aramada initialize() cagriyor; kanal silinince
     * o anda yapilmis olan full-screen intent'li bildirim de iptal oluyordu.
     */
    fun initialize() {
        val nm = context.getSystemService(NotificationManager::class.java)
        // Kanal zaten varsa yeniden olusturma — Android idempotent gibi davransa da
        // yeni instance ses/titresim gibi ayarlari guncellemez, sadece create_or_no_op
        if (nm.getNotificationChannel(INCOMING_CALL_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            INCOMING_CALL_CHANNEL_ID,
            "Gelen Arama",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            // Ses ve titresim RingtonePlayer tarafindan yonetilir — kanal sessiz olmali
            setSound(null, null)
            enableLights(true)
            enableVibration(false)
            description = "Gelen arama bildirimleri - kilit ekranında görünür"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    /**
     * Gelen arama bildirimi gosterir.
     *
     * NotificationCompat.CallStyle kullanir (Android 12+ icin native, daha eski versiyonlar
     * icin compat fallback). WhatsApp benzeri arama UI'i:
     * - Buyuk arayan ismi/avatar
     * - Yesil "Kabul Et" / kirmizi "Reddet" butonlari
     * - Android otomatik full-screen tetikler (kilit ekraninda + non-interactive durumda)
     * - SYSTEM_ALERT_WINDOW iznine ihtiyac duymaz
     *
     * @param session Gelen arama oturumu bilgileri
     * @param peerName Arayan kisinin gorunen adi
     * @param fullScreenActivityClass IncomingCallActivity sinif referansi (app modulunden saglanir)
     */
    fun showIncomingCall(session: CallSession, peerName: String, fullScreenActivityClass: Class<*>?) {
        val acceptIntent = Intent(ACTION_ACCEPT).apply {
            setPackage(context.packageName)
            putExtra(EXTRA_CALL_ID, session.callId)
        }
        val acceptPi = PendingIntent.getBroadcast(
            context, 0, acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rejectIntent = Intent(ACTION_REJECT).apply {
            setPackage(context.packageName)
            putExtra(EXTRA_CALL_ID, session.callId)
        }
        val rejectPi = PendingIntent.getBroadcast(
            context, 1, rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isVideo = session.callType == CallType.VIDEO

        // Arayan kisiyi Person olarak tanimla — CallStyle bu sayede WhatsApp-tarzi avatar/isim gosterir
        val caller = Person.Builder()
            .setName(peerName)
            .setImportant(true)
            .build()

        // CallStyle.forIncomingCall: sistem otomatik yesil-kabul/kirmizi-reddet butonlari ekler
        val callStyle = NotificationCompat.CallStyle.forIncomingCall(
            caller,
            rejectPi,   // declineIntent (kirmizi buton)
            acceptPi    // answerIntent (yesil buton)
        ).setIsVideo(isVideo)

        val builder = NotificationCompat.Builder(context, INCOMING_CALL_CHANNEL_ID)
            .setStyle(callStyle)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setTimeoutAfter(30_000) // 30sn sonra otomatik kaybolsun

        // Full-screen intent ekle — Android otomatik launch eder (kilit ekrani + non-interactive)
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
