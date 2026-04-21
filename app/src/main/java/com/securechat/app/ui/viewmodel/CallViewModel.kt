package com.securechat.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.media.model.CallSession
import com.securechat.network.model.CallType
import com.securechat.storage.dao.ConversationDao
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
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
    private val userSession: UserSession,
    private val conversationDao: ConversationDao
) : ViewModel() {

    private val peerId: String = savedStateHandle.get<String>("peerId") ?: ""
    private val callTypeStr: String = savedStateHandle.get<String>("callType") ?: "VOICE"

    val callState: StateFlow<CallSession?> = callManager.callSession

    private val _callDuration = MutableStateFlow(0L)
    val callDuration: StateFlow<Long> = _callDuration.asStateFlow()

    /** Karsi tarafin video track'i — SurfaceViewRenderer'a baglanir (1-to-1). */
    val remoteVideoTrack: StateFlow<VideoTrack?> = callManager.remoteVideoTrackFlow

    /** Grup aramasi remote video track'leri — peerId -> VideoTrack. */
    val remoteVideoTracks: StateFlow<Map<String, VideoTrack>> = callManager.remoteVideoTracksFlow

    /** Yerel kamera video track'i — PIP SurfaceViewRenderer icin. */
    val localVideoTrack: StateFlow<VideoTrack?> = callManager.localVideoTrackFlow

    /** EGL context — SurfaceViewRenderer.init() icin gerekli. */
    val eglBaseContext: EglBase.Context? get() = callManager.eglBaseContext

    /** Karsi tarafin kamera durumu — false ise overlay gosterilir. */
    val remoteCameraEnabled: StateFlow<Boolean> = IncomingMessageHandler.remoteCameraEnabled

    init {
        IncomingMessageHandler.currentChatId = "call_$peerId"
        android.util.Log.d("CallViewModel", "Current chat set to: call_$peerId")

        val current = callManager.currentSession
        android.util.Log.d("CallVM", "init: peerId=$peerId callType=$callTypeStr currentSession=${current?.state} userId=${userSession.userId}")

        val hasIncomingOrActiveCall = current != null && (
            (current.direction == com.securechat.media.model.CallDirection.INCOMING && current.state == com.securechat.media.model.CallState.RINGING) ||
            current.state == com.securechat.media.model.CallState.ACTIVE
        )

        if (hasIncomingOrActiveCall) {
            android.util.Log.d("CallVM", "SMART FIX: incoming/active call var, otomatik call engellendi")
        } else if (peerId.isNotBlank()) {
            val callType = try { CallType.valueOf(callTypeStr) } catch (_: Exception) { CallType.VOICE }

            // Grup konusmasi mi kontrol et
            if (peerId.startsWith("group_")) {
                // Grup aramasi — uyeleri DB'den cek ve grup aramasi baslat
                viewModelScope.launch(Dispatchers.IO) {
                    val conv = conversationDao.getById(peerId)
                    val members = conv?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                    val userId = userSession.userId ?: "unknown"
                    // Kendisini cikar
                    val otherMembers = members.filter { it != userId }
                    if (otherMembers.isNotEmpty()) {
                        android.util.Log.d("CallVM", "Grup aramasi baslatiliyor: $peerId, ${otherMembers.size} uye")
                        callManager.initiateGroupCall(peerId, otherMembers, callType, userId)
                    } else {
                        android.util.Log.e("CallVM", "Grup uyesi bulunamadi: $peerId")
                    }
                }
            } else {
                // Normal 1-to-1 arama
                android.util.Log.d("CallVM", "Manuel call baslatiliyor: $peerId $callType")
                callManager.initiateCall(peerId, callType, userSession.userId ?: "unknown")
            }
        } else {
            android.util.Log.d("CallVM", "peerId bos, call baslatilmiyor")
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
        IncomingMessageHandler.currentChatId = null
        IncomingMessageHandler.remoteCameraEnabled.value = true
        android.util.Log.d("CallViewModel", "Current chat cleared from call")
    }
}
