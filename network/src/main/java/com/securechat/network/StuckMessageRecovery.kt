package com.securechat.network

import android.util.Log
import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * SENDING durumunda takili kalan mesajlari kurtaran sinif (Bug 003).
 *
 * WebSocket baglantisi gonderim sirasinda koparsa mesaj SENDING durumunda kalir.
 * Bu sinif belirtilen timeout suresinden eski SENDING mesajlari FAILED olarak isaretler.
 *
 * Tetikleme: SignalingClient.onReconnectedCallback uzerinden, yeniden baglanti kuruldugunda
 * otomatik olarak cagrilir.
 */
@Singleton
class StuckMessageRecovery @Inject constructor(
    private val messageRepository: MessageRepository
) {
    /**
     * Belirtilen timeout suresinden eski SENDING mesajlari FAILED olarak isaretler.
     *
     * @param timeoutMs Timeout suresi (milisaniye). Varsayilan 30 saniye.
     * @return FAILED olarak isaretlenen mesaj sayisi
     */
    suspend fun recoverStuckMessages(timeoutMs: Long = SignalingClient.STUCK_MESSAGE_TIMEOUT_MS): Int {
        val cutoff = System.currentTimeMillis() - timeoutMs
        val recoveredCount = messageRepository.markStuckMessagesAsFailed(cutoff)
        if (recoveredCount > 0) {
            Log.w(TAG, "Recovered $recoveredCount stuck SENDING messages (marked as FAILED)")
        }
        return recoveredCount
    }

    companion object {
        private const val TAG = "StuckMessageRecovery"
    }
}
