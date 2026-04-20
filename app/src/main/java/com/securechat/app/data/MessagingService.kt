package com.securechat.app.data

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.securechat.app.SecureChatActivity
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Arka planda WebSocket baglantisini canli tutan foreground service.
 * Uygulama kapansa bile mesaj alabilmek icin gerekli.
 *
 * SMART FEATURES:
 * - Uygulama foreground'dayken bildirim gizlenir (minimized mode)
 * - Mesaj aldığında dinamik olarak güncellenir
 * - Kullanıcı dostu metinler ve akıllı durum yönetimi
 */
@AndroidEntryPoint
class MessagingService : Service() {

    @Inject lateinit var incomingMessageHandler: IncomingMessageHandler
    @Inject lateinit var incomingCallHandler: com.securechat.media.IncomingCallHandler
    @Inject lateinit var missedCallTracker: MissedCallTracker
    @Inject lateinit var messageRepository: com.securechat.storage.repository.MessageRepository
    @Inject lateinit var signalingClient: SignalingClient
    @Inject lateinit var userSession: com.securechat.app.data.UserSession

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var isMinimized = false
    private var lastMessageCount = 0
    private var lastMessageTime = 0L
    private var lastNotificationUpdate = 0L
    private var wakeLock: PowerManager.WakeLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    companion object {
        private const val CHANNEL_ID = "elci_bg_v2"
        private const val NOTIFICATION_ID = 2001

        // Service instance reference for updates
        private var serviceInstance: MessagingService? = null

        fun start(context: Context) {
            val intent = Intent(context, MessagingService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MessagingService::class.java))
        }

        /**
         * Mesaj geldiğinde bildirimi günceller
         */
        fun updateForNewMessage(messageCount: Int = 1) {
            serviceInstance?.handleNewMessage(messageCount)
        }

        /**
         * Uygulama foreground durumuna göre bildirimi günceller
         */
        fun updateAppState(isAppInForeground: Boolean) {
            serviceInstance?.updateNotificationVisibility(isAppInForeground)
        }
    }

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification(false))

        // Critical infrastructure'ları initialize et
        incomingCallHandler.initialize()
        missedCallTracker.initialize()

        // IncomingMessageHandler zaten SecureChatApplication.onCreate()'de baslatiliyor.
        // Burada tekrar cagirmak duplicate mesajlara neden olur.

        // Uygulama durumunu izle ve bildirimi buna göre ayarla
        startAppStateMonitoring()

        // Kritik: Service'in sistem tarafından kill edilmesini önle
        setupServiceProtection()

        // Sureli mesajlari periyodik olarak temizle
        startDisappearingMessageCleaner()

        // WebSocket baglantisini izle, koparsa yeniden baglan
        startConnectionWatchdog()

        // WakeLock — Doze modda CPU'yu uyandirarak WebSocket'i canli tut
        acquireWakeLock()

        // Network degisikligi dinle (WiFi <-> Mobil) — aninda reconnect
        registerNetworkCallback()
    }

    override fun onDestroy() {
        android.util.Log.d("MessagingService", "Service destroy edildi")
        serviceInstance = null
        missedCallTracker.cleanup()
        releaseWakeLock()
        unregisterNetworkCallback()
        scope.cancel()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Stop action gelirse service'i durdur
        if (intent?.action == "STOP_SERVICE") {
            android.util.Log.d("MessagingService", "Stop action alındı, service durduruluyor")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        // Eski kanal varsa sil — IMPORTANCE degisikliginin uygulanmasi icin
        // Eski kanallari temizle
        nm.deleteNotificationChannel("messaging_service")
        nm.deleteNotificationChannel("elci_bg")
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Arka Plan Hizmeti",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Arka planda güvenli mesaj alımını sağlar"
            setShowBadge(false)
            setSound(null, null) // Sessiz kanal
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(channel)
    }

    private fun createNotification(@Suppress("UNUSED_PARAMETER") isMinimized: Boolean): Notification {
        val openAppIntent = Intent(this, SecureChatActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openAppPendingIntent)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentTitle("Arka plan hizmeti")
            .setContentText(null)
            .setSubText(null)
            .setShowWhen(false)
            .build()
    }

    /**
     * Yeni mesaj geldiğinde bildirimi günceller
     */
    private fun handleNewMessage(messageCount: Int) {
        lastMessageCount += messageCount
        lastMessageTime = System.currentTimeMillis()

        if (!isMinimized) {
            updateNotification()
        }

        // 30 saniye sonra normal duruma dönsün
        scope.launch {
            delay(30_000)
            if (System.currentTimeMillis() - lastMessageTime >= 30_000) {
                lastMessageCount = 0
                if (!isMinimized) {
                    updateNotification()
                }
            }
        }
    }

    /**
     * Bildirim her zaman foreground olarak kalir — kapatılamaz.
     * stopForeground cagirilmaz, cunku tekrar startForeground yapinca
     * ongoing ozelligi kaybolabiliyor.
     */
    private fun updateNotificationVisibility(isAppInForeground: Boolean) {
        isMinimized = isAppInForeground
    }

    private fun updateNotification() {
        if (isMinimized) return // Uygulama on plandaysa bildirim yok
        val now = System.currentTimeMillis()
        if (now - lastNotificationUpdate < 3000) return
        lastNotificationUpdate = now

        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, createNotification(false))
    }

    /**
     * Uygulama durumunu periyodik olarak kontrol eder
     */
    private fun startAppStateMonitoring() {
        scope.launch {
            while (true) {
                delay(2000) // 2 saniyede bir kontrol et

                val isAppForeground = IncomingMessageHandler.isAppInForeground
                updateNotificationVisibility(isAppForeground)
            }
        }
    }

    /**
     * Service'in sistem tarafından kill edilmesini önlemek için
     * koruma mekanizmaları kurar.
     */
    /**
     * Bildirim kapatilirsa otomatik olarak geri getirir.
     * Samsung OneUI setOngoing(true) kuralini yok sayar,
     * bu watchdog foreground state'i korur.
     */
    private fun setupServiceProtection() {
        scope.launch {
            while (true) {
                delay(10_000)
                // Bildirim hala var mi kontrol et
                val nm = getSystemService(NotificationManager::class.java)
                val active = nm.activeNotifications.any { it.id == NOTIFICATION_ID }
                if (!active) {
                    android.util.Log.d("MessagingService", "Bildirim kapatilmis, yeniden olusturuluyor")
                    startForeground(NOTIFICATION_ID, createNotification(false))
                }
            }
        }
    }

    /**
     * WebSocket baglantisini izler.
     * SignalingClient kendi reconnect'ini yapar — watchdog sadece uzun sureli
     * kopukluklarda (60s+) fallback olarak devreye girer.
     * Bu sayede SignalingClient + watchdog cift baglanti denemesi onlenir.
     */
    private fun startConnectionWatchdog() {
        scope.launch(Dispatchers.IO) {
            while (true) {
                delay(60_000) // 60 saniyede bir kontrol
                val state = signalingClient.connectionState.value
                if ((state is ConnectionState.Disconnected || state is ConnectionState.Error)
                    && userSession.isLoggedIn
                ) {
                    android.util.Log.d("MessagingService", "Watchdog: baglanti hala kopuk, retryConnection")
                    signalingClient.retryConnection()
                }
            }
        }
    }

    /**
     * Partial WakeLock — CPU'yu uyanik tutar, ekrani acmaz.
     * Doze modda bile WebSocket ping/pong calisir.
     */
    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Elcim::MessagingWakeLock"
        ).apply {
            acquire()
        }
        android.util.Log.d("MessagingService", "WakeLock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        android.util.Log.d("MessagingService", "WakeLock released")
    }

    /**
     * Network degisikliklerini dinler.
     * WiFi <-> Mobil geciste aninda reconnect yapar.
     */
    private fun registerNetworkCallback() {
        val cm = getSystemService(ConnectivityManager::class.java)
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                android.util.Log.d("MessagingService", "Network available, checking connection...")
                scope.launch(Dispatchers.IO) {
                    delay(2000) // Network stabilize olsun
                    if (signalingClient.connectionState.value !is ConnectionState.Connected
                        && userSession.isLoggedIn
                    ) {
                        android.util.Log.d("MessagingService", "Reconnecting after network change...")
                        signalingClient.retryConnection()
                    }
                }
            }

            override fun onLost(network: Network) {
                android.util.Log.d("MessagingService", "Network lost")
            }
        }

        cm.registerNetworkCallback(request, networkCallback!!)
        android.util.Log.d("MessagingService", "NetworkCallback registered")
    }

    private fun unregisterNetworkCallback() {
        networkCallback?.let {
            val cm = getSystemService(ConnectivityManager::class.java)
            try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
        }
        networkCallback = null
    }

    /**
     * Sureli mesajlari periyodik olarak temizler.
     * Her 5 saniyede bir suresi dolmus mesajlari siler.
     */
    private fun startDisappearingMessageCleaner() {
        scope.launch(Dispatchers.IO) {
            while (true) {
                delay(5_000)
                try {
                    val deleted = messageRepository.deleteExpiredMessages()
                    if (deleted > 0) {
                        android.util.Log.d("MessagingService", "Sureli mesaj temizlendi: $deleted mesaj silindi")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MessagingService", "Sureli mesaj temizleme hatasi", e)
                }
            }
        }
    }
}
