package com.securechat.network

import android.content.Context
import android.util.Log
import com.securechat.network.model.PeerState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.webrtc.*
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

/**
 * WebRTC PeerConnection yasam dongusunu yoneten sinif.
 * Gercek P2P ses ve video akisi icin kullanilir.
 *
 * Video: Camera2Capturer → VideoTrack → PeerConnection → P2P
 * Ses: AudioSource → AudioTrack → PeerConnection → P2P
 * Remote medya: onAddTrack → SurfaceViewRenderer (dogrudan GPU render)
 * Ses: JavaAudioDeviceModule ile AEC/NS/AGC destekli ses yakalama ve cikis
 */
@Singleton
class PeerConnectionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "WebRTC"
        private const val VIDEO_WIDTH = 640
        private const val VIDEO_HEIGHT = 480
        private const val VIDEO_FPS = 24
    }

    private val _peerStates = MutableStateFlow<Map<String, PeerState>>(emptyMap())
    val peerStates: StateFlow<Map<String, PeerState>> = _peerStates.asStateFlow()

    // Video track'leri — SurfaceViewRenderer dogrudan bunlara baglanir
    private val _remoteVideoTrack = MutableStateFlow<VideoTrack?>(null)
    val remoteVideoTrackFlow: StateFlow<VideoTrack?> = _remoteVideoTrack.asStateFlow()

    private val _localVideoTrack = MutableStateFlow<VideoTrack?>(null)
    val localVideoTrackFlow: StateFlow<VideoTrack?> = _localVideoTrack.asStateFlow()

    /** EGL context — SurfaceViewRenderer.init() icin gerekli */
    val eglBaseContext: EglBase.Context? get() = eglBase?.eglBaseContext

    private var eglBase: EglBase? = null
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var currentPeerId: String? = null
    private var initialized = false

    // Audio
    private var localAudioSource: AudioSource? = null
    private var localAudioTrack: AudioTrack? = null
    private var remoteAudioTrack: AudioTrack? = null

    // Video
    private var localVideoSource: VideoSource? = null
    private var localVideoTrack: VideoTrack? = null
    private var videoCapturer: CameraVideoCapturer? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null
    var useFrontCamera = true
        private set

    // ICE candidate buffering - candidates may arrive before remote description is set
    private val pendingIceCandidates = ConcurrentLinkedQueue<IceCandidate>()
    @Volatile
    private var isRemoteDescriptionSet = false

    // Callback for ICE candidates to send to remote peer
    var onIceCandidateGenerated: ((IceCandidate) -> Unit)? = null

    // Callback for ICE connection state changes
    var onConnectionStateChanged: ((PeerConnection.IceConnectionState) -> Unit)? = null

    /** ICE sunucu listesi — STUN + TURN */
    private val iceServers = listOf(
        PeerConnection.IceServer.builder("stun:185.48.182.124:3478")
            .createIceServer(),
        PeerConnection.IceServer.builder("turn:185.48.182.124:3478")
            .setUsername("securechat")
            .setPassword("securechat123")
            .createIceServer()
    )

    fun initialize() {
        if (initialized) return
        eglBase = EglBase.create()

        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )

        val encoderFactory = DefaultVideoEncoderFactory(
            eglBase!!.eglBaseContext, true, true
        )
        val decoderFactory = DefaultVideoDecoderFactory(eglBase!!.eglBaseContext)

        // JavaAudioDeviceModule — AEC, NS, AGC destekli ses yakalama ve cikis
        val audioDeviceModule = JavaAudioDeviceModule.builder(context)
            .setUseHardwareAcousticEchoCanceler(true)
            .setUseHardwareNoiseSuppressor(true)
            .createAudioDeviceModule()

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(audioDeviceModule)
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .setOptions(PeerConnectionFactory.Options())
            .createPeerConnectionFactory()

        // audioDeviceModule artik factory tarafindan sahiplenildi
        audioDeviceModule.release()

        initialized = true
        Log.d(TAG, "PeerConnectionFactory baslatildi (JavaAudioDeviceModule + video destekli)")
    }

    /**
     * Yeni PeerConnection olusturur. Ses ve video trackleri eklenir.
     */
    fun createPeerConnection(peerId: String, enableVideo: Boolean): PeerConnection? {
        if (!initialized) initialize()
        val factory = peerConnectionFactory ?: return null

        // Onceki baglanti varsa temizle
        disposePeerConnection()

        currentPeerId = peerId
        isRemoteDescriptionSet = false
        pendingIceCandidates.clear()

        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            // P2P oncelikli, gerekirse TURN relay
            iceTransportsType = PeerConnection.IceTransportsType.ALL
        }

        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                Log.d(TAG, "onIceCandidate: ${candidate.sdpMid}")
                onIceCandidateGenerated?.invoke(candidate)
            }

            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "ICE baglanti durumu: $state")
                val peerState = when (state) {
                    PeerConnection.IceConnectionState.CONNECTED,
                    PeerConnection.IceConnectionState.COMPLETED -> PeerState.CONNECTED_P2P
                    PeerConnection.IceConnectionState.DISCONNECTED -> PeerState.RECONNECTING
                    PeerConnection.IceConnectionState.FAILED -> PeerState.DISCONNECTED
                    else -> PeerState.CONNECTING
                }
                updatePeerState(peerId, peerState)
                onConnectionStateChanged?.invoke(state)
            }

            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                Log.d(TAG, "onAddTrack: ${receiver.track()?.kind()}")
                val track = receiver.track()
                when (track) {
                    is VideoTrack -> {
                        track.setEnabled(true)
                        _remoteVideoTrack.value = track
                        Log.d(TAG, "Remote video track set edildi (SurfaceViewRenderer'a baglanacak)")
                    }
                    is AudioTrack -> {
                        track.setEnabled(true)
                        remoteAudioTrack = track
                        Log.d(TAG, "Remote audio track etkinlestirildi")
                    }
                }
            }

            override fun onSignalingChange(state: PeerConnection.SignalingState) {
                Log.d(TAG, "Signaling durumu: $state")
            }
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                Log.d(TAG, "ICE gathering: $state")
            }
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onDataChannel(channel: DataChannel) {}
            override fun onRenegotiationNeeded() {}
        }

        val pc = factory.createPeerConnection(config, observer) ?: return null

        // Audio track olustur ve ekle
        localAudioSource = factory.createAudioSource(MediaConstraints())
        localAudioTrack = factory.createAudioTrack("audio0", localAudioSource)
        localAudioTrack?.setEnabled(true)
        pc.addTrack(localAudioTrack, listOf("stream0"))

        // Video track olustur ve ekle
        if (enableVideo) {
            startLocalVideo(factory, pc)
        }

        peerConnection = pc
        Log.d(TAG, "PeerConnection olusturuldu: peerId=$peerId, video=$enableVideo")
        return pc
    }

    /**
     * Yerel kamera yakalama ve video track olusturur.
     */
    private fun startLocalVideo(factory: PeerConnectionFactory, pc: PeerConnection) {
        val enumerator = Camera2Enumerator(context)
        val cameraName = getCameraName(enumerator) ?: run {
            Log.e(TAG, "Kamera bulunamadi")
            return
        }

        videoCapturer = enumerator.createCapturer(cameraName, null)
        surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", eglBase!!.eglBaseContext)
        localVideoSource = factory.createVideoSource(videoCapturer!!.isScreencast)

        videoCapturer!!.initialize(surfaceTextureHelper, context, localVideoSource!!.capturerObserver)
        videoCapturer!!.startCapture(VIDEO_WIDTH, VIDEO_HEIGHT, VIDEO_FPS)

        localVideoTrack = factory.createVideoTrack("video0", localVideoSource)
        localVideoTrack?.setEnabled(true)
        _localVideoTrack.value = localVideoTrack
        pc.addTrack(localVideoTrack, listOf("stream0"))

        Log.d(TAG, "Yerel video baslatildi: ${VIDEO_WIDTH}x${VIDEO_HEIGHT} @ ${VIDEO_FPS}fps")
    }

    /**
     * Video yakalamayi yeniden baslatir.
     * Eger track hala mevcutsa (disable edilmis), sadece capture baslatip enable eder.
     * Track yoksa (ilk kez veya tam dispose sonrasi) sifirdan olusturur.
     */
    fun enableVideo() {
        // Track varsa sadece re-enable et
        val existingTrack = localVideoTrack
        if (existingTrack != null) {
            try {
                videoCapturer?.startCapture(VIDEO_WIDTH, VIDEO_HEIGHT, VIDEO_FPS)
            } catch (e: Exception) {
                Log.e(TAG, "Video capture yeniden baslatma hatasi: ${e.message}")
            }
            existingTrack.setEnabled(true)
            _localVideoTrack.value = existingTrack
            Log.d(TAG, "Video track yeniden etkinlestirildi")
            return
        }
        // Track yoksa sifirdan olustur
        val factory = peerConnectionFactory ?: return
        val pc = peerConnection ?: return
        startLocalVideo(factory, pc)
    }

    /**
     * Video yakalamayi durdurur.
     * Track ve kaynaklar dispose edilmez — sadece capture durdurulur ve track disable edilir.
     * Bu sayede enableVideo() cagrildiginda hizlica yeniden etkinlestirilebilir.
     */
    fun disableVideo() {
        localVideoTrack?.setEnabled(false)
        try { videoCapturer?.stopCapture() } catch (_: Exception) {}
        _localVideoTrack.value = null
        Log.d(TAG, "Video capture durduruldu, track disable edildi")
    }

    // ---- SDP Yonetimi ----

    suspend fun createOffer(): SessionDescription = suspendCoroutine { cont ->
        val pc = peerConnection
            ?: throw IllegalStateException("PeerConnection bulunamadi")

        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }

        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                // setLocalDescription TAMAMLANMADAN resume etme — aksi halde
                // local description commit edilmeden SDP gonderilir ve ICE baslatilmaz
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        Log.d(TAG, "SDP Offer olusturuldu ve local description set edildi (${sdp.description.length} byte)")
                        cont.resume(sdp)
                    }
                    override fun onSetFailure(error: String) {
                        Log.e(TAG, "setLocalDescription (offer) hatasi: $error")
                        cont.resumeWithException(RuntimeException("setLocalDescription failed: $error"))
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(e: String) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) {
                Log.e(TAG, "SDP Offer olusturulamadi: $error")
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    suspend fun createAnswer(): SessionDescription = suspendCoroutine { cont ->
        val pc = peerConnection
            ?: throw IllegalStateException("PeerConnection bulunamadi")

        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }

        pc.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                // setLocalDescription TAMAMLANMADAN resume etme
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        Log.d(TAG, "SDP Answer olusturuldu ve local description set edildi (${sdp.description.length} byte)")
                        cont.resume(sdp)
                    }
                    override fun onSetFailure(error: String) {
                        Log.e(TAG, "setLocalDescription (answer) hatasi: $error")
                        cont.resumeWithException(RuntimeException("setLocalDescription failed: $error"))
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(e: String) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) {
                Log.e(TAG, "SDP Answer olusturulamadi: $error")
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    suspend fun setRemoteDescription(sdp: SessionDescription) = suspendCoroutine<Unit> { cont ->
        val pc = peerConnection
        if (pc == null) {
            Log.e(TAG, "setRemoteDescription: PeerConnection bulunamadi")
            cont.resumeWithException(IllegalStateException("PeerConnection bulunamadi"))
            return@suspendCoroutine
        }
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                Log.d(TAG, "Remote description ayarlandi (${sdp.type})")
                isRemoteDescriptionSet = true
                // Bekleyen ICE adaylarini ekle
                drainPendingIceCandidates()
                cont.resume(Unit)
            }
            override fun onSetFailure(error: String) {
                Log.e(TAG, "Remote description ayarlanamadi: $error")
                cont.resumeWithException(RuntimeException("setRemoteDescription failed: $error"))
            }
            override fun onCreateSuccess(sdp: SessionDescription) {}
            override fun onCreateFailure(error: String) {}
        }, sdp)
    }

    fun addIceCandidate(candidate: IceCandidate) {
        if (isRemoteDescriptionSet) {
            peerConnection?.addIceCandidate(candidate)
        } else {
            // Remote description henuz set edilmediyse buffer'a al
            pendingIceCandidates.add(candidate)
            Log.d(TAG, "ICE candidate buffer'a eklendi (${pendingIceCandidates.size} bekliyor)")
        }
    }

    private fun drainPendingIceCandidates() {
        val pc = peerConnection ?: return
        var count = 0
        while (true) {
            val candidate = pendingIceCandidates.poll() ?: break
            pc.addIceCandidate(candidate)
            count++
        }
        if (count > 0) {
            Log.d(TAG, "$count bekleyen ICE candidate eklendi")
        }
    }

    // ---- Medya Kontrolleri ----

    fun setMicEnabled(enabled: Boolean) {
        localAudioTrack?.setEnabled(enabled)
    }

    fun switchCamera() {
        val capturer = videoCapturer ?: return
        useFrontCamera = !useFrontCamera
        capturer.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
            override fun onCameraSwitchDone(isFront: Boolean) {
                Log.d(TAG, "Kamera degistirildi: front=$isFront")
                useFrontCamera = isFront
            }
            override fun onCameraSwitchError(error: String) {
                Log.e(TAG, "Kamera degistirme hatasi: $error")
            }
        })
    }

    // ---- Temizlik ----

    fun disposePeerConnection() {
        try { videoCapturer?.stopCapture() } catch (_: Exception) {}
        videoCapturer?.dispose()
        videoCapturer = null
        surfaceTextureHelper?.dispose()
        surfaceTextureHelper = null

        localVideoTrack?.dispose()
        localVideoTrack = null
        localVideoSource?.dispose()
        localVideoSource = null
        localAudioTrack?.dispose()
        localAudioTrack = null
        localAudioSource?.dispose()
        localAudioSource = null

        peerConnection?.close()
        peerConnection = null
        currentPeerId = null

        isRemoteDescriptionSet = false
        pendingIceCandidates.clear()
        _remoteVideoTrack.value = null
        _localVideoTrack.value = null
        remoteAudioTrack = null

        Log.d(TAG, "PeerConnection ve kaynaklar temizlendi")
    }

    fun release() {
        disposePeerConnection()
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
        eglBase?.release()
        eglBase = null
        initialized = false
    }

    fun updatePeerState(peerId: String, state: PeerState) {
        _peerStates.value = _peerStates.value.toMutableMap().apply { put(peerId, state) }
    }

    private fun getCameraName(enumerator: Camera2Enumerator): String? {
        val names = enumerator.deviceNames
        val facing = if (useFrontCamera) "front" else "back"
        return names.firstOrNull { name ->
            if (useFrontCamera) enumerator.isFrontFacing(name)
            else enumerator.isBackFacing(name)
        } ?: names.firstOrNull()
    }

    private class SimpleSdpObserver : SdpObserver {
        override fun onCreateSuccess(sdp: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(error: String) {
            Log.e("WebRTC", "SDP create failure: $error")
        }
        override fun onSetFailure(error: String) {
            Log.e("WebRTC", "SDP set failure: $error")
        }
    }
}
