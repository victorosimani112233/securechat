package com.securechat.app

import android.content.Context
import android.os.PowerManager

internal class SecureChatProximityController(
    private val supported: Boolean,
    private val acquire: () -> Unit,
    private val release: () -> Unit
) {
    private var enabled = false

    fun update(isVoiceCall: Boolean, isCallActive: Boolean, isEarpiece: Boolean) {
        val next = supported && isVoiceCall && isCallActive && isEarpiece
        if (next == enabled) return
        if (next) acquire() else release()
        enabled = next
    }

    fun close() = update(isVoiceCall = false, isCallActive = false, isEarpiece = false)

    companion object {
        fun create(context: Context): SecureChatProximityController {
            val power = context.getSystemService(PowerManager::class.java)
            val supported = power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)
            val lock = if (supported) power.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "securechat:call-proximity"
            ).apply { setReferenceCounted(false) } else null
            return SecureChatProximityController(
                supported,
                acquire = { lock?.acquire() },
                // Do not wait for the user to move the phone after ending a call.
                release = { if (lock?.isHeld == true) lock.release() }
            )
        }
    }
}
