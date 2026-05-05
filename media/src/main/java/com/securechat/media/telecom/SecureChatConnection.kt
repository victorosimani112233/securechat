package com.securechat.media.telecom

import android.net.Uri
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.StatusHints
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log

/**
 * Telecom Framework Connection — SELF_MANAGED VoIP araması icin.
 *
 * Bu sinif sistemin (`TelecomManager`) bizim arama oturumumuzla
 * iletisim kurdugu yuzeyidir. Sistem callbackleri (onAnswer, onReject,
 * onDisconnect, onCallAudioStateChanged, vs.) buraya gelir; bizim
 * arama yasam dongumuzdeki degisikliklerin (setRinging/setActive/
 * setDisconnected) buradan disariya yansitilmasi gerekir.
 *
 * **Asama A:** Sadece iskelet. Sistem callbackleri loglanir; CallManager'a
 * dogrudan delegasyon Asama B (outgoing) ve C (incoming) eklendiginde
 * yapilacak.
 *
 * **Properties:**
 * - `PROPERTY_SELF_MANAGED` — Telecom UI gostermez; bizim CallScreen aktif kalir
 * - `audioModeIsVoip = true` — sistem AudioManager'i MODE_IN_COMMUNICATION'a alir
 * - `CAPABILITY_MUTE` + `CAPABILITY_HOLD` + `CAPABILITY_SUPPORT_HOLD`
 *
 * @param callId CallManager tarafindan uretilen benzersiz oturum kimligi
 * @param peerName Karsi tarafin gorunen adi (StatusHints icin)
 * @param isVideo true ise video aramasi
 * @param isIncoming true ise gelen arama (setRinging ile baslar), aksi halde
 *                  giden (setDialing ile baslar)
 */
internal class SecureChatConnection(
    val callId: String,
    val peerId: String,
    val peerName: String,
    val isVideo: Boolean,
    val isIncoming: Boolean
) : Connection() {

    /**
     * Connection action callback'leri icin opsiyonel listener.
     * Asama B/C'de TelecomBridge bunu set edip CallManager'a yonlendirecek.
     */
    var listener: Listener? = null

    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD
        audioModeIsVoip = true
        videoState = if (isVideo) VideoProfile.STATE_BIDIRECTIONAL else VideoProfile.STATE_AUDIO_ONLY

        // Sistem call UI'i icin caller bilgisi:
        // 1) DisplayName — peerName cozulmusse onu kullan; bos/sender-id formatinda
        //    ise "SecureChat" goster (sistemin kendi "Bilinmeyen" fallback'i yerine).
        val safeDisplayName = if (peerName.isNotBlank() && !looksLikeUuid(peerName)) {
            peerName
        } else {
            "SecureChat"
        }
        setCallerDisplayName(safeDisplayName, TelecomManager.PRESENTATION_ALLOWED)

        // 2) Address — sistem display name yedegi olarak kullanir. SIP scheme +
        //    peerId. Bazi cihazlarda call UI bu alani da gosterir.
        if (peerId.isNotBlank()) {
            setAddress(
                Uri.fromParts(PhoneAccount.SCHEME_SIP, peerId, null),
                TelecomManager.PRESENTATION_ALLOWED
            )
        }

        setStatusHints(StatusHints("SecureChat", null, null))
    }

    /** UUID benzeri (8-4-4-4-12 veya 36 char) string mi? */
    private fun looksLikeUuid(s: String): Boolean {
        if (s.length != 36) return false
        return s[8] == '-' && s[13] == '-' && s[18] == '-' && s[23] == '-'
    }

    // -------- Sistemden gelen callback'ler --------

    override fun onShowIncomingCallUi() {
        Log.d(TAG, "onShowIncomingCallUi: callId=$callId")
        listener?.onShowIncomingCallUi(this)
    }

    override fun onAnswer() {
        Log.d(TAG, "onAnswer: callId=$callId")
        listener?.onAnswer(this, VideoProfile.STATE_AUDIO_ONLY)
    }

    override fun onAnswer(videoState: Int) {
        Log.d(TAG, "onAnswer(videoState=$videoState): callId=$callId")
        listener?.onAnswer(this, videoState)
    }

    override fun onReject() {
        Log.d(TAG, "onReject: callId=$callId")
        listener?.onReject(this)
    }

    override fun onReject(replyMessage: String?) {
        Log.d(TAG, "onReject(reply=$replyMessage): callId=$callId")
        listener?.onReject(this)
    }

    override fun onDisconnect() {
        Log.d(TAG, "onDisconnect: callId=$callId")
        listener?.onDisconnect(this)
    }

    override fun onAbort() {
        Log.d(TAG, "onAbort: callId=$callId")
        listener?.onAbort(this)
    }

    override fun onHold() {
        Log.d(TAG, "onHold: callId=$callId")
        setOnHold()
        listener?.onHold(this)
    }

    override fun onUnhold() {
        Log.d(TAG, "onUnhold: callId=$callId")
        setActive()
        listener?.onUnhold(this)
    }

    override fun onCallAudioStateChanged(state: CallAudioState) {
        Log.d(TAG, "onCallAudioStateChanged: route=${state.route} muted=${state.isMuted}")
        listener?.onCallAudioStateChanged(this, state)
    }

    // -------- Yardimcilar (Bridge tarafindan cagirilir) --------

    /**
     * Aramayi normal sekilde sonlandirir ve kaynaklari serbest birakir.
     * Connection.destroy() cagrilmadan surec tamamlanmaz.
     */
    fun closeWith(cause: DisconnectCause) {
        try {
            setDisconnected(cause)
        } finally {
            destroy()
            listener = null
        }
    }

    interface Listener {
        fun onShowIncomingCallUi(connection: SecureChatConnection) {}
        fun onAnswer(connection: SecureChatConnection, videoState: Int) {}
        fun onReject(connection: SecureChatConnection) {}
        fun onDisconnect(connection: SecureChatConnection) {}
        fun onAbort(connection: SecureChatConnection) {}
        fun onHold(connection: SecureChatConnection) {}
        fun onUnhold(connection: SecureChatConnection) {}
        fun onCallAudioStateChanged(connection: SecureChatConnection, state: CallAudioState) {}
    }

    companion object {
        private const val TAG = "SecureChatConnection"
    }
}
