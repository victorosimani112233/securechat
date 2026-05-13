package com.securechat.app.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.app.ui.viewmodel.RepeatType
import com.securechat.app.ui.viewmodel.ScheduledMessageViewModel
import com.securechat.storage.dao.ScheduledMessageDao
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * AlarmManager tetiklediginde planli mesaji gonderir + sonraki alarm'i schedule eder.
 *
 * Akis:
 *   1. Intent.EXTRA_PLAN_ID ile plan id alinir
 *   2. DB'den plan cekilir (silinmis/disabled ise no-op)
 *   3. recipientIds split → her birine SendMessageUseCase
 *   4. Tekrarlama:
 *      - ONCE   → DB'den deleteById (alarm da otomatik silinmis)
 *      - DAILY  → nextTriggerTime hesapla, update, alarmScheduler.schedule(updated)
 *      - CUSTOM → ayni
 *
 * BroadcastReceiver kisa omurlu — coroutine icin `goAsync()` ile pending result tut.
 */
@AndroidEntryPoint
class ScheduledMessageReceiver : BroadcastReceiver() {

    @Inject lateinit var scheduledMessageDao: ScheduledMessageDao
    @Inject lateinit var sendMessageUseCase: SendMessageUseCase
    @Inject lateinit var alarmScheduler: ScheduledMessageAlarmScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ScheduledMessageAlarmScheduler.ACTION_TRIGGER) return
        val planId = intent.getStringExtra(ScheduledMessageAlarmScheduler.EXTRA_PLAN_ID) ?: return

        android.util.Log.d(TAG, "Alarm tetiklendi: plan=$planId")

        // BroadcastReceiver async — pending result ile coroutine'i tut
        val pendingResult = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                processPlan(planId)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Plan islenirken hata: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun processPlan(planId: String) {
        val entity = scheduledMessageDao.getById(planId)
        if (entity == null) {
            android.util.Log.w(TAG, "Plan $planId DB'de yok, atlandi")
            return
        }
        if (!entity.isEnabled) {
            android.util.Log.w(TAG, "Plan $planId disabled, atlandi")
            return
        }

        // Tüm alicilara mesaj
        val recipients = entity.recipientIds.split(",").filter { it.isNotBlank() }
        if (recipients.isEmpty()) {
            android.util.Log.w(TAG, "Plan $planId alici listesi bos, siliniyor")
            scheduledMessageDao.deleteById(planId)
            return
        }
        for (recipientId in recipients) {
            try {
                sendMessageUseCase(
                    conversationId = recipientId,
                    content = entity.messageContent
                )
                android.util.Log.d(TAG, "Plan $planId → $recipientId gonderildi")
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Plan $planId → $recipientId gonderilmedi: ${e.message}")
            }
        }

        // Tekrarlama
        val repeatType = try {
            RepeatType.valueOf(entity.repeatType)
        } catch (_: Exception) {
            RepeatType.ONCE
        }

        when (repeatType) {
            RepeatType.ONCE -> {
                scheduledMessageDao.deleteById(planId)
                android.util.Log.d(TAG, "Plan $planId ONCE — silindi")
            }
            RepeatType.DAILY, RepeatType.CUSTOM -> {
                val days = entity.repeatDays
                    ?.split(",")
                    ?.mapNotNull { it.trim().toIntOrNull() }
                    ?.toSet()
                    ?: emptySet()
                val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
                    entity.hour, entity.minute, repeatType, days
                )
                val updated = entity.copy(nextTriggerTime = nextTrigger)
                scheduledMessageDao.update(updated)
                alarmScheduler.schedule(updated)
                android.util.Log.d(TAG, "Plan $planId ${repeatType.name} — yeni alarm: $nextTrigger")
            }
        }
    }

    companion object {
        private const val TAG = "ScheduledMsgReceiver"
    }
}
