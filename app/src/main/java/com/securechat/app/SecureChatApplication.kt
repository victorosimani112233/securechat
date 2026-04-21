package com.securechat.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.Configuration
import com.securechat.app.data.AppLifecycleObserver
import com.securechat.app.data.DisappearingMessageWorker
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import androidx.hilt.work.HiltWorkerFactory

@HiltAndroidApp
class SecureChatApplication : Application(), Configuration.Provider {

    @Inject lateinit var incomingMessageHandler: dagger.Lazy<IncomingMessageHandler>
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var appLifecycleObserver: dagger.Lazy<AppLifecycleObserver>
    @Inject lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()

        // FCM notification kanali — hizli, UI thread'de olabilir
        createNotificationChannel()

        // Agir bagimliliklari arka planda baslat — cold start hizini arttirir
        val bgThread = Thread {
            // Gelen mesajlari dinle
            incomingMessageHandler.get().start()

            // App on plan/arka plan gecislerini izle
            // WebSocket baglantisi AppLifecycleObserver.onStart() icerisinde kurulur
            android.os.Handler(mainLooper).post {
                ProcessLifecycleOwner.get().lifecycle.addObserver(appLifecycleObserver.get())
            }

            // Sureli mesaj temizlik gorevini zamanla (15 dakikada bir)
            android.os.Handler(mainLooper).post {
                DisappearingMessageWorker.schedule(this@SecureChatApplication)
            }
        }
        bgThread.name = "securechat-init"
        bgThread.start()
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel("elcim_messages_v4") == null) {
            val channel = NotificationChannel(
                "elcim_messages_v4",
                "Mesajlar",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Gelen mesaj bildirimleri"
                enableVibration(true)
                enableLights(true)
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }
    }
}
