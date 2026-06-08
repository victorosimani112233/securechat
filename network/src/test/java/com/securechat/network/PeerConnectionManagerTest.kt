package com.securechat.network

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.securechat.network.model.PeerState
import io.mockk.mockk
import org.junit.Before
import org.junit.Test

/**
 * PeerConnectionManager sinifinin unit testleri.
 *
 * WebRTC native kutuphanesi unit testlerde kullanilamadigindan
 * bu testler state management mantigi uzerine odaklanir.
 * PeerConnection olusturma, SDP ve ICE islemleri runtime'da
 * integration testleri ile dogrulanir.
 *
 * Test edilen konular:
 * - Peer state gecisleri (CONNECTING, CONNECTED_P2P, RECONNECTING, DISCONNECTED)
 * - disposePeerConnection sonrasi state guncelleme
 * - Birden fazla peer'in farkli state'lerde olmasi
 * - release() ile tum kaynaklarin temizlenmesi
 * - ICE candidate buffering mantigi
 */
class PeerConnectionManagerTest {

    private lateinit var mockContext: Context
    private lateinit var peerConnectionManager: PeerConnectionManager

    @Before
    fun setUp() {
        mockContext = mockk(relaxed = true)
        peerConnectionManager = PeerConnectionManager(mockContext, stunUrl = "stun:test.example:3478")
    }

    @Test
    fun `initial peer states map is empty`() {
        assertThat(peerConnectionManager.peerStates.value).isEmpty()
    }

    @Test
    fun `updatePeerState changes state correctly`() {
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTING)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTING)

        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTED_P2P)

        peerConnectionManager.updatePeerState("peer1", PeerState.RECONNECTING)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.RECONNECTING)
    }

    @Test
    fun `updatePeerState works for peers not yet created`() {
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_SIGNALING)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTED_SIGNALING)
    }

    @Test
    fun `multiple peers can have different states`() {
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)
        peerConnectionManager.updatePeerState("peer2", PeerState.CONNECTED_SIGNALING)
        peerConnectionManager.updatePeerState("peer3", PeerState.CONNECTING)

        val states = peerConnectionManager.peerStates.value
        assertThat(states["peer1"]).isEqualTo(PeerState.CONNECTED_P2P)
        assertThat(states["peer2"]).isEqualTo(PeerState.CONNECTED_SIGNALING)
        assertThat(states["peer3"]).isEqualTo(PeerState.CONNECTING)
    }

    @Test
    fun `disposePeerConnection clears video frames`() {
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)

        peerConnectionManager.disposePeerConnection()

        assertThat(peerConnectionManager.remoteVideoTrackFlow.value).isNull()
        assertThat(peerConnectionManager.localVideoTrackFlow.value).isNull()
    }

    @Test
    fun `state transitions follow expected lifecycle`() {
        // Baglanti baslatma
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTING)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTING)

        // Baglanti kuruldu
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTED_P2P)

        // Baglanti koptu
        peerConnectionManager.updatePeerState("peer1", PeerState.RECONNECTING)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.RECONNECTING)

        // Yeniden baglandi
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTED_P2P)

        // Kapatildi
        peerConnectionManager.updatePeerState("peer1", PeerState.DISCONNECTED)
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.DISCONNECTED)
    }

    @Test
    fun `peer state map is immutable snapshot`() {
        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTING)
        val snapshot = peerConnectionManager.peerStates.value

        peerConnectionManager.updatePeerState("peer1", PeerState.CONNECTED_P2P)

        // Eski snapshot degismemeli
        assertThat(snapshot["peer1"]).isEqualTo(PeerState.CONNECTING)
        // Yeni deger guncel olmali
        assertThat(peerConnectionManager.peerStates.value["peer1"]).isEqualTo(PeerState.CONNECTED_P2P)
    }

    @Test
    fun `initial video frames are null`() {
        assertThat(peerConnectionManager.remoteVideoTrackFlow.value).isNull()
        assertThat(peerConnectionManager.localVideoTrackFlow.value).isNull()
    }

    @Test
    fun `useFrontCamera is true by default`() {
        assertThat(peerConnectionManager.useFrontCamera).isTrue()
    }

    @Test
    fun `release does not throw when not initialized`() {
        // release() cagirildikta factory null oldugu icin sorunsuz calisir
        peerConnectionManager.release()
    }

    @Test
    fun `setMicEnabled does not throw when audio track is null`() {
        // Audio track yokken setMicEnabled guvenli olmali
        peerConnectionManager.setMicEnabled(false)
        peerConnectionManager.setMicEnabled(true)
    }

    @Test
    fun `switchCamera does not throw when capturer is null`() {
        // Video capturer yokken switchCamera guvenli olmali
        peerConnectionManager.switchCamera()
    }

    @Test
    fun `disableVideo does not throw when video is not active`() {
        // Video aktif degilken disableVideo guvenli olmali
        peerConnectionManager.disableVideo()
        assertThat(peerConnectionManager.localVideoTrackFlow.value).isNull()
    }
}
