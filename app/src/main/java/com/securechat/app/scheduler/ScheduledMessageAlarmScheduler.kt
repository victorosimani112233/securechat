package com.securechat.app.scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.securechat.storage.entity.ScheduledMessageEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Planli mesajlar icin tam zamanli alarm yoneticisi.
 *
 * Kullanir: `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP, ...)`
 * - Doze mode'da bile cihaz uyandirilir (cihaz cep'te kapalı dahi tetiklenir)
 * - Hassasiyet: ±~9dk Android sistem optimizasyonu nedeniyle (kullanici tarafindan kabul edildi)
 * - `SCHEDULE_EXACT_ALARM` izni GEREKMEZ — `setExact*` yerine `setAndAllowWhileIdle` kullaniyoruz
 * - Reboot sonrasi alarm'lar kaybolur → `BootReceiver` ile yeniden schedule edilir
 *
 * Tek bir plan icin tek alarm; plan id hash'i requestCode olur (idempotent override).
 */
@Singleton
class ScheduledMessageAlarmScheduler @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        const val ACTION_TRIGGER = "com.securechat.app.SCHEDULED_MESSAGE_TRIGGER"
        const val EXTRA_PLAN_ID = "plan_id"
        private const val TAG = "ScheduledAlarm"
    }

    private val alarmManager: AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Bir plan icin alarm kurar (mevcut alarm override edilir — idempotent).
     *
     * @param entity Plan kayit. `nextTriggerTime` epoch ms — bu zamanda receiver tetiklenir.
     */
    fun schedule(entity: ScheduledMessageEntity) {
        if (!entity.isEnabled) {
            cancel(entity.id)
            return
        }
        val triggerTime = entity.nextTriggerTime
        if (triggerTime <= System.currentTimeMillis()) {
            android.util.Log.w(TAG, "Plan ${entity.id} trigger zamani gecmis: $triggerTime")
            // Yine de schedule et — alarm yarin gibi gelecek bir tarihe set edilemez, hemen tetiklenir
        }

        val pi = pendingIntent(entity.id)
        try {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pi
            )
            android.util.Log.d(TAG, "Plan ${entity.id} alarm kuruldu: trigger=$triggerTime")
        } catch (e: SecurityException) {
            // Bazi OEM'lerde alarm izin kisitlamasi (Xiaomi, Huawei) — fallback log
            android.util.Log.e(TAG, "Plan ${entity.id} alarm kurulamadi: ${e.message}")
        }
    }

    /** Plan'in alarm'ini iptal eder (delete veya toggle-off durumunda). */
    fun cancel(planId: String) {
        val pi = pendingIntent(planId)
        alarmManager.cancel(pi)
        pi.cancel()
        android.util.Log.d(TAG, "Plan $planId alarm iptal edildi")
    }

    /**
     * Bir plan icin benzersiz PendingIntent uretir.
     * requestCode = plan.id.hashCode() — ayni id icin daima ayni intent, override calisir.
     */
    private fun pendingIntent(planId: String): PendingIntent {
        val intent = Intent(context, ScheduledMessageReceiver::class.java).apply {
            action = ACTION_TRIGGER
            putExtra(EXTRA_PLAN_ID, planId)
            // Explicit receiver — implicit broadcast Android 8+ kisitlamasini bypass eder
            setPackage(context.packageName)
        }
        return PendingIntent.getBroadcast(
            context,
            planId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
