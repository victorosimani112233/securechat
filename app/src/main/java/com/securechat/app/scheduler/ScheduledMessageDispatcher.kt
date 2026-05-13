package com.securechat.app.scheduler

import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.app.ui.viewmodel.RepeatType
import com.securechat.app.ui.viewmodel.ScheduledMessageViewModel
import com.securechat.storage.dao.ScheduledMessageDao
import com.securechat.storage.entity.ScheduledMessageEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Planli mesaj islem mantigi — Receiver ve Worker'in ortak business logic'i.
 *
 * `ScheduledMessageReceiver` (AlarmManager tetikledi) ve `ScheduledMessageWorker`
 * (WorkManager periodic fallback) ikisi de bu sinifa delege eder. Boylelikle:
 *   - DRY: tekrarlama mantigi tek yerde
 *   - TEST: BroadcastReceiver / CoroutineWorker mock'lamak zor; bu sinif pure DI,
 *     direkt unit test edilebilir
 *
 * Davranis:
 *   1. Plan DB'de yoksa veya disabled ise → no-op
 *   2. recipientIds bos ise → DB'den sil
 *   3. Tum alicilara `SendMessageUseCase` ile gonder (bir tanesi fail → digerlerine devam)
 *   4. Tekrarlama:
 *      - ONCE → deleteById
 *      - DAILY/CUSTOM → nextTriggerTime hesapla, update, yeni alarm schedule
 */
@Singleton
class ScheduledMessageDispatcher @Inject constructor(
    private val scheduledMessageDao: ScheduledMessageDao,
    private val sendMessageUseCase: SendMessageUseCase,
    private val alarmScheduler: ScheduledMessageAlarmScheduler
) {

    /**
     * Bir plan'i isle: mesajlari gonder ve tekrarlama mantigini uygula.
     * @return işlenen plan, veya plan yok/disabled ise null
     */
    suspend fun processPlan(planId: String): ScheduledMessageEntity? {
        val entity = scheduledMessageDao.getById(planId)
        if (entity == null) {
            android.util.Log.w(TAG, "Plan $planId DB'de yok, atlandi")
            return null
        }
        if (!entity.isEnabled) {
            android.util.Log.w(TAG, "Plan $planId disabled, atlandi")
            return null
        }

        val recipients = entity.recipientIds.split(",").filter { it.isNotBlank() }
        if (recipients.isEmpty()) {
            android.util.Log.w(TAG, "Plan $planId alici listesi bos, siliniyor")
            scheduledMessageDao.deleteById(planId)
            return entity
        }

        // Tum alicilara mesaj — bireysel hata digerlerini etkilemez
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

        // Tekrarlama mantigi
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
        return entity
    }

    companion object {
        private const val TAG = "ScheduledMsgDispatcher"
    }
}
