package com.securechat.app.data

import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.securechat.app.BuildConfig
import com.securechat.network.NetworkMonitor
import com.securechat.network.OfflineMessageQueue
import com.securechat.network.SignalingClient
import com.securechat.network.StuckMessageRecovery
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Uygulama on plan/arka plan gecislerini izleyen lifecycle observer.
 *
 * ProcessLifecycleOwner ile kayit edilir:
 * - onStart (app on plana gecti): WebSocket baglantisinı kur, presence online gonder,
 *   NetworkMonitor baslatilir (Bug 016, 024)
 * - onStop (app arka plana gecti): WebSocket baglantisinı kapat, presence offline gonder,
 *   NetworkMonitor durdurulur
 *
 * Bu sayede WebSocket sadece app gorunurken aktif olur.
 * Arka planda mesajlar FCM push ile alinir ve WebSocketDrainWorker kuyrugu bosaltir.
 *
 * NetworkMonitor entegrasyonu: Ag degisikliklerini (ucak modu, WiFi/Mobile gecisi)
 * aninda algilar ve SignalingClient'i yeniden baglar (Bug 016, Bug 024).
 */
@Singleton
class AppLifecycleObserver @Inject constructor(
    private val signalingClient: SignalingClient,
    private val userSession: UserSession,
    private val fcmTokenManager: FcmTokenManager,
    private val networkMonitor: NetworkMonitor,
    private val offlineMessageQueue: OfflineMessageQueue,
    private val stuckMessageRecovery: StuckMessageRecovery,
    private val pendingTimerFlusher: PendingTimerFlusher
) : DefaultLifecycleObserver {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onStart(owner: LifecycleOwner) {
        super.onStart(owner)
        Log.d("AppLifecycle", "App on plana gecti")
        IncomingMessageHandler.isAppInForeground = true

        if (userSession.isLoggedIn) {
            val userId = userSession.userId!!

            // Offline mesaj kuyrugunu SignalingClient'a bagla (Bug 001)
            signalingClient.offlineMessageQueue = offlineMessageQueue

            // Bug 003: Yeniden baglanti kuruldugunda SENDING durumunda takili mesajlari kurtar
            // + Sureli mesaj timer guncellemelerini de flush et (Asama 2)
            signalingClient.onReconnectedCallback = {
                scope.launch {
                    stuckMessageRecovery.recoverStuckMessages()
                    runCatching { pendingTimerFlusher.flush() }
                }
            }

            // GUVENLIK (Faz 1): Gercek JWT access token kullanilir. Eski "token_$userId"
            // sahte string server tarafinda AuthService.verifyToken'da reject ediliyordu
            // (jti+sub claim sart). Bu yuzden eski APK kullanicilarinin WS_AUTH_INVALID
            // ile reddedildigini audit_log'da gorduk (154 reject / 24 saat).
            // Token yoksa WS hic acilmaz — server kabul etmezdi zaten, kullanici yeniden
            // login olmali (PhoneVerificationScreen).
            val accessToken = userSession.accessToken
            if (accessToken.isNullOrBlank()) {
                Log.w("AppLifecycle", "accessToken null/blank — WS acilamaz, kullanici tekrar giris yapmali")
            } else {
                signalingClient.connect(
                    userId = userId,
                    authToken = accessToken,
                    customUrl = BuildConfig.SIGNALING_URL
                )
            }

            // Bug 016, 024: Ag izlemeyi baslat — ucak modu ve WiFi/Mobile gecislerini yakala
            networkMonitor.onNetworkAvailable = onNetworkAvailable@{
                Log.d("AppLifecycle", "Network available — reconnecting SignalingClient")
                if (userSession.isLoggedIn) {
                    val uid = userSession.userId ?: return@onNetworkAvailable
                    val token = userSession.accessToken ?: run {
                        Log.w("AppLifecycle", "accessToken null on network available — skip")
                        return@onNetworkAvailable
                    }
                    signalingClient.connect(
                        userId = uid,
                        authToken = token,
                        customUrl = BuildConfig.SIGNALING_URL
                    )
                }
            }
            networkMonitor.onNetworkLost = {
                Log.d("AppLifecycle", "Network lost — SignalingClient will detect via WebSocket failure")
            }
            networkMonitor.start()

            // FCM token'i her app acilisinda guncelle (guvenlik agi)
            scope.launch {
                fcmTokenManager.registerTokenOnServer()
            }
        }
    }

    override fun onStop(owner: LifecycleOwner) {
        super.onStop(owner)
        Log.d("AppLifecycle", "App arka plana gecti")
        IncomingMessageHandler.isAppInForeground = false

        // Bug 016, 024: Ag izlemeyi durdur — arka planda gereksiz callback almamak icin
        networkMonitor.stop()

        if (userSession.isLoggedIn) {
            // Offline presence gonder ve WebSocket'i kapat
            userSession.userId?.let { userId ->
                signalingClient.sendPresenceUpdate(userId, false, hideLastSeen = !userSession.shareLastSeen)
            }
            signalingClient.disconnect()
        }
    }
}
