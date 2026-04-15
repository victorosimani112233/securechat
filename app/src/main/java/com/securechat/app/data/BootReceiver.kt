package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Cihaz açılışında veya uygulamanın güncellenmesinde otomatik olarak
 * background service'leri başlatan receiver.
 *
 * Bu receiver, kullanıcı uygulamayı manuel olarak açmadan da
 * gelen arama sinyallerini yakalayabilmesini sağlar.
 */
@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {

    @Inject lateinit var userSession: UserSession

    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("BootReceiver", "Boot broadcast alındı: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                // Kullanıcı giriş yapmışsa service'i başlat
                if (userSession.isLoggedIn) {
                    android.util.Log.d("BootReceiver", "Kullanıcı giriş yapmış, MessagingService başlatılıyor")
                    MessagingService.start(context)
                } else {
                    android.util.Log.d("BootReceiver", "Kullanıcı giriş yapmamış, service başlatılmadı")
                }
            }
        }
    }
}