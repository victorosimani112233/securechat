package com.securechat.app.data

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.securechat.app.crypto.GroupSenderKeyDistributor
import com.securechat.storage.dao.ConversationDao
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Grup Sender Key'leri periyodik olarak rotate eden WorkManager worker'i.
 * Perfect forward secrecy icin (7 gun) — eski mesajlarin gelecekteki bir
 * sizintida cozulememesini saglar.
 *
 * Tum aktif gruplar icin yerel sender key'i rotate eder ve yeniden tum
 * uyelere SKDM dagitir. Network gerekir (constraint).
 */
@HiltWorker
class SenderKeyRotationWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val conversationDao: ConversationDao,
    private val distributor: GroupSenderKeyDistributor
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            val groups = conversationDao.getAllGroups()
            var rotated = 0
            for (group in groups) {
                val ok = distributor.rotate(group.id)
                if (ok) rotated++ else Log.w(TAG, "Rotate basarisiz: ${group.id}")
            }
            Log.d(TAG, "Periyodik SK rotate: $rotated/${groups.size} grup")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "SK rotation hatasi", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "SenderKeyRotator"
        private const val WORK_NAME = "sender_key_rotator"

        /** 7 gunde bir tum gruplar icin SK rotate'i zamanlar. NETWORK_CONNECTED zorunlu. */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = PeriodicWorkRequestBuilder<SenderKeyRotationWorker>(
                7, TimeUnit.DAYS
            ).setConstraints(constraints).build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            Log.d(TAG, "Periyodik SK rotate zamanlandi (7 gun)")
        }
    }
}
