package com.securechat.app.data.incoming.handlers

import com.securechat.network.SignalMessage
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Karsi taraftan gelen DisappearingTimer signal'i isler.
 *
 * - conversation.disappearingDuration alani guncellenir
 * - Race penceresi: timer signal mesajdan once gelmediyse (FCM push sirasi
 *   farkli olabilir) son 60 sn icindeki gelen mesajlara retroaktif expiresAt uygula
 *
 * Faz 10: IncomingMessageHandler.handleDisappearingTimer extract edildi.
 */
@Singleton
class DisappearingTimerHandler @Inject constructor(
    private val conversationDao: ConversationDao,
    private val messageRepository: MessageRepository
) : SignalHandler<SignalMessage.DisappearingTimer> {

    override suspend fun handle(signal: SignalMessage.DisappearingTimer) {
        // conversationId bos ise birebir sohbet — senderId = konusma ID'si
        val targetConvId = signal.conversationId.ifBlank { signal.senderId }
        android.util.Log.d(
            "DisappearingTimerHandler",
            "duration=${signal.duration} from=${signal.senderId} conv=$targetConvId"
        )
        conversationDao.updateDisappearingDuration(targetConvId, signal.duration)

        if (signal.duration > 0) {
            val now = System.currentTimeMillis()
            val windowStart = now - RACE_WINDOW_MS
            try {
                messageRepository.applyRetroactiveExpiry(
                    conversationId = targetConvId,
                    duration = signal.duration,
                    windowStart = windowStart,
                    now = now
                )
            } catch (e: Exception) {
                android.util.Log.w("DisappearingTimerHandler", "Retroaktif expiresAt uygulanamadi: ${e.message}")
            }
        }
    }

    companion object {
        /** Race penceresi: timer signal gec geldiginde son N saniyedeki gelen mesajlara retroaktif. */
        private const val RACE_WINDOW_MS = 60_000L
    }
}
