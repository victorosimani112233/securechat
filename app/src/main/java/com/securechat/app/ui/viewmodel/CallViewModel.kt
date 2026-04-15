package com.securechat.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.media.model.CallSession
import com.securechat.network.model.CallType
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.webrtc.EglBase
import org.webrtc.VideoTrack
import javax.inject.Inject

@HiltViewModel
class CallViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val callManager: CallManager,
    private val userSession: UserSession
) : ViewModel() {

    private val peerId: String = savedStateHandle.get<String>("peerId") ?: ""
    private val callTypeStr: String = savedStateHandle.get<String>("callType") ?: "VOICE"

    val callState: StateFlow<CallSession?> = callManager.callSession

    private val _callDuration = MutableStateFlow(0L)
    val callDuration: StateFlow<Long> = _callDuration.asStateFlow()

    /** Karsi tarafin video track'i — SurfaceViewRenderer'a baglanir. */
    val remoteVideoTrack: StateFlow<VideoTrack?> = callManager.remoteVideoTrackFlow

    /** Yerel kamera video track'i — PIP SurfaceViewRenderer icin. */
    val localVideoTrack: StateFlow<VideoTrack?> = callManager.localVideoTrackFlow

    /** EGL context — SurfaceViewRenderer.init() icin gerekli. */
    val eglBaseContext: EglBase.Context? get() = callManager.eglBaseContext

    init {
        // Call ekrandayken current chat'i call peer olarak set et
        // Arama sırasında o kişiden gelen mesajlar bildirim almasın
        IncomingMessageHandler.currentChatId = "call_$peerId"
        android.util.Log.d("CallViewModel", "Current chat set to: call_$peerId")

        // Arama ekrani acildiginda: gelen arama zaten var mi kontrol et
        // Yoksa giden arama baslat
        val current = callManager.currentSession
        android.util.Log.d("CallVM", "init: peerId=$peerId callType=$callTypeStr currentSession=${current?.state} userId=${userSession.userId}")
        // SMART FIX: Sadece incoming/active call varken otomatik call engelle
        // Manuel user-initiated call'lar çalışmaya devam etsin
        val hasIncomingOrActiveCall = current != null && (
            (current.direction == com.securechat.media.model.CallDirection.INCOMING && current.state == com.securechat.media.model.CallState.RINGING) ||
            current.state == com.securechat.media.model.CallState.ACTIVE
        )

        if (hasIncomingOrActiveCall) {
            android.util.Log.d("CallVM", "SMART FIX: incoming/active call var, otomatik initiateCall engellendi - duplicate call prevention")
        } else if (peerId.isNotBlank()) {
            // Normal manual call - çalışsın
            val callType = try { CallType.valueOf(callTypeStr) } catch (_: Exception) { CallType.VOICE }
            android.util.Log.d("CallVM", "SMART FIX: manuel call başlatılıyor: $peerId $callType")
            callManager.initiateCall(peerId, callType, userSession.userId ?: "unknown")
        } else {
            android.util.Log.d("CallVM", "SMART FIX: peerId boş, call başlatılmıyor")
        }

        viewModelScope.launch {
            while (isActive) {
                delay(1000)
                callManager.getCallDuration()?.let { _callDuration.value = it }
            }
        }
    }

    fun acceptCall() = callManager.acceptCall(userSession.userId ?: "")
    fun toggleMute() = callManager.toggleMute()
    fun toggleSpeaker() = callManager.toggleSpeaker()
    fun toggleCamera() = callManager.toggleCamera()
    fun switchCamera() = callManager.switchCamera()
    fun endCall() = callManager.endCall(userSession.userId ?: "")

    override fun onCleared() {
        super.onCleared()
        // Call ekrani kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null
        android.util.Log.d("CallViewModel", "Current chat cleared from call")
    }
}
