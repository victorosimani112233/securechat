package com.securechat.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentCallbacks2
import android.util.Log
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.Configuration
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.CachePolicy
import com.securechat.app.data.AppLifecycleObserver
import com.securechat.app.data.DisappearingMessageWorker
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.BuildConfig
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import androidx.hilt.work.HiltWorkerFactory

@HiltAndroidApp
class SecureChatApplication : Application(), Configuration.Provider, ImageLoaderFactory {

    @Inject lateinit var incomingMessageHandler: dagger.Lazy<IncomingMessageHandler>
    @Inject lateinit var userSession: UserSession
    @Inject lateinit var appLifecycleObserver: dagger.Lazy<AppLifecycleObserver>
    @Inject lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    /**
     * Coil gorsel yukleme kutuphanesi icin sinirli disk ve bellek onbellegi.
     * Disk: 200 MB, Bellek: 128 MB ile sinirlandirilir.
     */
    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.25) // Uygulama bellegi %25'i
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache"))
                    .maxSizeBytes(200L * 1024 * 1024) // 200 MB sinir
                    .build()
            }
            .memoryCachePolicy(CachePolicy.ENABLED)
            .diskCachePolicy(CachePolicy.ENABLED)
            .build()
    }

    override fun onCreate() {
        super.onCreate()

        // Uygulama guncelleme sonrasi uyumsuz onbellegi temizle
        clearCacheOnVersionUpdate()

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

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        Log.d("SecureChatApp", "onTrimMemory cagirildi, seviye: $level")

        if (level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE) {
            Log.w("SecureChatApp", "Bellek baskisi yuksek (seviye=$level), onbellekler temizleniyor")
            // Bildirim bitmap onbellegini temizle
            try {
                incomingMessageHandler.get().clearBitmapCache()
            } catch (e: Exception) {
                Log.e("SecureChatApp", "Bitmap onbellegi temizlenemedi", e)
            }
            // Bildirim mesaj sayaclarini temizle
            IncomingMessageHandler.clearNotificationCounts()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        Log.w("SecureChatApp", "onLowMemory cagirildi, tam temizlik yapiliyor")
        onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
    }

    /**
     * Uygulama versiyonu degistiginde eski onbellegi temizler.
     * Uyumsuz cache verisinin cokmelere yol acmasini engeller.
     */
    private fun clearCacheOnVersionUpdate() {
        val prefs = getSharedPreferences("app_version", MODE_PRIVATE)
        val lastVersion = prefs.getInt("last_version_code", 0)
        val currentVersion = BuildConfig.VERSION_CODE
        if (lastVersion != 0 && lastVersion < currentVersion) {
            // Uygulama guncellendi — uyumsuz cache temizle
            cacheDir.deleteRecursively()
            cacheDir.mkdirs()
            Log.d("SecureChatApp", "Cache temizlendi: v$lastVersion -> v$currentVersion")
        }
        prefs.edit().putInt("last_version_code", currentVersion).apply()
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
