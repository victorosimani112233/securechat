package com.securechat.telecom

import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.VideoProfile
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Android Telecom Framework ile SecureChat call lifecycle arasındaki köprü.
 *
 * Sistem bu Connection'ı [SecureChatConnectionService.onCreateIncomingConnection] veya
 * [SecureChatConnectionService.onCreateOutgoingConnection] çağrılarında oluşturur.
 *
 * Sistem callback'leri ([onAnswer], [onReject], [onDisconnect], [onHold]) kullanıcının
 * native arama UI'i üzerindeki etkileşimlerinden tetiklenir; biz bunları
 * [ConnectionBridge] üzerinden CallManager'a yönlendiririz.
 *
 * State akışı:
 *  - Gelen arama: Sistem connection oluşturur → [setRinging] → kullanıcı kabul → [onAnswer]
 *    → bridge.acceptCall() → CallManager.acceptCall → media kurulduğunda [setActive]
 *  - Giden arama: [setDialing] → karşı tarafta accept signal → [setActive]
 *  - Sonlanma: [setDisconnected] ile DisconnectCause set edilir, sistem connection'ı yok eder.
 *
 * Min SDK: O (API 26) — calling app'lerin self-managed ConnectionService desteği için 26+.
 */
@RequiresApi(Build.VERSION_CODES.O)
class SecureChatConnection(
    private val callId: String,
    private val peerId: String,
    private val isIncoming: Boolean,
    private val bridge: ConnectionBridge
) : Connection() {

    init {
        // Self-managed property — Android'in default phone UI'ini bypass et,
        // SecureChat kendi arama ekranını yönetiyor. Yine de ConnectionService
        // sistem entegrasyonunu (lock screen, audio routing, ongoing call chip) sağlar.
        connectionProperties = PROPERTY_SELF_MANAGED
        // Audio + video tipi sonradan setVideoState ile değiştirilebilir
        videoState = VideoProfile.STATE_AUDIO_ONLY
        connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_HOLD
        setInitializing()
    }

    /** Kullanıcı sistem UI'inden "Kabul Et" tıkladı. */
    override fun onAnswer() {
        Log.d(TAG, "onAnswer call=$callId peer=$peerId")
        bridge.onUserAnswered(callId)
        // CallManager media kurduktan sonra setActive() çağrılacak.
    }

    /** Kullanıcı "Kabul Et" — video ile. */
    override fun onAnswer(videoState: Int) {
        super.onAnswer(videoState)
        onAnswer()
    }

    /** Kullanıcı "Reddet" tıkladı. */
    override fun onReject() {
        Log.d(TAG, "onReject call=$callId peer=$peerId")
        bridge.onUserRejected(callId)
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
    }

    /** Kullanıcı "Kapat" tıkladı (aktif aramada). */
    override fun onDisconnect() {
        Log.d(TAG, "onDisconnect call=$callId peer=$peerId")
        bridge.onUserHangup(callId)
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }

    /** Bekletme/devam etme — şimdilik no-op. */
    override fun onHold() {
        Log.d(TAG, "onHold call=$callId")
        setOnHold()
    }

    override fun onUnhold() {
        Log.d(TAG, "onUnhold call=$callId")
        setActive()
    }

    /** Sistem audio değişikliği bildirir (Bluetooth, hoparlör, kulaklık). */
    override fun onCallAudioStateChanged(state: CallAudioState) {
        Log.d(TAG, "onCallAudioStateChanged route=${state.route} muted=${state.isMuted}")
        bridge.onAudioStateChanged(callId, state)
    }

    /** Mute toggle */
    override fun onMuteStateChanged(state: Boolean) {
        bridge.onMuteToggled(callId, state)
    }

    /**
     * Sistem connection'ı abort etti — örneğin gelen SIM araması sırasında SecureChat
     * aramasının önceliği yok. Sistem state cleanup'ı yaparken CallManager'a da hangup
     * yansıt; aksi halde WebRTC PeerConnection açık kalır ve kaynak sızıntısı yaratır.
     */
    override fun onAbort() {
        Log.d(TAG, "onAbort call=$callId")
        bridge.onUserHangup(callId)
        setDisconnected(DisconnectCause(DisconnectCause.OTHER))
        destroy()
    }

    /** Connection oluştu, sistem state'i belirlemeli. */
    fun startRinging() {
        Log.d(TAG, "startRinging call=$callId")
        setRinging()
    }

    fun startDialing() {
        Log.d(TAG, "startDialing call=$callId")
        setDialing()
    }

    fun connectionActive() {
        Log.d(TAG, "setActive call=$callId")
        setActive()
    }

    fun connectionEnded(cause: DisconnectCause) {
        Log.d(TAG, "setDisconnected call=$callId cause=$cause")
        setDisconnected(cause)
        destroy()
    }

    companion object {
        private const val TAG = "SCConnection"
    }
}
