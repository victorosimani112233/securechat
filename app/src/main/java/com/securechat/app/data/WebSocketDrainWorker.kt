package com.securechat.app.data

import android.content.Context
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.securechat.app.BuildConfig
import com.securechat.app.R
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * FCM push geldiginde kisa sureli WebSocket baglantisi kuran worker.
 *
 * Islem akisi:
 * 1. WebSocket baglantisinı kur
 * 2. Connected durumunu bekle (maks 10s)
 * 3. Offline mesajlar otomatik olarak IncomingMessageHandler tarafindan islenir
 * 4. 5 saniye daha bekle (ek mesajlar icin drain window)
 * 5. WebSocket'i kapat
 *
 * App on plandaysa AppLifecycleObserver zaten WS acik tutar,
 * bu worker sadece arka planda FCM push geldiginde calisir.
 */
@HiltWorker
class WebSocketDrainWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val notification = NotificationCompat.Builder(applicationContext, "elcim_messages_v4")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Elçim")
            .setContentText("Mesajlar senkronize ediliyor…")
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        return ForegroundInfo(FOREGROUND_NOTIFICATION_ID, notification)
    }

    override suspend fun doWork(): Result {
        val userId = userSession.userId ?: return Result.failure()

        // App on plandaysa WS zaten acik — drain gereksiz
        if (IncomingMessageHandler.isAppInForeground) {
            Log.d("DrainWorker", "App on planda, drain atlandi")
            return Result.success()
        }

        // Zaten bagliysa sadece drain window bekle
        if (signalingClient.connectionState.value is ConnectionState.Connected) {
            Log.d("DrainWorker", "WS zaten bagli, drain window bekleniyor")
            delay(DRAIN_WINDOW_MS)
            return Result.success()
        }

        Log.d("DrainWorker", "WS drain basladi: $userId")

        try {
            // GUVENLIK: JWT access token zorunlu
            if (userSession.accessToken.isNullOrBlank()) {
                Log.w("DrainWorker", "Access token yok — drain atlandi")
                return Result.failure()
            }
            // WebSocket baglan — reactive provider ile (token expire olursa 1008 → refresh + retry)
            signalingClient.connect(
                userId = userId,
                customUrl = BuildConfig.SIGNALING_URL
            ) { userSession.accessToken }

            // Connected durumunu bekle (maks 10s)
            val connected = withTimeoutOrNull(CONNECTION_TIMEOUT_MS) {
                signalingClient.connectionState.first { it is ConnectionState.Connected }
            }

            if (connected == null) {
                Log.w("DrainWorker", "WS baglanti zaman asimi")
                return Result.retry()
            }

            // Offline mesajlar addConnection icerisinde otomatik iletilir.
            // IncomingMessageHandler bunlari isler ve bildirim gosterir.
            // Ek mesajlar icin drain window bekle.
            delay(DRAIN_WINDOW_MS)

            Log.d("DrainWorker", "WS drain tamamlandi")

        } catch (e: Exception) {
            Log.e("DrainWorker", "WS drain hatasi: ${e.message}")
            return Result.retry()
        } finally {
            // App hala arka plandaysa baglantiyi kapat
            if (!IncomingMessageHandler.isAppInForeground) {
                signalingClient.disconnect()
                Log.d("DrainWorker", "WS baglanti kapatildi (arka plan)")
            }
        }

        return Result.success()
    }

    companion object {
        private const val CONNECTION_TIMEOUT_MS = 10_000L
        private const val DRAIN_WINDOW_MS = 5_000L
        private const val WORK_NAME = "ws_drain"
        private const val FOREGROUND_NOTIFICATION_ID = 9901

        /**
         * Drain worker'i tetikler. Ayni anda tek instance calisir (KEEP).
         */
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<WebSocketDrainWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request)

            Log.d("DrainWorker", "Drain worker enqueue edildi")
        }
    }
}
