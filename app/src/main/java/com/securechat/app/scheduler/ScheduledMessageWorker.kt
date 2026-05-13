package com.securechat.app.scheduler

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.securechat.storage.dao.ScheduledMessageDao
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Planli mesaj tetikleyici — 15dk'da bir tum due plan'lari gonderir.
 *
 * Akis:
 *   1. `scheduledMessageDao.getDueMessages(now)` — `isEnabled=true` ve `nextTriggerTime <= now` olanlar
 *   2. Her plan icin tum recipient'lara `SendMessageUseCase` ile mesaj gonder
 *   3. Tekrarlama tipine gore:
 *      - ONCE → DB'den sil
 *      - DAILY → nextTriggerTime += 1 gun, update
 *      - CUSTOM → calculateNextTrigger ile yeniden hesapla, update
 *
 * Kullanim: Application.onCreate'te [enqueue] cagrilir, WorkManager 15dk minimum interval ile
 * tetikler. Reboot sonrasi WorkManager otomatik resume eder (KEEP policy).
 *
 * SINIRLAMA: WorkManager periodic min interval 15dk — plan icin secilen saat ile gercek
 * tetiklenme arasinda ±15dk gecikme olabilir. WhatsApp'in zamanlanmis mesaji da ayni pattern.
 */
@HiltWorker
class ScheduledMessageWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val scheduledMessageDao: ScheduledMessageDao,
    private val dispatcher: ScheduledMessageDispatcher
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        return try {
            val now = System.currentTimeMillis()
            val due = scheduledMessageDao.getDueMessages(now)
            android.util.Log.d(TAG, "Worker calisti — due plan sayisi: ${due.size}")

            // Dispatcher'a delege — Receiver ile ayni logic
            for (entity in due) {
                dispatcher.processPlan(entity.id)
            }
            Result.success()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Worker hatasi: ${e.message}", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "ScheduledMsgWorker"
        const val WORK_NAME = "scheduled_messages_periodic"

        /**
         * Application.onCreate'te cagirilir — periodic worker'i enqueue eder.
         * KEEP policy: zaten enqueue edildiyse yeniden eklemez (idempotent).
         */
        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<ScheduledMessageWorker>(
                15, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
            android.util.Log.d("ScheduledMsgWorker", "Periodic worker enqueued (15dk interval)")
        }
    }
}
