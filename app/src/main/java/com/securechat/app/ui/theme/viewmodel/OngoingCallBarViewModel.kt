package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.media.CallManager
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import com.securechat.storage.resolver.ContactNameResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * OngoingCallBar icin durum saglar.
 *
 * Aktif arama varsa (ACTIVE/CONNECTING) bar gosterilir. Peer ismi
 * ContactNameResolver ile cozulur — UUID yerine kullanici dostu ad.
 *
 * Bar her ekran refresh'inde lokal ticker ile sure yenilenir;
 * bu VM sadece BASLANGIC durumu saglar (startTime'a gore o anki ms).
 */
@HiltViewModel
class OngoingCallBarViewModel @Inject constructor(
    private val callManager: CallManager,
    private val contactNameResolver: ContactNameResolver
) : ViewModel() {

    data class OngoingCallInfo(
        val peerId: String,
        val displayName: String,
        val callType: CallType,
        val durationMs: Long
    )

    private val _displayName = MutableStateFlow<Pair<String, String>?>(null)

    /**
     * Bar'da gosterilecek info. null = bar gizli.
     * Aktif state: ACTIVE veya CONNECTING (ringing'de bar yok — kullanici zaten CallScreen'de).
     */
    val ongoingCall: StateFlow<OngoingCallInfo?> = callManager.callSession.map { session ->
        toInfo(session)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    init {
        // peerId degisirse ismi yeniden coz — async, ana flow'u bloklamaz
        viewModelScope.launch {
            callManager.callSession.collect { session ->
                if (session != null && isBarEligible(session.state)) {
                    val resolved = try {
                        contactNameResolver.resolveDisplayName(session.peerId)
                    } catch (_: Exception) {
                        session.peerId.take(8)
                    }
                    _displayName.value = session.peerId to resolved
                } else {
                    _displayName.value = null
                }
            }
        }
    }

    private fun toInfo(session: CallSession?): OngoingCallInfo? {
        if (session == null || !isBarEligible(session.state)) return null
        val now = System.currentTimeMillis()
        val durationMs = session.startTime?.let { now - it } ?: 0L
        val displayName = _displayName.value
            ?.takeIf { it.first == session.peerId }
            ?.second
            ?: session.peerId.take(8)
        return OngoingCallInfo(
            peerId = session.peerId,
            displayName = displayName,
            callType = session.callType,
            durationMs = durationMs
        )
    }

    private fun isBarEligible(state: CallState): Boolean = when (state) {
        CallState.ACTIVE, CallState.CONNECTING -> true
        else -> false
    }
}
