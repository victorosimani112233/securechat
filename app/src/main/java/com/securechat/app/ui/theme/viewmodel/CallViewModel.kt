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
import com.securechat.storage.resolver.ContactNameResolver
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
    private val savedStateHandle: SavedStateHandle,
    private val callManager: CallManager,
    private val userSession: UserSession,
    private val conversationDao: ConversationDao,
    private val contactNameResolver: ContactNameResolver,
    private val phoneAccountRegistrar: dagger.Lazy<com.securechat.telecom.PhoneAccountRegistrar>
) : ViewModel() {

    companion object {
        /** SavedStateHandle key — bu ViewModel call'i baslattigini hatirlasin. */
        private const val KEY_CALL_INITIATED = "call_initiated"
    }

    private val peerId: String = savedStateHandle.get<String>("peerId") ?: ""
    private val callTypeStr: String = savedStateHandle.get<String>("callType") ?: "VOICE"

    val callState: StateFlow<CallSession?> = callManager.callSession

    private val _callDuration = MutableStateFlow(0L)
    val callDuration: StateFlow<Long> = _callDuration.asStateFlow()

    /** Karsi tarafin gosterilecek adi — UUID yerine rehber/DB ismi. */
    private val _peerDisplayName = MutableStateFlow(peerId)
    val peerDisplayName: StateFlow<String> = _peerDisplayName.asStateFlow()

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

    /** Aktif arama sirasinda gelen ikinci arama — UI banner icin. */
    val secondaryIncomingCall: StateFlow<CallSession?> = callManager.secondaryIncomingCall

    /** Bekleyen ikinci aramanin gosterim adi (UUID yerine isim). */
    private val _secondaryPeerDisplayName = MutableStateFlow<String>("")
    val secondaryPeerDisplayName: StateFlow<String> = _secondaryPeerDisplayName.asStateFlow()

    init {
        // Secondary call peer ismini her degisiminde coz
        viewModelScope.launch(Dispatchers.IO) {
            callManager.secondaryIncomingCall.collect { session ->
                if (session != null && session.peerId.isNotBlank()) {
                    _secondaryPeerDisplayName.value = try {
                        contactNameResolver.resolveDisplayName(session.peerId)
                    } catch (_: Exception) { session.peerId }
                } else {
                    _secondaryPeerDisplayName.value = ""
                }
            }
        }
    }

    init {
        IncomingMessageHandler.currentChatId = "call_$peerId"
        android.util.Log.d("CallViewModel", "Current chat set to: call_$peerId")

        // Peer ismini coz — UUID yerine rehber/DB ismi goster
        if (peerId.isNotBlank()) {
            viewModelScope.launch(Dispatchers.IO) {
                if (peerId.startsWith("group_")) {
                    val conv = conversationDao.getById(peerId)
                    _peerDisplayName.value = conv?.peerName ?: peerId
                } else {
                    _peerDisplayName.value = contactNameResolver.resolveDisplayName(peerId)
                }
            }
        }

        val current = callManager.currentSession
        // GHOST CALL FIX: SavedStateHandle ile re-create'lerde initiateCall'i engelle.
        // ViewModel her olusturuldugunda init blogu calisirdi — Compose recomposition,
        // configuration change, navigation re-entry sonrasi currentSession null gorunce
        // OTOMATIK initiateCall yapip hayalet arama uretirdi. Flag SavedStateHandle Bundle
        // ile korunur, ayni ViewModel tekrar olusursa true gorulur, atlanir.
        val alreadyInitiated = savedStateHandle.get<Boolean>(KEY_CALL_INITIATED) ?: false
        android.util.Log.d("CallVM", "init: peerId=$peerId callType=$callTypeStr currentSession=${current?.state} userId=${userSession.userId} alreadyInitiated=$alreadyInitiated")

        val hasIncomingOrActiveCall = current != null && (
            (current.direction == com.securechat.media.model.CallDirection.INCOMING && current.state == com.securechat.media.model.CallState.RINGING) ||
            current.state == com.securechat.media.model.CallState.ACTIVE
        )

        if (alreadyInitiated) {
            android.util.Log.w("CallVM", "ViewModel re-create: initiateCall ATLANDI (call_initiated flag true) — hayalet call onlendi")
        } else if (hasIncomingOrActiveCall) {
            android.util.Log.d("CallVM", "SMART FIX: incoming/active call var, otomatik call engellendi")
            // Bu da ilk initiate sayilir — sonraki re-create'lerde otomatik baslama
            savedStateHandle[KEY_CALL_INITIATED] = true
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
                        savedStateHandle[KEY_CALL_INITIATED] = true
                    } else {
                        android.util.Log.e("CallVM", "Grup uyesi bulunamadi: $peerId")
                    }
                }
            } else {
                // Normal 1-to-1 arama — flag set EDEREK, tekrar tetiklenmesin
                android.util.Log.d("CallVM", "Manuel call baslatiliyor: $peerId $callType")
                callManager.initiateCall(peerId, callType, userSession.userId ?: "unknown")
                savedStateHandle[KEY_CALL_INITIATED] = true
                notifyTelecomOutgoing(peerId, callType)
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

    /**
     * Telecom Framework'e giden arama bildirimi yapar.
     * Sistem [com.securechat.telecom.SecureChatConnectionService.onCreateOutgoingConnection]
     * çağrılır → bridge `onConnectionCreated` + `startDialing` → state observer ACCEPT
     * geldiğinde `setActive` eder. API 26+ koşulu ConnectionService gereği.
     */
    private fun notifyTelecomOutgoing(peerId: String, callType: CallType) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        val session = callManager.currentSession ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val peerName = try { contactNameResolver.resolveDisplayName(peerId) } catch (_: Exception) { peerId }
            try {
                phoneAccountRegistrar.get().placeOutgoingCall(
                    callId = session.callId,
                    peerId = peerId,
                    peerName = peerName,
                    isVideo = callType == CallType.VIDEO
                )
            } catch (e: Exception) {
                android.util.Log.w("CallVM", "Telecom placeOutgoingCall hatasi: ${e.message}")
            }
        }
    }

    fun acceptCall() = callManager.acceptCall(userSession.userId ?: "")

    /** Bekleyen ikinci aramayi kabul et: mevcut kapatilir, yeni acilir. */
    fun acceptSecondaryCall() = callManager.acceptSecondaryCall(userSession.userId ?: "")

    /** Bekleyen ikinci aramayi reddet: caller'a REJECT, banner kaybolur. */
    fun rejectSecondaryCall() = callManager.rejectSecondaryCall(userSession.userId ?: "")

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
