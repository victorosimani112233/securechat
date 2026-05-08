package com.securechat.telecom

import android.telecom.CallAudioState

/**
 * Telecom Framework ↔ CallManager köprü.
 *
 * [SecureChatConnection] sistem callback'lerinden tetiklenir; bu interface üzerinden
 * uygulama tarafındaki CallManager'a yönlendirilir.
 *
 * Implementasyon: [TelecomCallBridge] (CallManager'ı inject eder).
 */
interface ConnectionBridge {
    /** Kullanıcı sistem UI'inden "Kabul Et" bastı. */
    fun onUserAnswered(callId: String)

    /** Kullanıcı sistem UI'inden "Reddet" bastı. */
    fun onUserRejected(callId: String)

    /** Kullanıcı sistem UI'inden "Kapat" bastı (aktif arama). */
    fun onUserHangup(callId: String)

    /** Sistem audio routing değişti (Bluetooth/Speaker/Earpiece). */
    fun onAudioStateChanged(callId: String, state: CallAudioState)

    /** Mute toggle (sistem UI'inden). */
    fun onMuteToggled(callId: String, muted: Boolean)

    /** SecureChatConnectionService callback'i bir Connection oluşturduğunda. */
    fun onConnectionCreated(callId: String, connection: SecureChatConnection)
}
