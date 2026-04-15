package com.securechat.media

import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * CallState, CallDirection ve CallSession model siniflarinin unit testleri.
 */
class CallStateTest {

    // ---- CallState enum testleri ----

    @Test
    fun `CallState has all expected values`() {
        val expected = listOf(
            "IDLE", "INITIATING", "RINGING", "CONNECTING",
            "ACTIVE", "RECONNECTING", "ENDED", "REJECTED",
            "BUSY", "FAILED"
        )
        val actual = CallState.entries.map { it.name }

        assertEquals(expected.sorted(), actual.sorted())
    }

    @Test
    fun `CallState has exactly 10 values`() {
        assertEquals(10, CallState.entries.size)
    }

    @Test
    fun `CallState valueOf returns correct value`() {
        assertEquals(CallState.IDLE, CallState.valueOf("IDLE"))
        assertEquals(CallState.ACTIVE, CallState.valueOf("ACTIVE"))
        assertEquals(CallState.ENDED, CallState.valueOf("ENDED"))
    }

    // ---- CallDirection enum testleri ----

    @Test
    fun `CallDirection has INCOMING and OUTGOING`() {
        val values = CallDirection.entries
        assertEquals(2, values.size)
        assertTrue(values.contains(CallDirection.INCOMING))
        assertTrue(values.contains(CallDirection.OUTGOING))
    }

    // ---- CallSession testleri ----

    @Test
    fun `CallSession defaults are correct`() {
        val session = CallSession(
            callId = "test-id",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.IDLE
        )

        assertNull(session.startTime)
        assertNull(session.duration)
        assertFalse(session.isMuted)
        assertFalse(session.isSpeakerOn)
        assertTrue(session.isCameraEnabled)
        assertTrue(session.isUsingFrontCamera)
    }

    @Test
    fun `CallSession copy with state change preserves other fields`() {
        val original = CallSession(
            callId = "call-123",
            peerId = "peer-456",
            callType = CallType.VIDEO,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            isMuted = true,
            isSpeakerOn = true
        )

        val updated = original.copy(state = CallState.CONNECTING)

        assertEquals(CallState.CONNECTING, updated.state)
        assertEquals(original.callId, updated.callId)
        assertEquals(original.peerId, updated.peerId)
        assertEquals(original.callType, updated.callType)
        assertEquals(original.direction, updated.direction)
        assertTrue(updated.isMuted)
        assertTrue(updated.isSpeakerOn)
    }

    @Test
    fun `CallSession copy with startTime sets value`() {
        val session = CallSession(
            callId = "test-id",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.ACTIVE
        )

        val startTime = System.currentTimeMillis()
        val updated = session.copy(startTime = startTime)

        assertEquals(startTime, updated.startTime)
        assertNull(session.startTime) // Orijinal degismemeli
    }

    @Test
    fun `CallSession copy with duration sets value`() {
        val session = CallSession(
            callId = "test-id",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.ENDED,
            startTime = 1000L
        )

        val updated = session.copy(duration = 5000L)

        assertEquals(5000L, updated.duration)
    }

    @Test
    fun `CallSession equality works correctly`() {
        val session1 = CallSession(
            callId = "same-id",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.IDLE
        )
        val session2 = session1.copy()

        assertEquals(session1, session2)
    }

    @Test
    fun `CallSession inequality with different state`() {
        val session1 = CallSession(
            callId = "same-id",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.IDLE
        )
        val session2 = session1.copy(state = CallState.ACTIVE)

        assertNotEquals(session1, session2)
    }

    @Test
    fun `CallSession with all custom values`() {
        val session = CallSession(
            callId = "custom-call",
            peerId = "custom-peer",
            callType = CallType.VIDEO,
            direction = CallDirection.INCOMING,
            state = CallState.ACTIVE,
            startTime = 100L,
            duration = 200L,
            isMuted = true,
            isSpeakerOn = true,
            isCameraEnabled = false,
            isUsingFrontCamera = false
        )

        assertEquals("custom-call", session.callId)
        assertEquals("custom-peer", session.peerId)
        assertEquals(CallType.VIDEO, session.callType)
        assertEquals(CallDirection.INCOMING, session.direction)
        assertEquals(CallState.ACTIVE, session.state)
        assertEquals(100L, session.startTime)
        assertEquals(200L, session.duration)
        assertTrue(session.isMuted)
        assertTrue(session.isSpeakerOn)
        assertFalse(session.isCameraEnabled)
        assertFalse(session.isUsingFrontCamera)
    }

    @Test
    fun `CallSession VOICE type default camera enabled`() {
        val session = CallSession(
            callId = "voice-call",
            peerId = "peer-1",
            callType = CallType.VOICE,
            direction = CallDirection.OUTGOING,
            state = CallState.ACTIVE
        )

        // Varsayilan olarak kamera acik (UI katmaninda gizlenecek)
        assertTrue(session.isCameraEnabled)
    }
}
