package com.securechat.app.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.securechat.app.scheduler.ScheduledMessageAlarmScheduler
import com.securechat.storage.dao.ScheduledMessageDao
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Cihaz acilisinda veya uygulama guncellendiginde:
 *   1. FCM token'ini sunucuya kaydeder
 *   2. Aktif planli mesajlarin alarm'larini yeniden schedule eder
 *      (AlarmManager reboot sonrasi alarm'lari kaybeder — bu olmazsa planlar tetiklenmez)
 */
@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {

    @Inject lateinit var userSession: UserSession
    @Inject lateinit var fcmTokenManager: FcmTokenManager
    @Inject lateinit var scheduledMessageDao: ScheduledMessageDao
    @Inject lateinit var alarmScheduler: ScheduledMessageAlarmScheduler

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

                // Planli mesajlari yeniden schedule et — reboot/app update sonrasi
                // AlarmManager alarm'lari kaybeder. Aktif planlari tarayip her birine
                // yeniden alarm kur.
                val pendingResult = goAsync()
                scope.launch {
                    try {
                        rescheduleActivePlans()
                    } catch (e: Exception) {
                        android.util.Log.e("BootReceiver", "Plan reschedule hatasi: ${e.message}")
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
        }
    }

    private suspend fun rescheduleActivePlans() {
        // DAO senkron erisim: getDueMessages(Long.MAX_VALUE) → tum aktif planlari getirir,
        // bunlardan isEnabled olanlar zaten filter yapar (DAO query'sinde).
        // Daha temiz: getAll() ile Flow yerine snapshot ister — DAO'da yoksa
        // getDueMessages(MAX_VALUE) ile workaround.
        val all = scheduledMessageDao.getDueMessages(Long.MAX_VALUE)
        var count = 0
        for (entity in all) {
            if (entity.isEnabled) {
                alarmScheduler.schedule(entity)
                count++
            }
        }
        android.util.Log.d("BootReceiver", "Reboot sonrasi $count planli mesaj alarm'i kuruldu")
    }
}
