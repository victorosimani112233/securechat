package com.securechat.telecom

import android.os.Build
import android.telecom.CallAudioState
import android.telecom.DisconnectCause
import android.util.Log
import androidx.annotation.RequiresApi
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.media.model.CallState
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.Lazy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Telecom Framework ile uygulama tarafı (CallManager) arasındaki köprü.
 *
 * Akış:
 *  - Sistem connection oluşturur → [onConnectionCreated] çağrılır → bridge ID ile track eder.
 *  - Kullanıcı sistem UI'inde "Kabul Et" → [onUserAnswered] → CallManager.acceptCall()
 *  - Kullanıcı "Reddet" → [onUserRejected] → CallManager.rejectCall()
 *  - Kullanıcı "Kapat" → [onUserHangup] → CallManager.endCall()
 *  - CallManager state değişince → bridge connection'ı setActive/setDisconnected eder
 *    (CallStateObserver tarafından).
 *
 * CallManager (media module) telecom'u bilmez — bridge senkronizasyonu yapar.
 * Lazy<CallManager> cycle önler (CallManager → SignalingClient → ... cycle riski).
 */
@Singleton
@RequiresApi(Build.VERSION_CODES.O)
class TelecomCallBridge @Inject constructor(
    @ApplicationContext private val context: android.content.Context,
    private val callManagerLazy: Lazy<CallManager>,
    private val userSession: UserSession
) : ConnectionBridge {

    private val callManager: CallManager get() = callManagerLazy.get()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** Aktif Connection'ları callId ile track et. */
    private val connections = ConcurrentHashMap<String, SecureChatConnection>()

    @Volatile
    private var stateObserverStarted = false

    override fun onConnectionCreated(callId: String, connection: SecureChatConnection) {
        Log.d(TAG, "Connection registered: $callId")
        connections[callId] = connection
        startStateObserverIfNeeded()
    }

    override fun onUserAnswered(callId: String) {
        Log.d(TAG, "User answered: $callId")
        val userId = userSession.userId ?: return
        callManager.acceptCall(userId)
    }

    override fun onUserRejected(callId: String) {
        Log.d(TAG, "User rejected: $callId")
        val userId = userSession.userId ?: return
        callManager.rejectCall(userId)
        connections.remove(callId)
    }

    override fun onUserHangup(callId: String) {
        Log.d(TAG, "User hangup: $callId")
        val userId = userSession.userId ?: return
        callManager.endCall(userId)
        connections.remove(callId)
    }

    /**
     * Sistem audio route degisikligini CallManager'a yansit.
     * SELF_MANAGED ConnectionService'de sistem route'u kendisi uygular; biz yalnız
     * UI durumunu (isSpeakerOn) senkronize ederiz. BT/WIRED_HEADSET/EARPIECE → speaker off,
     * SPEAKER → speaker on. Bu sayede kullanıcı sistem volume HUD'undan hoparloru
     * acip kapattığında CallScreen butonu doğru gözükür.
     */
    override fun onAudioStateChanged(callId: String, state: CallAudioState) {
        val isSpeaker = state.route == CallAudioState.ROUTE_SPEAKER
        Log.d(TAG, "Audio route changed: route=${state.route} isSpeaker=$isSpeaker muted=${state.isMuted}")
        try {
            callManager.notifyAudioRouteChanged(isSpeaker)
        } catch (e: Exception) {
            Log.w(TAG, "notifyAudioRouteChanged hata: ${e.message}")
        }
    }

    override fun onMuteToggled(callId: String, muted: Boolean) {
        // Şimdilik no-op: CallManager.toggleMute zaten state'i takip ediyor
    }

    /**
     * CallManager.callSession Flow'unu tek seferlik subscribe et — state değişikliklerini
     * Telecom Connection'a yansıt (setActive, setDisconnected, vb).
     */
    private fun startStateObserverIfNeeded() {
        if (stateObserverStarted) return
        stateObserverStarted = true
        scope.launch {
            try {
                callManager.callSession.collectLatest { session ->
                    if (session == null) {
                        // Tüm Connection'ları temizle
                        connections.values.forEach {
                            try { it.connectionEnded(DisconnectCause(DisconnectCause.LOCAL)) } catch (_: Exception) {}
                        }
                        connections.clear()
                        return@collectLatest
                    }
                    val conn = connections.values.firstOrNull() ?: return@collectLatest
                    when (session.state) {
                        CallState.ACTIVE -> {
                            try { conn.connectionActive() } catch (_: Exception) {}
                        }
                        CallState.ENDED -> {
                            try { conn.connectionEnded(DisconnectCause(DisconnectCause.LOCAL)) } catch (_: Exception) {}
                            connections.clear()
                        }
                        CallState.REJECTED -> {
                            try { conn.connectionEnded(DisconnectCause(DisconnectCause.REJECTED)) } catch (_: Exception) {}
                            connections.clear()
                        }
                        CallState.FAILED -> {
                            try { conn.connectionEnded(DisconnectCause(DisconnectCause.ERROR)) } catch (_: Exception) {}
                            connections.clear()
                        }
                        CallState.BUSY -> {
                            try { conn.connectionEnded(DisconnectCause(DisconnectCause.BUSY)) } catch (_: Exception) {}
                            connections.clear()
                        }
                        else -> { /* INITIATING/RINGING/CONNECTING — Connection zaten setRinging/setDialing */ }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "State observer hata: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "TelecomBridge"
    }
}
