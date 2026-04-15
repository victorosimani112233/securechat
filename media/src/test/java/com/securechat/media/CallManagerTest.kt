package com.securechat.media

import android.content.Context
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallState
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import io.mockk.verifyOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * CallManager sinifinin unit testleri.
 *
 * Arama yasam dongusu durum gecisleri, medya kontrolleri ve
 * signaling entegrasyonu test edilir.
 *
 * WebRTC PeerConnection yerine AudioStreamer kullanildigi icin
 * testler guncellenmistir.
 */
class CallManagerTest {

    private lateinit var callManager: CallManager
    private lateinit var signalingClient: SignalingClient
    private lateinit var audioManager: CallAudioManager
    private lateinit var audioStreamer: AudioStreamer
    private lateinit var videoStreamer: VideoStreamer
    private lateinit var ringtonePlayer: RingtonePlayer
    private lateinit var incomingCallHandler: IncomingCallHandler
    private lateinit var context: Context

    private val testUserId = "user-123"
    private val testPeerId = "peer-456"

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        audioManager = mockk(relaxed = true)
        audioStreamer = mockk(relaxed = true)
        videoStreamer = mockk(relaxed = true)
        ringtonePlayer = mockk(relaxed = true)
        incomingCallHandler = mockk(relaxed = true)

        callManager = CallManager(
            context = context,
            signalingClient = signalingClient,
            audioManager = audioManager,
            audioStreamer = audioStreamer,
            videoStreamer = videoStreamer,
            ringtonePlayer = ringtonePlayer,
            incomingCallHandler = incomingCallHandler
        )
    }

    // ---- Giden arama testleri ----

    @Test
    fun `initiateCall creates session with RINGING state`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        val session = callManager.currentSession
        assertNotNull(session)
        assertEquals(testPeerId, session?.peerId)
        assertEquals(CallType.VOICE, session?.callType)
        assertEquals(CallDirection.OUTGOING, session?.direction)
        assertEquals(CallState.RINGING, session?.state)
        assertNull(session?.startTime)
    }

    @Test
    fun `initiateCall sends SdpOffer signal with audio-call sdp`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        verify {
            signalingClient.sendSignal(match { s ->
                s is SignalMessage.SdpOffer &&
                    s.senderId == testUserId &&
                    s.recipientId == testPeerId &&
                    s.sdp == "audio-call" &&
                    s.callType == CallType.VOICE
            })
        }
    }

    @Test
    fun `initiateCall for VIDEO sets callType to VIDEO`() {
        callManager.initiateCall(testPeerId, CallType.VIDEO, testUserId)

        assertEquals(CallType.VIDEO, callManager.currentSession?.callType)
    }

    @Test
    fun `initiateCall sets OUTGOING direction`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        assertEquals(CallDirection.OUTGOING, callManager.currentSession?.direction)
    }

    // ---- Gelen arama testleri ----

    @Test
    fun `handleIncomingCall creates session with correct direction`() {
        val signal = createIncomingSdpOffer()

        callManager.handleIncomingCall(signal, testUserId)

        assertEquals(CallDirection.INCOMING, callManager.currentSession?.direction)
        assertEquals(CallState.RINGING, callManager.currentSession?.state)
        assertEquals(testPeerId, callManager.currentSession?.peerId)
        assertEquals(CallType.VOICE, callManager.currentSession?.callType)
    }

    @Test
    fun `handleIncomingCall does not start AudioStreamer`() {
        val signal = createIncomingSdpOffer()

        callManager.handleIncomingCall(signal, testUserId)

        verify(exactly = 0) { audioStreamer.start(any(), any()) }
    }

    // ---- Arama kabul testleri ----

    @Test
    fun `acceptCall sends ACCEPT signal and starts AudioStreamer`() {
        setupIncomingCall()

        callManager.acceptCall(testUserId)

        verify {
            signalingClient.sendSignal(match { s ->
                s is SignalMessage.CallControl &&
                    s.action == CallAction.ACCEPT &&
                    s.senderId == testUserId &&
                    s.recipientId == testPeerId
            })
        }
        verify { audioStreamer.start(testUserId, testPeerId) }
        verify { audioManager.setCallMode() }
        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)
        assertNotNull(callManager.currentSession?.startTime)
    }

    @Test
    fun `acceptCall does not change state for OUTGOING calls`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        callManager.acceptCall(testUserId)

        // OUTGOING arama icin acceptCall calismamali, state RINGING kalmali
        assertEquals(CallState.RINGING, callManager.currentSession?.state)
        verify(exactly = 0) { audioStreamer.start(any(), any()) }
    }

    @Test
    fun `acceptCall does nothing when no session exists`() {
        callManager.acceptCall(testUserId)

        assertNull(callManager.currentSession)
    }

    // ---- Arama sonlandirma testleri ----

    @Test
    fun `endCall sends HANGUP signal`() {
        setupIncomingCall()

        callManager.endCall(testUserId)

        verify {
            signalingClient.sendSignal(match { s ->
                s is SignalMessage.CallControl &&
                    s.action == CallAction.HANGUP &&
                    s.senderId == testUserId &&
                    s.recipientId == testPeerId
            })
        }
    }

    @Test
    fun `endCall stops AudioStreamer`() {
        setupIncomingCall()

        callManager.endCall(testUserId)

        verify { audioStreamer.stop() }
    }

    @Test
    fun `endCall resets audio mode`() {
        setupIncomingCall()

        callManager.endCall(testUserId)

        verify { audioManager.resetAudioMode() }
    }

    @Test
    fun `endCall transitions to ENDED`() {
        setupIncomingCall()

        callManager.endCall(testUserId)

        assertEquals(CallState.ENDED, callManager.currentSession?.state)
    }

    @Test
    fun `endCall does nothing when no session exists`() {
        callManager.endCall(testUserId)

        assertNull(callManager.currentSession)
    }

    // ---- Arama reddi testleri ----

    @Test
    fun `rejectCall transitions to REJECTED`() {
        setupIncomingCall()

        callManager.rejectCall(testUserId)

        assertEquals(CallState.REJECTED, callManager.currentSession?.state)
    }

    @Test
    fun `rejectCall sends REJECT signal`() {
        setupIncomingCall()

        callManager.rejectCall(testUserId)

        verify {
            signalingClient.sendSignal(match { s ->
                s is SignalMessage.CallControl &&
                    s.action == CallAction.REJECT
            })
        }
    }

    @Test
    fun `rejectCall stops AudioStreamer`() {
        setupIncomingCall()

        callManager.rejectCall(testUserId)

        verify { audioStreamer.stop() }
    }

    // ---- Callback testleri ----

    @Test
    fun `onCallConnected sets ACTIVE with startTime and starts AudioStreamer`() {
        // Arayan taraf: initiateCall -> RINGING, sonra ACCEPT alindi -> onCallConnected
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        callManager.onCallConnected()

        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)
        assertNotNull(callManager.currentSession?.startTime)
        verify { audioStreamer.start(testUserId, testPeerId) }
        verify { audioManager.setCallMode() }
    }

    @Test
    fun `onCallFailed sets FAILED and cleans up`() {
        setupIncomingCall()

        callManager.onCallFailed()

        assertEquals(CallState.FAILED, callManager.currentSession?.state)
        verify { audioStreamer.stop() }
        verify { audioManager.resetAudioMode() }
    }

    @Test
    fun `onRemoteHangup cleans up and sets ENDED`() {
        setupIncomingCall()

        callManager.onRemoteHangup()

        assertEquals(CallState.ENDED, callManager.currentSession?.state)
        verify { audioStreamer.stop() }
    }

    @Test
    fun `onRemoteReject sets REJECTED`() {
        setupIncomingCall()

        callManager.onRemoteReject()

        assertEquals(CallState.REJECTED, callManager.currentSession?.state)
    }

    @Test
    fun `onRemoteBusy sets BUSY`() {
        setupIncomingCall()

        callManager.onRemoteBusy()

        assertEquals(CallState.BUSY, callManager.currentSession?.state)
    }

    // ---- Medya kontrol testleri ----

    @Test
    fun `toggleMute flips muted state`() {
        setupIncomingCall()
        assertFalse(callManager.currentSession!!.isMuted)

        callManager.toggleMute()
        assertTrue(callManager.currentSession!!.isMuted)

        callManager.toggleMute()
        assertFalse(callManager.currentSession!!.isMuted)
    }

    @Test
    fun `toggleMute calls setMuted on AudioStreamer`() {
        setupIncomingCall()

        callManager.toggleMute()
        verify { audioStreamer.setMuted(true) }

        callManager.toggleMute()
        verify { audioStreamer.setMuted(false) }
    }

    @Test
    fun `toggleMute does nothing when no session`() {
        callManager.toggleMute()
        assertNull(callManager.currentSession)
    }

    @Test
    fun `toggleSpeaker flips speaker and calls audioManager`() {
        setupIncomingCall()
        assertFalse(callManager.currentSession!!.isSpeakerOn)

        callManager.toggleSpeaker()
        assertTrue(callManager.currentSession!!.isSpeakerOn)
        verify { audioManager.setSpeakerOn(true) }

        callManager.toggleSpeaker()
        assertFalse(callManager.currentSession!!.isSpeakerOn)
        verify { audioManager.setSpeakerOn(false) }
    }

    @Test
    fun `toggleCamera flips camera state`() {
        setupIncomingCall()
        assertTrue(callManager.currentSession!!.isCameraEnabled)

        callManager.toggleCamera()
        assertFalse(callManager.currentSession!!.isCameraEnabled)

        callManager.toggleCamera()
        assertTrue(callManager.currentSession!!.isCameraEnabled)
    }

    @Test
    fun `switchCamera flips front and back`() {
        setupIncomingCall()
        assertTrue(callManager.currentSession!!.isUsingFrontCamera)

        callManager.switchCamera()
        assertFalse(callManager.currentSession!!.isUsingFrontCamera)

        callManager.switchCamera()
        assertTrue(callManager.currentSession!!.isUsingFrontCamera)
    }

    // ---- Arama suresi testleri ----

    @Test
    fun `getCallDuration returns null when no active call`() {
        assertNull(callManager.getCallDuration())
    }

    @Test
    fun `getCallDuration returns null when call has no startTime`() {
        setupIncomingCall()
        assertNull(callManager.getCallDuration())
    }

    @Test
    fun `getCallDuration returns positive value after connected`() {
        setupIncomingCall()
        callManager.onCallConnected()

        val duration = callManager.getCallDuration()
        assertNotNull(duration)
        assertTrue(duration!! >= 0)
    }

    @Test
    fun `endCall records duration for active calls`() {
        setupIncomingCall()
        callManager.onCallConnected()

        callManager.endCall(testUserId)

        assertNotNull(callManager.currentSession?.duration)
        assertTrue(callManager.currentSession?.duration!! >= 0)
    }

    // ---- StateFlow testleri ----

    @Test
    fun `callSession StateFlow initially null`() {
        assertNull(callManager.callSession.value)
    }

    @Test
    fun `callSession StateFlow updates on handleIncomingCall`() {
        val signal = createIncomingSdpOffer()

        callManager.handleIncomingCall(signal, testUserId)

        val session = callManager.callSession.value
        assertNotNull(session)
        assertEquals(testPeerId, session?.peerId)
    }

    // ---- Tam yasam dongusu testleri ----

    @Test
    fun `full incoming call lifecycle RINGING to ACTIVE to ENDED`() {
        // 1. Gelen arama
        setupIncomingCall()
        assertEquals(CallState.RINGING, callManager.currentSession?.state)
        assertEquals(CallDirection.INCOMING, callManager.currentSession?.direction)

        // 2. Arama baglandi
        callManager.onCallConnected()
        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)
        assertNotNull(callManager.currentSession?.startTime)

        // 3. Arama sonlandirildi
        callManager.endCall(testUserId)
        assertEquals(CallState.ENDED, callManager.currentSession?.state)
        assertNotNull(callManager.currentSession?.duration)
    }

    @Test
    fun `full outgoing call lifecycle RINGING to ACTIVE to ENDED`() {
        // 1. Giden arama baslatildi
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)
        assertEquals(CallState.RINGING, callManager.currentSession?.state)
        assertEquals(CallDirection.OUTGOING, callManager.currentSession?.direction)

        // 2. Karsi taraf kabul etti -> onCallConnected
        callManager.onCallConnected()
        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)
        verify { audioStreamer.start(testUserId, testPeerId) }

        // 3. Arama sonlandirildi
        callManager.endCall(testUserId)
        assertEquals(CallState.ENDED, callManager.currentSession?.state)
        verify { audioStreamer.stop() }
    }

    @Test
    fun `incoming call accepted lifecycle`() {
        // 1. Gelen arama
        setupIncomingCall()
        assertEquals(CallState.RINGING, callManager.currentSession?.state)

        // 2. Kullanici kabul etti
        callManager.acceptCall(testUserId)
        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)
        verify { audioStreamer.start(testUserId, testPeerId) }

        // 3. Arama sonlandirildi
        callManager.endCall(testUserId)
        assertEquals(CallState.ENDED, callManager.currentSession?.state)
    }

    @Test
    fun `incoming call rejected lifecycle`() {
        setupIncomingCall()
        assertEquals(CallState.RINGING, callManager.currentSession?.state)

        callManager.rejectCall(testUserId)
        assertEquals(CallState.REJECTED, callManager.currentSession?.state)
    }

    @Test
    fun `incoming call remote hangup lifecycle`() {
        setupIncomingCall()
        callManager.onCallConnected()
        assertEquals(CallState.ACTIVE, callManager.currentSession?.state)

        callManager.onRemoteHangup()
        assertEquals(CallState.ENDED, callManager.currentSession?.state)
    }

    // ---- Zil sesi ve titresim testleri ----

    @Test
    fun `handleIncomingCall starts ringing`() {
        val signal = createIncomingSdpOffer()

        callManager.handleIncomingCall(signal, testUserId)

        verify { ringtonePlayer.startRinging() }
    }

    @Test
    fun `acceptCall stops ringing before starting audio`() {
        setupIncomingCall()

        callManager.acceptCall(testUserId)

        verifyOrder {
            ringtonePlayer.stopRinging()
            audioManager.setCallMode()
            audioStreamer.start(testUserId, testPeerId)
        }
    }

    @Test
    fun `acceptCall plays connected tone after starting audio`() {
        setupIncomingCall()

        callManager.acceptCall(testUserId)

        verify { ringtonePlayer.playConnectedTone() }
    }

    @Test
    fun `rejectCall stops ringing`() {
        setupIncomingCall()

        callManager.rejectCall(testUserId)

        verify { ringtonePlayer.stopRinging() }
    }

    @Test
    fun `onRemoteHangup stops ringing`() {
        setupIncomingCall()

        callManager.onRemoteHangup()

        verify { ringtonePlayer.stopRinging() }
    }

    @Test
    fun `cleanupCall stops ringing as safety net`() {
        setupIncomingCall()

        callManager.endCall(testUserId)

        // cleanupCall icinde stopRinging cagirilir
        verify { ringtonePlayer.stopRinging() }
    }

    @Test
    fun `onCallConnected plays connected tone`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        callManager.onCallConnected()

        verify { ringtonePlayer.playConnectedTone() }
    }

    @Test
    fun `initiateCall does not start ringing for outgoing calls`() {
        callManager.initiateCall(testPeerId, CallType.VOICE, testUserId)

        verify(exactly = 0) { ringtonePlayer.startRinging() }
    }

    @Test
    fun `onCallFailed stops ringing via cleanupCall`() {
        setupIncomingCall()

        callManager.onCallFailed()

        verify { ringtonePlayer.stopRinging() }
    }

    // ---- Yardimci metodlar ----

    /**
     * Test icin gelen arama senaryosu olusturur.
     * handleIncomingCall cagrilarak RINGING durumunda bir session olusturur.
     */
    private fun setupIncomingCall() {
        val signal = createIncomingSdpOffer()
        callManager.handleIncomingCall(signal, testUserId)
    }

    /**
     * Test icin mock SDP Offer sinyali olusturur.
     */
    private fun createIncomingSdpOffer(): SignalMessage.SdpOffer {
        return SignalMessage.SdpOffer(
            senderId = testPeerId,
            recipientId = testUserId,
            timestamp = System.currentTimeMillis(),
            sdp = "audio-call",
            callType = CallType.VOICE
        )
    }
}
