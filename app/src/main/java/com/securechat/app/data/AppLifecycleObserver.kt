package com.securechat.app.data

import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.securechat.app.BuildConfig
import com.securechat.network.SignalingClient
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
 * - onStart (app on plana gecti): WebSocket baglantisinı kur, presence online gonder
 * - onStop (app arka plana gecti): WebSocket baglantisinı kapat, presence offline gonder
 *
 * Bu sayede WebSocket sadece app gorunurken aktif olur.
 * Arka planda mesajlar FCM push ile alinir ve WebSocketDrainWorker kuyrugu bosaltir.
 */
@Singleton
class AppLifecycleObserver @Inject constructor(
    private val signalingClient: SignalingClient,
    private val userSession: UserSession,
    private val fcmTokenManager: FcmTokenManager
) : DefaultLifecycleObserver {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onStart(owner: LifecycleOwner) {
        super.onStart(owner)
        Log.d("AppLifecycle", "App on plana gecti")
        IncomingMessageHandler.isAppInForeground = true

        if (userSession.isLoggedIn) {
            val userId = userSession.userId!!
            signalingClient.connect(
                userId = userId,
                authToken = "token_$userId",
                customUrl = BuildConfig.SIGNALING_URL
            )
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

        if (userSession.isLoggedIn) {
            // Offline presence gonder ve WebSocket'i kapat
            userSession.userId?.let { userId ->
                signalingClient.sendPresenceUpdate(userId, false)
            }
            signalingClient.disconnect()
        }
    }
}
