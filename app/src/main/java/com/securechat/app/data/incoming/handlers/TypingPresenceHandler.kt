package com.securechat.app.data.incoming.handlers

import com.securechat.app.data.IncomingMessageHandler
import com.securechat.network.SignalMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Karsi tarafin yazma + cevrimici state'lerini isler.
 *
 * Faz 10: IncomingMessageHandler.handleTypingIndicator + handlePresenceUpdate
 * extract edildi. Global typingStates/presenceStates Flow'lari IncomingMessageHandler
 * companion'inda kalir (cok yerden okunuyor) — handler bunlari update eder.
 *
 * Typing icin: 10 saniyelik timeout — sinyal kaybolursa otomatik temizlik.
 */
@Singleton
class TypingPresenceHandler @Inject constructor() {

    /** Typing timeout job'lari — her kullanici icin ayri. Handler scope'unda yasiyor. */
    private val typingTimeoutJobs = mutableMapOf<String, Job>()

    /**
     * Yazma gostergesi handler — IncomingMessageHandler'in scope'una ihtiyac duyar
     * (timeout coroutine icin). Bu yuzden SignalHandler<T> interface'ini implement
     * etmiyor; ozel imza.
     */
    fun onTyping(signal: SignalMessage.TypingIndicator, scope: CoroutineScope) {
        typingTimeoutJobs[signal.senderId]?.cancel()
        val current = IncomingMessageHandler.typingStates.value.toMutableMap()
        if (signal.isTyping) {
            current[signal.senderId] = true
            IncomingMessageHandler.typingStates.value = current
            // 10 saniye sonra otomatik temizle (sinyal kaybolursa)
            typingTimeoutJobs[signal.senderId] = scope.launch {
                delay(10_000)
                val updated = IncomingMessageHandler.typingStates.value.toMutableMap()
                updated.remove(signal.senderId)
                IncomingMessageHandler.typingStates.value = updated
            }
        } else {
            current.remove(signal.senderId)
            IncomingMessageHandler.typingStates.value = current
        }
    }

    fun onPresence(signal: SignalMessage.PresenceUpdate) {
        val current = IncomingMessageHandler.presenceStates.value.toMutableMap()
        // Karsi taraf son gorulmeyi gizliyorsa lastSeen=0 olarak kaydet
        val effectiveLastSeen = if (signal.hideLastSeen) 0L else signal.lastSeen
        current[signal.senderId] = IncomingMessageHandler.PresenceInfo(
            isOnline = signal.isOnline,
            lastSeen = effectiveLastSeen
        )
        IncomingMessageHandler.presenceStates.value = current
        android.util.Log.d(
            "TypingPresenceHandler",
            "Presence: ${signal.senderId} online=${signal.isOnline} lastSeen=$effectiveLastSeen hideLastSeen=${signal.hideLastSeen}"
        )
    }
}
