package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Cihaz acilisinda veya uygulama guncellendiginde FCM token'ini
 * sunucuya kaydeden receiver.
 *
 * Foreground service kaldirildi — artik sadece FCM token guncelleme yapar.
 */
@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {

    @Inject lateinit var userSession: UserSession
    @Inject lateinit var fcmTokenManager: FcmTokenManager

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("BootReceiver", "Boot broadcast alindi: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                if (userSession.isLoggedIn) {
                    android.util.Log.d("BootReceiver", "FCM token sunucuya kaydediliyor")
                    scope.launch {
                        fcmTokenManager.registerTokenOnServer()
                    }
                }
            }
        }
    }
}
