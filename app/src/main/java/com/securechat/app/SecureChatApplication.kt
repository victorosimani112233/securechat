package com.securechat.app

import android.app.Application
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.network.SignalingClient
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class SecureChatApplication : Application() {

    @Inject lateinit var signalingClient: SignalingClient
    @Inject lateinit var incomingMessageHandler: IncomingMessageHandler
    @Inject lateinit var userSession: UserSession

    override fun onCreate() {
        super.onCreate()

        // Gelen mesajlari dinle
        incomingMessageHandler.start()

        // Daha once giris yapildiysa otomatik baglan ve servisi baslat
        if (userSession.isLoggedIn) {
            signalingClient.connect(
                userId = userSession.userId!!,
                authToken = "token_${userSession.userId}",
                customUrl = BuildConfig.SIGNALING_URL
            )
            // Arka planda mesaj almak icin foreground service
            com.securechat.app.data.MessagingService.start(this)
        }
    }
}
