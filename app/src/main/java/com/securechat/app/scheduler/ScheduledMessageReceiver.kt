package com.securechat.app.scheduler

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
 * AlarmManager tetiklediginde planli mesaji gonderir + sonraki alarm'i schedule eder.
 * Business logic [ScheduledMessageDispatcher]'da — bu sinif thin wrapper.
 *
 * BroadcastReceiver kisa omurlu — coroutine icin `goAsync()` ile pending result tutar.
 */
@AndroidEntryPoint
class ScheduledMessageReceiver : BroadcastReceiver() {

    @Inject lateinit var dispatcher: ScheduledMessageDispatcher

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ScheduledMessageAlarmScheduler.ACTION_TRIGGER) return
        val planId = intent.getStringExtra(ScheduledMessageAlarmScheduler.EXTRA_PLAN_ID) ?: return

        android.util.Log.d(TAG, "Alarm tetiklendi: plan=$planId")

        val pendingResult = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                dispatcher.processPlan(planId)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Plan islenirken hata: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val TAG = "ScheduledMsgReceiver"
    }
}
