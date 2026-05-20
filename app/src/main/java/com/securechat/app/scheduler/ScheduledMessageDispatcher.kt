package com.securechat.app.scheduler

import com.securechat.app.BuildConfig
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.app.ui.viewmodel.RepeatType
import com.securechat.app.ui.viewmodel.ScheduledMessageViewModel
import com.securechat.network.SignalingClient
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
    private val alarmScheduler: ScheduledMessageAlarmScheduler,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession
) {

    /**
     * Bir plan'i isle: mesajlari gonder ve tekrarlama mantigini uygula.
     * @return işlenen plan, veya plan yok/disabled/bağlanılamadı ise null
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

        // WS baglantisi garantiye al — app arka plandayken AppLifecycleObserver disconnect
        // etmis olabilir. Bağlanamazsak hicbir sey yapma, plan'i ilerletme, mesaj kaydetme
        // — periodik ScheduledMessageWorker getDueMessages ile geri donup tekrar dener.
        // Boylelikle FAILED + kirmizi unlem hic olusmaz.
        val userId = userSession.userId
        val token = userSession.accessToken
        val openedWsHere = signalingClient.connectionState.value !is com.securechat.network.model.ConnectionState.Connected
        if (userId == null || token.isNullOrBlank()) {
            android.util.Log.w(TAG, "Plan $planId: kullanici/token yok, plan korunuyor, sonraki worker cycle'da denenecek")
            return null
        }
        val connected = signalingClient.ensureConnected(
            userId = userId,
            authToken = token,
            customUrl = BuildConfig.SIGNALING_URL,
            timeoutMs = CONNECT_TIMEOUT_MS
        )
        if (!connected) {
            android.util.Log.w(TAG, "Plan $planId: WS bağlantısı kurulamadı, plan korunuyor, sonraki worker cycle'da denenecek")
            return null
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

        // Bagliyiz ve WS'yi bu cagrida biz actiysak + app arka plandaysa: pil tasarrufu icin kapat.
        // Foreground'da AppLifecycleObserver yonettigi icin dokunma.
        if (openedWsHere && !IncomingMessageHandler.isAppInForeground) {
            signalingClient.disconnect()
            android.util.Log.d(TAG, "Plan $planId: arka plan — WS kapatildi")
        }
        return entity
    }

    companion object {
        private const val TAG = "ScheduledMsgDispatcher"
        /** WS bağlantısı açılması için bekleme süresi — WebSocketDrainWorker ile aynı pattern */
        private const val CONNECT_TIMEOUT_MS = 8_000L
    }
}
