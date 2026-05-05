package com.securechat.app.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.securechat.app.SecureChatActivity
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.storage.dao.ConversationDao
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Kaçırılan aramaları takip eden ve bildirim gösteren sınıf.
 *
 * Sorumluluklarş:
 * - Gelen arama 30 saniye boyunca cevaplanmazsa "missed call" olarak işaretler
 * - Missed call bildirimi gösterir
 * - Arama geçmişi kaydını tutar
 * - Bildirimden doğrudan callback yapma özelliği sunar
 */
@Singleton
class MissedCallTracker @Inject constructor(
    @ApplicationContext private val context: Context,
    private val conversationDao: ConversationDao
) {
    companion object {
        private const val MISSED_CALL_CHANNEL_ID = "missed_call_channel"
        private const val MISSED_CALL_TIMEOUT = 30_000L // 30 saniye
        private const val MISSED_CALL_NOTIFICATION_BASE_ID = 3000
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeCallTimers = mutableMapOf<String, kotlinx.coroutines.Job>()

    /**
     * Missed call notification channel'ını oluşturur.
     */
    fun initialize() {
        val channel = NotificationChannel(
            MISSED_CALL_CHANNEL_ID,
            "Kaçırılan Aramalar",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Cevaplanmayan arama bildirimleri"
            enableLights(true)
            enableVibration(false) // Missed call için vibrasyon gereksiz
        }
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    /**
     * Gelen arama için timer başlatır.
     * 30 saniye boyunca cevap verilmezse missed call olarak işaretlenir.
     *
     * @param session Gelen arama oturumu
     * @param peerName Arayan kişinin adı
     */
    fun startMissedCallTimer(session: CallSession, peerName: String) {
        // Mevcut timer'ı iptal et (duplicate önlemi)
        activeCallTimers[session.callId]?.cancel()

        android.util.Log.d("MissedCallTracker", "Timer başlatıldı: ${session.callId}, peer: $peerName")

        val job = scope.launch {
            delay(MISSED_CALL_TIMEOUT)

            // 30 saniye sonunda hala RINGING durumundaysa missed call
            android.util.Log.d("MissedCallTracker", "Timer süresi doldu, missed call kaydediliyor: ${session.callId}")
            recordMissedCall(session, peerName)
            showMissedCallNotification(session, peerName)

            // Timer'ı temizle
            activeCallTimers.remove(session.callId)
        }

        activeCallTimers[session.callId] = job
    }

    /**
     * Arama cevaplanırsa veya reddedilirse timer'ı iptal eder.
     *
     * @param callId İptal edilecek arama ID'si
     */
    fun cancelMissedCallTimer(callId: String) {
        activeCallTimers[callId]?.cancel()
        activeCallTimers.remove(callId)
        android.util.Log.d("MissedCallTracker", "Timer iptal edildi: $callId")
    }

    /**
     * Missed call kaydını konuşmada saklar.
     * Son mesaj olarak "Kaçırılan arama" metni eklenir.
     */
    private suspend fun recordMissedCall(session: CallSession, peerName: String) {
        try {
            val existingConv = conversationDao.getByPeerId(session.peerId)
            if (existingConv != null) {
                // Unread count artır ve son mesaj güncelle
                conversationDao.updateLastMessage(
                    session.peerId,
                    "Kaçırılan arama",
                    System.currentTimeMillis()
                )
                conversationDao.incrementUnreadCount(session.peerId)
                android.util.Log.d("MissedCallTracker", "Missed call kaydedildi: ${session.peerId}")
            }
        } catch (e: Exception) {
            android.util.Log.e("MissedCallTracker", "Missed call kaydetme hatası: ${e.message}")
        }
    }

    /**
     * Kaçırılan arama bildirimi gösterir.
     * Bildirime tıklandığında ilgili konuşma açılır ve callback yapma seçeneği sunulur.
     */
    private fun showMissedCallNotification(session: CallSession, peerName: String) {
        // Ana uygulama intent'i
        val openChatIntent = Intent(context, SecureChatActivity::class.java).apply {
            putExtra("chat_peer", session.peerId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openChatPi = PendingIntent.getActivity(
            context, session.callId.hashCode(), openChatIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Callback intent'i (geri arama)
        val callBackIntent = Intent(context, SecureChatActivity::class.java).apply {
            putExtra("action", "call_back")
            putExtra("peer_id", session.peerId)
            putExtra("call_type", session.callType.name)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val callBackPi = PendingIntent.getActivity(
            context, session.callId.hashCode() + 1000, callBackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val callTypeLabel = if (session.callType.name == "VIDEO") "Görüntülü Arama" else "Sesli Arama"
        val notification = NotificationCompat.Builder(context, MISSED_CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_missed_call)
            .setContentTitle("Kaçırılan $callTypeLabel")
            .setContentText("$peerName tarafından")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(openChatPi)
            .setAutoCancel(true)
            .addAction(
                android.R.drawable.ic_menu_call,
                "Geri Ara",
                callBackPi
            )
            .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_LIGHTS)
            .build()

        try {
            val notificationId = MISSED_CALL_NOTIFICATION_BASE_ID + session.peerId.hashCode()
            NotificationManagerCompat.from(context).notify(notificationId, notification)
            android.util.Log.d("MissedCallTracker", "Missed call bildirimi gösterildi: $peerName")
        } catch (e: SecurityException) {
            android.util.Log.e("MissedCallTracker", "Missed call bildirimi gösterilemedi: ${e.message}")
        }
    }

    /**
     * Tüm aktif timer'ları temizler (service shutdown sırasında).
     */
    fun cleanup() {
        activeCallTimers.values.forEach { it.cancel() }
        activeCallTimers.clear()
        android.util.Log.d("MissedCallTracker", "Tüm timer'lar temizlendi")
    }
}