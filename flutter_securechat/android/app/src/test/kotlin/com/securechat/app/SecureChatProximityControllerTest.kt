package com.securechat.app

import org.junit.Assert.assertEquals
import org.junit.Test

class SecureChatProximityControllerTest {
    @Test
    fun onlyActiveVoiceOnEarpieceEnablesProximity() {
        for (supported in listOf(false, true)) {
            for (voice in listOf(false, true)) {
                for (active in listOf(false, true)) {
                    for (earpiece in listOf(false, true)) {
                        var acquired = 0
                        var released = 0
                        val controller = SecureChatProximityController(supported, { acquired++ }, { released++ })
                        controller.update(voice, active, earpiece)
                        controller.update(voice, active, earpiece)
                        val expected = if (supported && voice && active && earpiece) 1 else 0
                        assertEquals(expected, acquired)
                        controller.close()
                        controller.close()
                        assertEquals(expected, released)
                    }
                }
            }
        }
    }

    @Test
    fun routeChangesAndHangupReleaseImmediately() {
        val transitions = mutableListOf<Boolean>()
        val controller = SecureChatProximityController(true, { transitions.add(true) }, { transitions.add(false) })
        controller.update(true, true, true)
        controller.update(true, true, false)
        controller.update(true, true, true)
        controller.update(true, false, true)
        assertEquals(listOf(true, false, true, false), transitions)
    }
}
