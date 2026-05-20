package com.securechat.app.data

import android.util.Log
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.PendingTimerUpdateDao
import com.securechat.storage.entity.PendingTimerUpdateEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Sureli mesaj timer guncellemeleri icin offline kuyruk yoneticisi.
 *
 * `ChatInfoViewModel.setDisappearingDuration` ve `GroupInfoViewModel.setDisappearingDuration`
 * cagrildiginda WS uzerinden DisappearingTimer signal gonderir. Signal kuyruga alinamazsa
 * (WS kapali / sendSignal false donerse) bu sinif PendingTimerUpdate tablosuna kaydeder.
 *
 * Reconnect oldugunda `SignalingClient.onReconnectedCallback` icinden `flush()` cagrilir,
 * tum bekleyen guncellemeler tekrar denenir. Basariliysa silinir, basarisiz olanlar kalir.
 *
 * Boylece kullanici timer'i offline iken degistirse de internet gelince karsi taraf
 * otomatik olarak guncel olur.
 */
@Singleton
class PendingTimerFlusher @Inject constructor(
    private val signalingClient: SignalingClient,
    private val pendingTimerUpdateDao: PendingTimerUpdateDao,
    private val userSession: UserSession
) {

    /**
     * Tek bir guncellemeyi gonderir. Basariliysa true, kuyruga alinmasi gerekiyorsa false.
     */
    fun trySend(targetUserId: String, conversationId: String, duration: Long): Boolean {
        val senderId = userSession.userId ?: return false
        val signal = SignalMessage.DisappearingTimer(
            senderId = senderId,
            recipientId = targetUserId,
            timestamp = System.currentTimeMillis(),
            duration = duration,
            conversationId = conversationId
        )
        return signalingClient.sendSignal(signal)
    }

    /**
     * Guncellemeyi gonderim icin dener; basarisiz ise persistent kuyruga ekler.
     * ViewModel'ler bu metodu cagirir — direkt `sendSignal` yerine.
     */
    suspend fun sendOrQueue(targetUserId: String, conversationId: String, duration: Long) {
        // userId yoksa kullaniciyi kuyruga almak anlamsiz — flush sirasinda yine senderId
        // gerekiyor. Kullanici giris yapmamissa bu cagri zaten anlamsiz, sessizce iptal et.
        if (userSession.userId == null) return
        if (!trySend(targetUserId, conversationId, duration)) {
            pendingTimerUpdateDao.insert(
                PendingTimerUpdateEntity(
                    conversationId = conversationId,
                    targetUserId = targetUserId,
                    duration = duration
                )
            )
            Log.d(TAG, "Timer guncellemesi kuyruga alindi: conv=$conversationId target=$targetUserId")
        }
    }

    /**
     * Tum bekleyen timer guncellemelerini gonder. Basariliyi sil, basarisizi birak.
     * AppLifecycleObserver reconnect callback'inden cagrir.
     */
    suspend fun flush() {
        val pending = pendingTimerUpdateDao.getAll()
        if (pending.isEmpty()) return
        Log.d(TAG, "Pending timer flush: ${pending.size} guncelleme")
        for (entry in pending) {
            if (trySend(entry.targetUserId, entry.conversationId, entry.duration)) {
                pendingTimerUpdateDao.deleteById(entry.id)
            } else {
                // WS yine kopuk — sonraki reconnect'e birak
                break
            }
        }
    }

    companion object {
        private const val TAG = "PendingTimerFlusher"
    }
}
