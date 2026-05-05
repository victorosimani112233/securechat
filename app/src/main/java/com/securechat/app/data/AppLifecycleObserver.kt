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
    private val stuckMessageRecovery: StuckMessageRecovery
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
            signalingClient.onReconnectedCallback = {
                scope.launch {
                    stuckMessageRecovery.recoverStuckMessages()
                }
            }

            // GUVENLIK: JWT access token zorunlu — sunucu eski "token_<id>" sahte token'larini reddediyor
            val token = userSession.accessToken
            if (token.isNullOrBlank()) {
                Log.w("AppLifecycle", "Access token yok — sunucuya kayit gerekli, baglanti atlandi")
                return
            }
            signalingClient.connect(
                userId = userId,
                authToken = token,
                customUrl = BuildConfig.SIGNALING_URL
            )

            // Bug 016, 024: Ag izlemeyi baslat — ucak modu ve WiFi/Mobile gecislerini yakala
            networkMonitor.onNetworkAvailable = onNetworkAvailable@{
                Log.d("AppLifecycle", "Network available — reconnecting SignalingClient")
                if (userSession.isLoggedIn) {
                    val uid = userSession.userId ?: return@onNetworkAvailable
                    val tk = userSession.accessToken
                    if (tk.isNullOrBlank()) {
                        Log.w("AppLifecycle", "Access token yok, reconnect atlandi")
                        return@onNetworkAvailable
                    }
                    signalingClient.connect(
                        userId = uid,
                        authToken = tk,
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
