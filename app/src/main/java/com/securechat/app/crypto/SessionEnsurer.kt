package com.securechat.app.crypto

import android.util.Log
import com.securechat.crypto.SessionManager
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.whispersystems.libsignal.SignalProtocolAddress
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Belirli bir recipient ile Signal Protocol session'i mevcut degilse PreKeyBundle
 * fetch'leyip X3DH key agreement ile yenisini kurar.
 *
 * Concurrent ensure cagrilari per-recipient Mutex ile tek calisma altinda
 * birlesir — ayni recipient icin iki istek gelse bile tek bir fetch yapilir.
 */
@Singleton
class SessionEnsurer @Inject constructor(
    private val sessionManager: SessionManager,
    private val preKeyBundleFetcher: PreKeyBundleFetcher
) {
    private val mutexes = ConcurrentHashMap<String, Mutex>()

    /**
     * @param recipientId Hedef kullanici UUID
     * @return Session kurulduysa veya zaten varsa true; bundle alinamadiysa false
     */
    suspend fun ensureSession(recipientId: String): Boolean {
        // Hizli yol: session zaten varsa kilit almaya gerek yok
        if (sessionManager.hasSession(recipientId)) return true

        val mutex = mutexes.computeIfAbsent(recipientId) { Mutex() }
        return mutex.withLock {
            // Mutex icinde tekrar kontrol — baska coroutine kurmus olabilir
            if (sessionManager.hasSession(recipientId)) return@withLock true
            val bundle = preKeyBundleFetcher.fetch(recipientId)
            if (bundle == null) {
                Log.w("SessionEnsurer", "PreKeyBundle alinamadi: $recipientId")
                return@withLock false
            }
            try {
                val address = SignalProtocolAddress(recipientId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID)
                sessionManager.createSession(address, bundle)
                Log.d("SessionEnsurer", "Yeni Signal session kuruldu: $recipientId")
                true
            } catch (e: Exception) {
                Log.e("SessionEnsurer", "Session olusturma hatasi ($recipientId): ${e.message}")
                false
            }
        }
    }
}
