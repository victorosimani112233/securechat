import Foundation
import WebRTC
import Combine
import AVFoundation

/**
 * WebRTC peer connection yöneticisi.
 *
 * Bu sınıf:
 * - WebRTC PeerConnection lifecycle'ını yönetir
 * - Audio/Video stream capture ve render
 * - ICE candidate handling
 * - SDP offer/answer exchange
 * - Media track yönetimi (mute, camera toggle, vb.)
 * - DTLS-SRTP encryption (WebRTC native)
 */
public class WebRTCManager: NSObject, ObservableObject {

    // MARK: - Public Properties

    /// WebRTC bağlantı durumu
    @Published public private(set) var connectionState: RTCPeerConnectionState = .new

    /// ICE bağlantı durumu
    @Published public private(set) var iceConnectionState: RTCIceConnectionState = .new

    /// Local video track aktif mi
    @Published public private(set) var isLocalVideoEnabled: Bool = true

    /// Local audio track aktif mi
    @Published public private(set) var isLocalAudioEnabled: Bool = true

    /// Remote video stream mevcut mu
    @Published public private(set) var hasRemoteVideo: Bool = false

    /// Remote audio stream mevcut mu
    @Published public private(set) var hasRemoteAudio: Bool = false

    /// Kamera pozisyonu (front/back)
    @Published public private(set) var isUsingFrontCamera: Bool = true

    // MARK: - Callbacks

    /// ICE candidate oluşturuldu callback'i
    public var onIceCandidate: ((RTCIceCandidate) -> Void)?

    /// Remote stream eklendi callback'i
    public var onRemoteStreamAdded: ((RTCMediaStream) -> Void)?

    /// Remote stream çıkarıldı callback'i
    public var onRemoteStreamRemoved: ((RTCMediaStream) -> Void)?

    /// Bağlantı durumu değişti callback'i
    public var onConnectionStateChanged: ((RTCPeerConnectionState) -> Void)?

    // MARK: - Private Properties

    private var peerConnectionFactory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?

    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCVideoSource?
    private var videoCapturer: RTCCameraVideoCapturer?

    private var remoteVideoTrack: RTCVideoTrack?
    private var remoteAudioTrack: RTCAudioTrack?

    // Video capture ayarları
    private let targetWidth: Int32 = 1280
    private let targetHeight: Int32 = 720
    private let targetFps: Int32 = 30

    // MARK: - Initialization

    public override init() {
        // WebRTC factory oluştur
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )

        super.init()

        print("WebRTCManager: WebRTC factory oluşturuldu")
    }

    // MARK: - Public Methods

    /**
     * Peer connection oluşturur ve yapılandırır.
     */
    public func createPeerConnection(
        iceServers: [RTCIceServer],
        isVideoCall: Bool = false
    ) throws {
        print("WebRTCManager: Peer connection oluşturuluyor")

        // ICE servers konfigürasyonu
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.iceTransportPolicy = .all
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require

        // DTLS-SRTP encryption (varsayılan olarak aktif)
        configuration.cryptoOptions = RTCCryptoOptions(
            srtpEnableGcmCryptoSuites: true,
            srtpEnableAes128Sha1_32CryptoCipher: true,
            srtpEnableEncryptedRtpHeaderExtensions: false,
            sframeRequireFrameEncryption: false
        )

        // Peer connection constraints
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": isVideoCall ? "true" : "false"
            ],
            optionalConstraints: []
        )

        guard let peerConnection = peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw CallError.webRTCError("Peer connection oluşturulamadı")
        }

        self.peerConnection = peerConnection

        // Local media tracks oluştur
        try createLocalMediaTracks(isVideoCall: isVideoCall)

        print("WebRTCManager: Peer connection başarıyla oluşturuldu")
    }

    /**
     * SDP offer oluşturur.
     */
    public func createOffer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw CallError.webRTCError("Peer connection yok")
        }

        print("WebRTCManager: SDP offer oluşturuluyor")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": localVideoTrack != nil ? "true" : "false"
            ],
            optionalConstraints: []
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: CallError.webRTCError("SDP offer oluşturulamadı: \(error)"))
                } else if let sdp = sdp {
                    // Local description'ı ayarla
                    peerConnection.setLocalDescription(sdp) { setError in
                        if let setError = setError {
                            continuation.resume(throwing: CallError.webRTCError("Local SDP ayarlanamadı: \(setError)"))
                        } else {
                            print("WebRTCManager: SDP offer oluşturuldu ve local description ayarlandı")
                            continuation.resume(returning: sdp)
                        }
                    }
                } else {
                    continuation.resume(throwing: CallError.webRTCError("SDP offer null"))
                }
            }
        }
    }

    /**
     * SDP answer oluşturur.
     */
    public func createAnswer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw CallError.webRTCError("Peer connection yok")
        }

        print("WebRTCManager: SDP answer oluşturuluyor")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": localVideoTrack != nil ? "true" : "false"
            ],
            optionalConstraints: []
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: CallError.webRTCError("SDP answer oluşturulamadı: \(error)"))
                } else if let sdp = sdp {
                    // Local description'ı ayarla
                    peerConnection.setLocalDescription(sdp) { setError in
                        if let setError = setError {
                            continuation.resume(throwing: CallError.webRTCError("Local SDP ayarlanamadı: \(setError)"))
                        } else {
                            print("WebRTCManager: SDP answer oluşturuldu ve local description ayarlandı")
                            continuation.resume(returning: sdp)
                        }
                    }
                } else {
                    continuation.resume(throwing: CallError.webRTCError("SDP answer null"))
                }
            }
        }
    }

    /**
     * Remote SDP description ayarlar.
     */
    public func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
        guard let peerConnection = peerConnection else {
            throw CallError.webRTCError("Peer connection yok")
        }

        print("WebRTCManager: Remote SDP description ayarlanıyor")

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: CallError.webRTCError("Remote SDP ayarlanamadı: \(error)"))
                } else {
                    print("WebRTCManager: Remote SDP description başarıyla ayarlandı")
                    continuation.resume()
                }
            }
        }
    }

    /**
     * ICE candidate ekler.
     */
    public func addIceCandidate(_ candidate: RTCIceCandidate) async throws {
        guard let peerConnection = peerConnection else {
            throw CallError.webRTCError("Peer connection yok")
        }

        print("WebRTCManager: ICE candidate ekleniyor: \(candidate.sdp)")

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.add(candidate) { error in
                if let error = error {
                    continuation.resume(throwing: CallError.webRTCError("ICE candidate eklenemedi: \(error)"))
                } else {
                    print("WebRTCManager: ICE candidate başarıyla eklendi")
                    continuation.resume()
                }
            }
        }
    }

    /**
     * Mikrofonu açar/kapatır.
     */
    public func setMicrophoneEnabled(_ enabled: Bool) {
        localAudioTrack?.isEnabled = enabled
        isLocalAudioEnabled = enabled
        print("WebRTCManager: Mikrofon \(enabled ? "açıldı" : "kapatıldı")")
    }

    /**
     * Kamerayı açar/kapatır.
     */
    public func setCameraEnabled(_ enabled: Bool) {
        localVideoTrack?.isEnabled = enabled
        isLocalVideoEnabled = enabled

        if !enabled {
            videoCapturer?.stopCapture()
        } else {
            startVideoCapture()
        }

        print("WebRTCManager: Kamera \(enabled ? "açıldı" : "kapatıldı")")
    }

    /**
     * Kamera pozisyonunu değiştirir (front/back).
     */
    public func switchCamera() throws {
        guard let videoCapturer = videoCapturer else {
            throw CallError.webRTCError("Video capturer yok")
        }

        videoCapturer.stopCapture()

        // Kamera pozisyonunu değiştir
        isUsingFrontCamera.toggle()

        // Yeni kamera ile capture'ı başlat
        startVideoCapture()

        print("WebRTCManager: Kamera pozisyonu değiştirildi: \(isUsingFrontCamera ? "ön" : "arka")")
    }

    /**
     * Peer connection'ı kapatır ve kaynakları temizler.
     */
    public func closePeerConnection() {
        print("WebRTCManager: Peer connection kapatılıyor")

        videoCapturer?.stopCapture()
        localVideoTrack = nil
        localAudioTrack = nil
        localVideoSource = nil
        videoCapturer = nil

        remoteVideoTrack = nil
        remoteAudioTrack = nil

        peerConnection?.close()
        peerConnection = nil

        connectionState = .closed
        iceConnectionState = .closed
        hasRemoteVideo = false
        hasRemoteAudio = false

        print("WebRTCManager: Peer connection kapatıldı ve kaynaklar temizlendi")
    }

    // MARK: - Private Methods

    private func createLocalMediaTracks(isVideoCall: Bool) throws {
        print("WebRTCManager: Local media tracks oluşturuluyor")

        // Audio track oluştur (her zaman)
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory.audioSource(with: audioConstraints)
        localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")

        guard let localAudioTrack = localAudioTrack else {
            throw CallError.webRTCError("Local audio track oluşturulamadı")
        }

        peerConnection?.add(localAudioTrack, streamIds: ["stream0"])

        // Video track oluştur (sadece video arama ise)
        if isVideoCall {
            localVideoSource = peerConnectionFactory.videoSource()
            guard let localVideoSource = localVideoSource else {
                throw CallError.webRTCError("Local video source oluşturulamadı")
            }

            localVideoTrack = peerConnectionFactory.videoTrack(with: localVideoSource, trackId: "video0")
            guard let localVideoTrack = localVideoTrack else {
                throw CallError.webRTCError("Local video track oluşturulamadı")
            }

            peerConnection?.add(localVideoTrack, streamIds: ["stream0"])

            // Video capture başlat
            videoCapturer = RTCCameraVideoCapturer(delegate: localVideoSource)
            startVideoCapture()
        }

        print("WebRTCManager: Local media tracks başarıyla oluşturuldu")
    }

    private func startVideoCapture() {
        guard let videoCapturer = videoCapturer else { return }

        // Mevcut kameraları listele
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        guard !captureDevices.isEmpty else {
            print("WebRTCManager: Kamera bulunamadı")
            return
        }

        // Ön/arka kamera seç
        let device = captureDevices.first { device in
            if isUsingFrontCamera {
                return device.position == .front
            } else {
                return device.position == .back
            }
        } ?? captureDevices.first!

        // En uygun format seç
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let selectedFormat = formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == targetWidth && dimensions.height == targetHeight
        } ?? formats.first!

        guard let selectedFormat = selectedFormat else {
            print("WebRTCManager: Uygun video format bulunamadı")
            return
        }

        // FPS seç
        let frameRates = selectedFormat.videoSupportedFrameRateRanges
        let selectedFps = frameRates.first { range in
            return range.minFrameRate <= Float64(targetFps) && Float64(targetFps) <= range.maxFrameRate
        }?.maxFrameRate ?? frameRates.first?.maxFrameRate ?? 30.0

        // Video capture başlat
        videoCapturer.startCapture(
            with: device,
            format: selectedFormat,
            fps: Int(selectedFps)
        )

        print("WebRTCManager: Video capture başlatıldı - \(targetWidth)x\(targetHeight)@\(Int(selectedFps))fps")
    }

    private func handleRemoteStream(_ stream: RTCMediaStream) {
        print("WebRTCManager: Remote stream alındı")

        // Remote audio track
        if let audioTrack = stream.audioTracks.first {
            remoteAudioTrack = audioTrack
            hasRemoteAudio = true
            print("WebRTCManager: Remote audio track eklendi")
        }

        // Remote video track
        if let videoTrack = stream.videoTracks.first {
            remoteVideoTrack = videoTrack
            hasRemoteVideo = true
            print("WebRTCManager: Remote video track eklendi")
        }

        // Callback ile bildir
        onRemoteStreamAdded?(stream)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCManager: RTCPeerConnectionDelegate {

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {
        print("WebRTCManager: Signaling state değişti: \(stateChange)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.handleRemoteStream(stream)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DispatchQueue.main.async {
            print("WebRTCManager: Remote stream çıkarıldı")
            self.remoteAudioTrack = nil
            self.remoteVideoTrack = nil
            self.hasRemoteAudio = false
            self.hasRemoteVideo = false
            self.onRemoteStreamRemoved?(stream)
        }
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("WebRTCManager: Peer connection negotiation gerekli")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            print("WebRTCManager: ICE connection state değişti: \(newState)")
            self.iceConnectionState = newState
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("WebRTCManager: ICE gathering state değişti: \(newState)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("WebRTCManager: ICE candidate oluşturuldu: \(candidate.sdp)")
        onIceCandidate?(candidate)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("WebRTCManager: ICE candidate'lar çıkarıldı: \(candidates.count) adet")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("WebRTCManager: Data channel açıldı: \(dataChannel.label)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            print("WebRTCManager: Peer connection state değişti: \(newState)")
            self.connectionState = newState
            self.onConnectionStateChanged?(newState)
        }
    }
}