package com.securechat.app.data

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.securechat.storage.repository.MessageRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Sureli mesajlari periyodik olarak temizleyen WorkManager worker'i.
 * MessagingService'ten tasinmistir — artik foreground service yerine
 * WorkManager ile calisir.
 *
 * WorkManager minimum 15 dakikada bir calisir.
 * App on plandayken daha sik temizlik AppLifecycleObserver
 * veya ChatViewModel tarafindan yapilabilir.
 */
@HiltWorker
class DisappearingMessageWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val messageRepository: MessageRepository
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            val deleted = messageRepository.deleteExpiredMessages()
            if (deleted > 0) {
                Log.d("DisappearingWorker", "Sureli mesaj temizlendi: $deleted mesaj silindi")
            }
            Result.success()
        } catch (e: Exception) {
            Log.e("DisappearingWorker", "Sureli mesaj temizleme hatasi", e)
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "disappearing_message_cleaner"

        /**
         * Periyodik temizlik gorevini baslatir. 15 dakikada bir calisir.
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<DisappearingMessageWorker>(
                15, TimeUnit.MINUTES
            ).build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request
                )

            Log.d("DisappearingWorker", "Periyodik temizlik zamanlandi")
        }
    }
}
