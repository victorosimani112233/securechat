package com.securechat.network

import android.content.Context
import android.util.Log
import com.securechat.network.model.PeerState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import org.webrtc.*
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject
import javax.inject.Named
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
    @ApplicationContext private val context: Context,
    @Named("stunUrl") private val stunUrl: String
) {
    companion object {
        private const val TAG = "WebRTC"
        private const val VIDEO_WIDTH = 640
        private const val VIDEO_HEIGHT = 480
        private const val VIDEO_FPS = 24
        // Bandwidth cap'leri — agresif bir kullanici toplam server bandwidth'ini yememe.
        // 1-1: kaliteli (640x480 @ 24fps icin ~500-700 kbps gerekir).
        // Mesh: her peer ayri encode oldugu icin daha agresif sikistirma. 3 peer × 300 = 900kbps upload.
        private const val VIDEO_MAX_BITRATE_BPS_P2P = 600_000
        private const val VIDEO_MAX_BITRATE_BPS_MESH = 300_000
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

    // --- Grup arama (mesh WebRTC) ---
    private val groupPeerConnections = ConcurrentHashMap<String, PeerConnection>()
    private val groupRemoteDescSet = ConcurrentHashMap<String, Boolean>()
    private val groupPendingIce = ConcurrentHashMap<String, ConcurrentLinkedQueue<IceCandidate>>()
    private val _remoteVideoTracks = MutableStateFlow<Map<String, VideoTrack>>(emptyMap())
    val remoteVideoTracksFlow: StateFlow<Map<String, VideoTrack>> = _remoteVideoTracks.asStateFlow()

    // --- Audio level polling (grup arama konusma gostergesi icin) ---
    // Mesh + SFU her iki dalda da inbound-rtp/audio stat'larindan audioLevel okunur.
    // Yerel kullanici icin v1'de polling yapilmaz — media-source stat'i WebRTC build
    // versiyonuna gore eksik olabilir; UX olarak da kendi avatarinda pulse beklenmez.
    private val internalScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var statsJob: Job? = null
    private val _audioLevels = MutableStateFlow<Map<String, Float>>(emptyMap())
    val audioLevelsFlow: StateFlow<Map<String, Float>> = _audioLevels.asStateFlow()

    // SFU subscriber feedId -> peerId eslesmesi (Janus 'display' alaninda peerId tasinir).
    private val sfuFeedToPeer = ConcurrentHashMap<Long, String>()

    /** Grup aramasi ICE candidate callback — peerId ile birlikte uretilir. */
    var onGroupIceCandidateGenerated: ((String, IceCandidate) -> Unit)? = null

    /** Grup aramasi ICE baglanti durumu callback — peerId ile birlikte bildirilir. */
    var onGroupConnectionStateChanged: ((String, PeerConnection.IceConnectionState) -> Unit)? = null

    // --- SFU mode callback'leri (PC tanimlari ileride, "SFU PeerConnection Yonetimi" bolumunde) ---
    /** SFU publisher PC icin yerel ICE candidate — Janus'a trickle gonderilir. */
    var onSfuPublisherIce: ((IceCandidate) -> Unit)? = null

    /** SFU publisher ICE gathering tamamlandi. */
    var onSfuPublisherIceComplete: (() -> Unit)? = null

    /** SFU subscriber PC icin yerel ICE candidate — feedId ile birlikte. */
    var onSfuSubscriberIce: ((Long, IceCandidate) -> Unit)? = null

    /** SFU publisher baglanti durumu. */
    var onSfuPublisherConnectionStateChanged: ((PeerConnection.IceConnectionState) -> Unit)? = null

    /** ICE sunucu listesi — sunucudan dinamik cekilir, fallback olarak STUN kullanilir.
     *  Hardcoded URL kaldirildi — stunUrl BuildConfig.STUN_URL'den inject edilir. */
    @Volatile
    private var iceServers: List<PeerConnection.IceServer> = listOf(
        PeerConnection.IceServer.builder(stunUrl)
            .createIceServer()
    )

    /**
     * Sunucudan dinamik TURN credential alip ICE sunucu listesini gunceller.
     * Her arama baslatilmadan once cagirilmali.
     */
    fun updateIceServers(servers: List<PeerConnection.IceServer>) {
        iceServers = servers
        Log.d(TAG, "ICE sunuculari guncellendi: ${servers.size} sunucu")
    }

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

        // 1-1: max video bitrate cap — agresif kullanici upload'u sinirla.
        applyVideoBitrateCap(pc, VIDEO_MAX_BITRATE_BPS_P2P)

        Log.d(TAG, "Yerel video baslatildi: ${VIDEO_WIDTH}x${VIDEO_HEIGHT} @ ${VIDEO_FPS}fps")
    }

    /**
     * PC uzerindeki video sender'larin maxBitrateBps degerini set eder.
     * SDP renegotiation gerektirmez — RtpSender.setParameters anlik etkili.
     */
    private fun applyVideoBitrateCap(pc: PeerConnection, maxBitrateBps: Int) {
        try {
            for (sender in pc.senders) {
                val track = sender.track() ?: continue
                if (track.kind() == "video") {
                    val params = sender.parameters
                    for (enc in params.encodings) {
                        enc.maxBitrateBps = maxBitrateBps
                    }
                    sender.parameters = params
                    Log.d(TAG, "Video bitrate cap: ${maxBitrateBps / 1000} kbps")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "applyVideoBitrateCap hatasi: ${e.message}")
        }
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

    // ---- Grup Arama PeerConnection Yonetimi ----

    /**
     * Yerel medya kaynaklarinin (audio/video) olusturulmasini saglar.
     * Grup aramalarda paylasimli medya icin: bir kez olustur, tum PC'lere ekle.
     */
    private fun ensureLocalMedia(factory: PeerConnectionFactory, enableVideo: Boolean) {
        if (localAudioTrack == null) {
            localAudioSource = factory.createAudioSource(MediaConstraints())
            localAudioTrack = factory.createAudioTrack("audio0", localAudioSource)
            localAudioTrack?.setEnabled(true)
        }
        if (enableVideo && localVideoTrack == null) {
            startLocalVideoInternal(factory)
        }
    }

    /**
     * Video capturer ve track olusturur (ama PC'ye eklemez — bunu arayan yapar).
     */
    private fun startLocalVideoInternal(factory: PeerConnectionFactory) {
        val enumerator = Camera2Enumerator(context)
        val cameraName = getCameraName(enumerator) ?: run {
            Log.e(TAG, "Kamera bulunamadi (group)")
            return
        }
        videoCapturer = enumerator.createCapturer(cameraName, null)
        surfaceTextureHelper = SurfaceTextureHelper.create("GroupCaptureThread", eglBase!!.eglBaseContext)
        localVideoSource = factory.createVideoSource(videoCapturer!!.isScreencast)
        videoCapturer!!.initialize(surfaceTextureHelper, context, localVideoSource!!.capturerObserver)
        videoCapturer!!.startCapture(VIDEO_WIDTH, VIDEO_HEIGHT, VIDEO_FPS)
        localVideoTrack = factory.createVideoTrack("video0", localVideoSource)
        localVideoTrack?.setEnabled(true)
        _localVideoTrack.value = localVideoTrack
        Log.d(TAG, "Paylasimli yerel video baslatildi: ${VIDEO_WIDTH}x${VIDEO_HEIGHT} @ ${VIDEO_FPS}fps")
    }

    /**
     * Grup aramasi icin yeni PeerConnection olusturur.
     * Mevcut baglantilari KAPATMAZ — mesh'e yeni peer ekler.
     * Paylasimli yerel audio/video track'leri otomatik eklenir.
     */
    fun createGroupPeerConnection(peerId: String, enableVideo: Boolean): PeerConnection? {
        if (!initialized) initialize()
        val factory = peerConnectionFactory ?: return null

        ensureLocalMedia(factory, enableVideo)

        groupRemoteDescSet[peerId] = false
        groupPendingIce[peerId] = ConcurrentLinkedQueue()

        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            iceTransportsType = PeerConnection.IceTransportsType.ALL
        }

        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                Log.d(TAG, "Group ICE candidate: $peerId - ${candidate.sdpMid}")
                onGroupIceCandidateGenerated?.invoke(peerId, candidate)
            }
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "Group ICE state: $peerId -> $state")
                val peerState = when (state) {
                    PeerConnection.IceConnectionState.CONNECTED,
                    PeerConnection.IceConnectionState.COMPLETED -> PeerState.CONNECTED_P2P
                    PeerConnection.IceConnectionState.DISCONNECTED -> PeerState.RECONNECTING
                    PeerConnection.IceConnectionState.FAILED -> PeerState.DISCONNECTED
                    else -> PeerState.CONNECTING
                }
                updatePeerState(peerId, peerState)
                onGroupConnectionStateChanged?.invoke(peerId, state)
            }
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                val track = receiver.track()
                when (track) {
                    is VideoTrack -> {
                        track.setEnabled(true)
                        _remoteVideoTracks.value = _remoteVideoTracks.value + (peerId to track)
                        Log.d(TAG, "Group remote video track: $peerId")
                    }
                    is AudioTrack -> {
                        track.setEnabled(true)
                        Log.d(TAG, "Group remote audio track: $peerId")
                    }
                }
            }
            override fun onSignalingChange(state: PeerConnection.SignalingState) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onDataChannel(channel: DataChannel) {}
            override fun onRenegotiationNeeded() {}
        }

        val pc = factory.createPeerConnection(config, observer) ?: return null

        localAudioTrack?.let { pc.addTrack(it, listOf("stream0")) }
        if (enableVideo) {
            localVideoTrack?.let { pc.addTrack(it, listOf("stream0")) }
            // Mesh: her peer ayri encode, daha agresif bitrate cap (300 kbps).
            applyVideoBitrateCap(pc, VIDEO_MAX_BITRATE_BPS_MESH)
        }

        groupPeerConnections[peerId] = pc
        Log.d(TAG, "Group PeerConnection olusturuldu: peerId=$peerId, video=$enableVideo (toplam: ${groupPeerConnections.size})")
        return pc
    }

    /** Belirli bir grup peer'i icin SDP Offer olusturur. */
    suspend fun createOfferForPeer(peerId: String): SessionDescription = suspendCoroutine { cont ->
        val pc = groupPeerConnections[peerId]
            ?: throw IllegalStateException("Group PeerConnection bulunamadi: $peerId")
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }
        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        Log.d(TAG, "Group SDP Offer olusturuldu: $peerId")
                        cont.resume(sdp)
                    }
                    override fun onSetFailure(error: String) {
                        cont.resumeWithException(RuntimeException("setLocalDescription failed: $error"))
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(e: String) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) {
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    /** Belirli bir grup peer'i icin SDP Answer olusturur. */
    suspend fun createAnswerForPeer(peerId: String): SessionDescription = suspendCoroutine { cont ->
        val pc = groupPeerConnections[peerId]
            ?: throw IllegalStateException("Group PeerConnection bulunamadi: $peerId")
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }
        pc.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        Log.d(TAG, "Group SDP Answer olusturuldu: $peerId")
                        cont.resume(sdp)
                    }
                    override fun onSetFailure(error: String) {
                        cont.resumeWithException(RuntimeException("setLocalDescription failed: $error"))
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(e: String) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) {
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    /** Belirli bir grup peer'i icin remote description ayarlar. */
    suspend fun setRemoteDescriptionForPeer(peerId: String, sdp: SessionDescription) = suspendCoroutine<Unit> { cont ->
        val pc = groupPeerConnections[peerId]
        if (pc == null) {
            cont.resumeWithException(IllegalStateException("Group PeerConnection bulunamadi: $peerId"))
            return@suspendCoroutine
        }
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                Log.d(TAG, "Group remote description set: $peerId (${sdp.type})")
                groupRemoteDescSet[peerId] = true
                drainGroupPendingIce(peerId)
                cont.resume(Unit)
            }
            override fun onSetFailure(error: String) {
                cont.resumeWithException(RuntimeException("setRemoteDescription failed: $error"))
            }
            override fun onCreateSuccess(sdp: SessionDescription) {}
            override fun onCreateFailure(error: String) {}
        }, sdp)
    }

    /** Belirli bir grup peer'i icin ICE candidate ekler. */
    fun addIceCandidateForPeer(peerId: String, candidate: IceCandidate) {
        if (groupRemoteDescSet[peerId] == true) {
            groupPeerConnections[peerId]?.addIceCandidate(candidate)
        } else {
            groupPendingIce.getOrPut(peerId) { ConcurrentLinkedQueue() }.add(candidate)
            Log.d(TAG, "Group ICE candidate buffer: $peerId (${groupPendingIce[peerId]?.size} bekliyor)")
        }
    }

    private fun drainGroupPendingIce(peerId: String) {
        val pc = groupPeerConnections[peerId] ?: return
        val queue = groupPendingIce[peerId] ?: return
        var count = 0
        while (true) {
            val candidate = queue.poll() ?: break
            pc.addIceCandidate(candidate)
            count++
        }
        if (count > 0) Log.d(TAG, "Group $count bekleyen ICE candidate eklendi: $peerId")
    }

    /** Belirli bir grup peer'inin PeerConnection'ini kapatir. */
    fun disposeGroupPeerConnection(peerId: String) {
        groupPeerConnections.remove(peerId)?.close()
        groupRemoteDescSet.remove(peerId)
        groupPendingIce.remove(peerId)
        _remoteVideoTracks.value = _remoteVideoTracks.value - peerId
        Log.d(TAG, "Group PeerConnection dispose: $peerId")
    }

    /** Tum grup PeerConnection'larini kapatir ve yerel medyayi temizler. */
    fun disposeAllGroupPeerConnections() {
        // Polling'i ONCE durdur (cancelAndJoin) — in-flight getStats kapali PC'ye dusmesin
        stopAudioLevelPolling()

        closeGroupPeerConnectionsOnly()

        // Paylasimli yerel medyayi temizle
        disposeSharedLocalMedia()

        onGroupIceCandidateGenerated = null
        onGroupConnectionStateChanged = null
        Log.d(TAG, "Tum grup PeerConnection'lari ve medya temizlendi")
    }

    /**
     * Sadece mesh PeerConnection'lari kapatir, paylasimli yerel medyaya DOKUNMAZ.
     * SFU'ya gecis sirasinda kullanilir — SFU publisher ayni medya track'lerini kullanir.
     */
    fun closeGroupPeerConnectionsOnly() {
        groupPeerConnections.forEach { (_, pc) ->
            try { pc.close() } catch (_: Exception) {}
        }
        groupPeerConnections.clear()
        groupRemoteDescSet.clear()
        groupPendingIce.clear()
        _remoteVideoTracks.value = emptyMap()
        onGroupIceCandidateGenerated = null
        onGroupConnectionStateChanged = null
        Log.d(TAG, "Grup PeerConnection'lari kapatildi (medya korundu)")
    }

    /**
     * Local video source uzerine bir VideoProcessor takar veya cikarir.
     * Processor null gecilirse mevcut isleyici kaldirilir; capture pipeline
     * dogrudan source'a baglanir.
     *
     * F7 background blur: media modulundeki BackgroundBlurProcessor buradan
     * enjekte edilir; CallManager toggle eder.
     */
    fun setVideoProcessor(processor: org.webrtc.VideoProcessor?) {
        val source = localVideoSource
        if (source == null) {
            Log.w(TAG, "setVideoProcessor: localVideoSource null — atlandi")
            return
        }
        try {
            source.setVideoProcessor(processor)
            Log.d(TAG, "VideoProcessor set: ${processor?.javaClass?.simpleName ?: "null"}")
        } catch (e: Exception) {
            Log.w(TAG, "setVideoProcessor hatasi: ${e.message}")
        }
    }

    /** F7 background blur processor olusturmak icin gerekli SurfaceTextureHelper. */
    fun getSurfaceTextureHelper(): SurfaceTextureHelper? = surfaceTextureHelper

    /**
     * Paylasimli yerel medya kaynaklarini (audio/video track, capturer) serbest birakir.
     * Tum PeerConnection'lar kapandiktan sonra cagirilmali.
     */
    private fun disposeSharedLocalMedia() {
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
        _localVideoTrack.value = null
        Log.d(TAG, "Paylasimli yerel medya kaynaklari serbest birakildi")
    }

    // ---- SFU (Janus VideoRoom) PeerConnection Yonetimi ----

    /** SFU publisher PeerConnection — yerel medya Janus'a yayinlanir. */
    private var sfuPublisherPc: PeerConnection? = null

    /** SFU subscriber PeerConnection'lari: feedId -> PeerConnection */
    private val sfuSubscriberPcs = ConcurrentHashMap<Long, PeerConnection>()

    /** SFU subscriber remote video track'leri: feedId -> VideoTrack */
    private val _sfuRemoteVideoTracks = MutableStateFlow<Map<Long, VideoTrack>>(emptyMap())
    val sfuRemoteVideoTracksFlow: StateFlow<Map<Long, VideoTrack>> = _sfuRemoteVideoTracks.asStateFlow()

    /**
     * SFU publisher PeerConnection olusturur.
     * Yerel audio/video track'leri Janus VideoRoom'a yayinlamak icin tek PeerConnection.
     * Mesh'ten farkli olarak sadece BIR PC gerekir (N-1 yerine).
     */
    fun createSfuPublisherConnection(enableVideo: Boolean): PeerConnection? {
        if (!initialized) initialize()
        val factory = peerConnectionFactory ?: return null

        sfuPublisherPc?.close()
        sfuPublisherPc = null

        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            iceTransportsType = PeerConnection.IceTransportsType.ALL
        }

        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                onSfuPublisherIce?.invoke(candidate)
            }
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                if (state == PeerConnection.IceGatheringState.COMPLETE) {
                    onSfuPublisherIceComplete?.invoke()
                }
            }
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "SFU Publisher ICE state: $state")
                onSfuPublisherConnectionStateChanged?.invoke(state)
            }
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
            override fun onSignalingChange(state: PeerConnection.SignalingState) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onDataChannel(channel: DataChannel) {}
            override fun onRenegotiationNeeded() {}
        }

        val pc = factory.createPeerConnection(config, observer) ?: return null

        // Audio track
        ensureLocalMedia(factory, enableVideo)
        localAudioTrack?.let { pc.addTrack(it, listOf("stream0")) }
        if (enableVideo) {
            localVideoTrack?.let { pc.addTrack(it, listOf("stream0")) }
        }

        sfuPublisherPc = pc
        Log.d(TAG, "SFU Publisher PeerConnection olusturuldu, video=$enableVideo")
        return pc
    }

    /** SFU publisher icin SDP Offer olusturur. */
    suspend fun createSfuPublisherOffer(): SessionDescription = suspendCoroutine { cont ->
        val pc = sfuPublisherPc
            ?: throw IllegalStateException("SFU Publisher PeerConnection bulunamadi")
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "false"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false"))
        }
        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        Log.d(TAG, "SFU Publisher Offer olusturuldu (${sdp.description.length} byte)")
                        cont.resume(sdp)
                    }
                    override fun onSetFailure(error: String) {
                        cont.resumeWithException(RuntimeException("setLocalDescription failed: $error"))
                    }
                    override fun onCreateSuccess(s: SessionDescription) {}
                    override fun onCreateFailure(e: String) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) {
                cont.resumeWithException(RuntimeException(error))
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    /** SFU publisher icin remote SDP answer ayarlar. */
    suspend fun setSfuPublisherRemoteAnswer(sdp: SessionDescription) = suspendCoroutine<Unit> { cont ->
        val pc = sfuPublisherPc
            ?: throw IllegalStateException("SFU Publisher PeerConnection bulunamadi")
        pc.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                Log.d(TAG, "SFU Publisher remote answer set edildi")
                cont.resume(Unit)
            }
            override fun onSetFailure(error: String) {
                cont.resumeWithException(RuntimeException("setRemoteDescription failed: $error"))
            }
            override fun onCreateSuccess(sdp: SessionDescription) {}
            override fun onCreateFailure(error: String) {}
        }, sdp)
    }

    /**
     * SFU subscriber PeerConnection olusturur.
     * Janus'tan gelen her remote publisher icin ayri PeerConnection.
     * Sadece medya alir (recvonly).
     */
    fun createSfuSubscriberConnection(feedId: Long): PeerConnection? {
        if (!initialized) initialize()
        val factory = peerConnectionFactory ?: return null

        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            iceTransportsType = PeerConnection.IceTransportsType.ALL
        }

        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                onSfuSubscriberIce?.invoke(feedId, candidate)
            }
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "SFU Subscriber ICE state: feedId=$feedId -> $state")
            }
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                val track = receiver.track()
                when (track) {
                    is VideoTrack -> {
                        track.setEnabled(true)
                        _sfuRemoteVideoTracks.value = _sfuRemoteVideoTracks.value + (feedId to track)
                        Log.d(TAG, "SFU Subscriber remote video track: feedId=$feedId")
                    }
                    is AudioTrack -> {
                        track.setEnabled(true)
                        Log.d(TAG, "SFU Subscriber remote audio track: feedId=$feedId")
                    }
                }
            }
            override fun onSignalingChange(state: PeerConnection.SignalingState) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onAddStream(stream: MediaStream) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onDataChannel(channel: DataChannel) {}
            override fun onRenegotiationNeeded() {}
        }

        val pc = factory.createPeerConnection(config, observer) ?: return null
        sfuSubscriberPcs[feedId] = pc
        Log.d(TAG, "SFU Subscriber PeerConnection olusturuldu: feedId=$feedId")
        return pc
    }

    /** SFU subscriber icin Janus'tan gelen SDP offer'i ayarlar ve answer uretir. */
    suspend fun handleSfuSubscriberOffer(feedId: Long, remoteSdp: SessionDescription): SessionDescription {
        val pc = sfuSubscriberPcs[feedId]
            ?: throw IllegalStateException("SFU Subscriber PeerConnection bulunamadi: feedId=$feedId")

        // Remote offer'i set et
        suspendCoroutine<Unit> { cont ->
            pc.setRemoteDescription(object : SdpObserver {
                override fun onSetSuccess() { cont.resume(Unit) }
                override fun onSetFailure(error: String) { cont.resumeWithException(RuntimeException(error)) }
                override fun onCreateSuccess(sdp: SessionDescription) {}
                override fun onCreateFailure(error: String) {}
            }, remoteSdp)
        }

        // Answer olustur
        return suspendCoroutine { cont ->
            val constraints = MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
                mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
            }
            pc.createAnswer(object : SdpObserver {
                override fun onCreateSuccess(sdp: SessionDescription) {
                    pc.setLocalDescription(object : SdpObserver {
                        override fun onSetSuccess() {
                            Log.d(TAG, "SFU Subscriber answer olusturuldu: feedId=$feedId")
                            cont.resume(sdp)
                        }
                        override fun onSetFailure(error: String) {
                            cont.resumeWithException(RuntimeException(error))
                        }
                        override fun onCreateSuccess(s: SessionDescription) {}
                        override fun onCreateFailure(e: String) {}
                    }, sdp)
                }
                override fun onCreateFailure(error: String) {
                    cont.resumeWithException(RuntimeException(error))
                }
                override fun onSetSuccess() {}
                override fun onSetFailure(error: String) {}
            }, constraints)
        }
    }

    /** SFU subscriber PeerConnection'ini kapatir. */
    fun disposeSfuSubscriber(feedId: Long) {
        sfuSubscriberPcs.remove(feedId)?.close()
        _sfuRemoteVideoTracks.value = _sfuRemoteVideoTracks.value - feedId
        unregisterSfuFeed(feedId)
        Log.d(TAG, "SFU Subscriber dispose: feedId=$feedId")
    }

    /** Tum SFU kaynaklarini temizler (publisher + tum subscriber'lar). */
    fun disposeAllSfuConnections() {
        // Polling'i ONCE durdur (cancelAndJoin) — in-flight getStats kapali PC'ye dusmesin
        stopAudioLevelPolling()

        sfuPublisherPc?.close()
        sfuPublisherPc = null

        sfuSubscriberPcs.forEach { (_, pc) ->
            try { pc.close() } catch (_: Exception) {}
        }
        sfuSubscriberPcs.clear()
        _sfuRemoteVideoTracks.value = emptyMap()
        sfuFeedToPeer.clear()

        // Paylasimli yerel medyayi temizle (tek noktadan)
        disposeSharedLocalMedia()

        Log.d(TAG, "Tum SFU PeerConnection'lari temizlendi")
    }

    // ---- Temizlik ----

    fun disposePeerConnection() {
        // WebRTC best practice sıralaması:
        // 1) Track'leri SUSTUR (setEnabled=false) — close() async oldugu icin
        //    dispose esnasinda hala ses paketi gonderiyor olabilir.
        // 2) PeerConnection.close() — close() asenkrondur, sinyal/ICE'i durdurur.
        // 3) Kisa delay (close() ICE thread'inin temizlenmesi icin ~150ms yeterli).
        // 4) Track'leri dispose et — close()'dan sonra olmalı, aksi halde
        //    close() icindeki audio render hala dispose'lu track'e erisebilir → crash/leak.
        // 5) Source ve diger native kaynaklar.
        try {
            // 1. Track'leri susur — ses paketleri kesilsin, remote tarafta sessizlik
            try { localAudioTrack?.setEnabled(false) } catch (_: Exception) {}
            try { localVideoTrack?.setEnabled(false) } catch (_: Exception) {}
            try { remoteAudioTrack?.setEnabled(false) } catch (_: Exception) {}

            // 2. Video capture'i hemen durdur (kamerayi serbest birak)
            try { videoCapturer?.stopCapture() } catch (_: Exception) {}

            // 3. PeerConnection close — ICE/DTLS/SCTP shutdown asenkron
            val pcToClose = peerConnection
            peerConnection = null
            currentPeerId = null
            try { pcToClose?.close() } catch (e: Exception) {
                Log.w(TAG, "peerConnection.close() hatasi: ${e.message}")
            }

            // 4. Kisa delay — close() ICE thread'inin temizlenmesi icin pencere.
            //    Senkron olarak Thread.sleep guvenli (caller IO scope'unda).
            try { Thread.sleep(150) } catch (_: InterruptedException) {}

            // 5. Track ve source dispose — close()'dan sonra guvenli
            try { localVideoTrack?.dispose() } catch (e: Exception) { Log.w(TAG, "localVideoTrack.dispose: ${e.message}") }
            localVideoTrack = null
            try { localVideoSource?.dispose() } catch (e: Exception) { Log.w(TAG, "localVideoSource.dispose: ${e.message}") }
            localVideoSource = null
            try { localAudioTrack?.dispose() } catch (e: Exception) { Log.w(TAG, "localAudioTrack.dispose: ${e.message}") }
            localAudioTrack = null
            try { localAudioSource?.dispose() } catch (e: Exception) { Log.w(TAG, "localAudioSource.dispose: ${e.message}") }
            localAudioSource = null

            try { videoCapturer?.dispose() } catch (_: Exception) {}
            videoCapturer = null
            try { surfaceTextureHelper?.dispose() } catch (_: Exception) {}
            surfaceTextureHelper = null

            // 6. State flag'leri sifirla
            isRemoteDescriptionSet = false
            pendingIceCandidates.clear()
            _remoteVideoTrack.value = null
            _localVideoTrack.value = null
            remoteAudioTrack = null

            Log.d(TAG, "PeerConnection ve kaynaklar temizlendi (best-practice sira)")
        } catch (e: Exception) {
            Log.e(TAG, "disposePeerConnection beklenmedik hata: ${e.message}", e)
        }
    }

    fun release() {
        disposePeerConnection()
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
        eglBase?.release()
        eglBase = null
        initialized = false
    }

    // =====================================================================
    // Audio Level Polling (grup arama konusma gostergesi)
    // =====================================================================

    /**
     * SFU subscriber feedId -> peerId esleshmesini kaydeder.
     * subscribeToFeed sirasinda Janus 'display' alani peerId tasir.
     */
    fun registerSfuFeed(feedId: Long, peerId: String) {
        sfuFeedToPeer[feedId] = peerId
    }

    fun unregisterSfuFeed(feedId: Long) {
        sfuFeedToPeer.remove(feedId)
    }

    /**
     * Tum aktif PC'lerden 500ms araliklarla audioLevel okur ve [audioLevelsFlow]'a yayar.
     * Mesh dali: groupPeerConnections (peerId -> PC).
     * SFU dali: sfuSubscriberPcs (feedId -> PC) + sfuFeedToPeer ile peerId cozulur.
     * Idempotent: iki kere cagirmak guvenli, ikinci cagirma onceki job'u iptal eder.
     */
    fun startAudioLevelPolling() {
        statsJob?.cancel()
        statsJob = internalScope.launch {
            while (isActive) {
                val snapshot = mutableMapOf<String, Float>()

                // Mesh
                for ((peerId, pc) in groupPeerConnections) {
                    snapshot[peerId] = readInboundAudioLevel(pc)
                }

                // SFU
                for ((feedId, pc) in sfuSubscriberPcs) {
                    val peerId = sfuFeedToPeer[feedId] ?: continue
                    snapshot[peerId] = readInboundAudioLevel(pc)
                }

                _audioLevels.value = snapshot
                delay(500)
            }
        }
    }

    /**
     * Polling'i durdurur. dispose noktalarinda PC.close() ONCESI cagirilmali,
     * cancelAndJoin ile in-flight tick bitirilir — kapali PC'de getStats riskini onler.
     */
    fun stopAudioLevelPolling() {
        val job = statsJob ?: run { _audioLevels.value = emptyMap(); return }
        statsJob = null
        try {
            runBlocking { job.cancelAndJoin() }
        } catch (_: Exception) {}
        _audioLevels.value = emptyMap()
    }

    /**
     * Tek bir PC icin inbound-rtp/audio audioLevel okur.
     * suspendCancellableCoroutine: polling job iptal edildiginde callback'in
     * double-resume riskini engeller (cont.isActive kontrolu).
     */
    private suspend fun readInboundAudioLevel(pc: PeerConnection): Float =
        suspendCancellableCoroutine { cont ->
            try {
                pc.getStats { report ->
                    val level = report.statsMap.values
                        .firstOrNull {
                            it.type == "inbound-rtp" &&
                                (it.members["kind"] as? String) == "audio"
                        }
                        ?.let { (it.members["audioLevel"] as? Double)?.toFloat() } ?: 0f
                    if (cont.isActive) cont.resume(level)
                }
            } catch (_: Exception) {
                if (cont.isActive) cont.resume(0f)
            }
        }

    fun updatePeerState(peerId: String, state: PeerState) {
        _peerStates.value = _peerStates.value.toMutableMap().apply { put(peerId, state) }
    }

    private fun getCameraName(enumerator: Camera2Enumerator): String? {
        val names = enumerator.deviceNames
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
