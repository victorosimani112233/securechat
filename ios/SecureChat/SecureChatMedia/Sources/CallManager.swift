import Foundation
import WebRTC
import CallKit
import Combine
import AVFoundation
import SecureChatNetwork
import SecureChatCommon

/**
 * Ana arama yaşam döngüsü yöneticisi.
 *
 * Bu sınıf Android CallManager'ının iOS eşdeğeridir ve şu sorumlulukları yerine getirir:
 * - Giden/gelen arama başlatma ve yönetme
 * - WebRTC PeerConnection lifecycle'ı
 * - CallKit sistem entegrasyonu
 * - Audio session yönetimi
 * - Media kontrolleri (mute, speaker, camera)
 * - Arama durumu ve istatistikleri
 * - SRTP şifreleme (WebRTC DTLS-SRTP)
 */
@MainActor
public class CallManager: ObservableObject {

    // MARK: - Published Properties

    /// Aktif arama oturumu
    @Published public private(set) var currentSession: CallSession?

    /// Arama durumu değişiklik yayını
    @Published public private(set) var callState: CallState = .idle

    /// Audio route durumu
    @Published public private(set) var audioRoute: AudioRoute = .receiver

    /// Network bağlantı kalitesi
    @Published public private(set) var connectionQuality: ConnectionQuality = .unavailable

    // MARK: - Dependencies

    private let networkService: NetworkService
    private let callKitManager: CallKitManager
    private let webRTCManager: WebRTCManager
    private let audioSessionManager: AudioSessionManager

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var callTimer: Timer?
    private var currentUserId: String = ""

    // Call statistics tracking
    private var callStartTime: Date?
    private var lastStatsCheck: Date?

    // MARK: - Initialization

    public init(networkService: NetworkService) {
        self.networkService = networkService
        self.callKitManager = CallKitManager()
        self.webRTCManager = WebRTCManager()
        self.audioSessionManager = AudioSessionManager()

        super.init()

        setupBindings()
        setupCallKitCallbacks()
        setupWebRTCCallbacks()
        setupSignalingHandlers()

        print("CallManager: iOS CallManager başlatıldı")
    }

    // MARK: - Public API

    /**
     * Giden arama başlatır.
     * Android CallManager.initiateCall() eşdeğeri.
     */
    public func initiateCall(to peerId: String, callType: CallType, userId: String) async throws {
        print("CallManager: Giden arama başlatılıyor - peerId: \(peerId), tip: \(callType)")

        // Guard: Aktif arama kontrolü
        guard currentSession == nil || currentSession?.state == .ended else {
            throw CallError.callAlreadyActive
        }

        currentUserId = userId
        let callId = UUID().uuidString

        // CallSession oluştur
        let session = CallSession(
            callId: callId,
            peerId: peerId,
            callType: callType,
            direction: .outgoing,
            state: .initiating
        )

        currentSession = session
        callState = .initiating

        do {
            // Audio session yapılandır
            try audioSessionManager.configureForCall()

            // WebRTC PeerConnection oluştur
            let iceServers = getICEServers()
            try webRTCManager.createPeerConnection(
                iceServers: iceServers,
                isVideoCall: callType == .video
            )

            // CallKit ile giden arama başlat
            try await callKitManager.startOutgoingCall(
                to: peerId,
                isVideo: callType == .video
            )

            // SDP Offer oluştur ve gönder
            let offer = try await webRTCManager.createOffer()
            let offerMessage = SdpOfferMessage(
                senderId: userId,
                recipientId: peerId,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                sdp: offer.sdp,
                callType: callType
            )

            networkService.signalingClient.sendSignal(offerMessage)

            // Durum güncelle
            updateSession { $0.state = .ringing }
            callState = .ringing

            print("CallManager: Giden arama başlatıldı, SDP Offer gönderildi")

        } catch {
            print("CallManager: Giden arama başlatma hatası: \(error)")
            await cleanupCall()
            throw error
        }
    }

    /**
     * Gelen aramayı kabul eder.
     * Android CallManager.acceptCall() eşdeğeri.
     */
    public func acceptCall() async throws {
        guard let session = currentSession,
              session.direction == .incoming,
              session.state == .ringing else {
            throw CallError.noActiveCall
        }

        print("CallManager: Gelen arama kabul ediliyor")

        do {
            // Audio session yapılandır
            try audioSessionManager.configureForCall()

            // SDP Answer oluştur ve gönder
            let answer = try await webRTCManager.createAnswer()
            let answerMessage = SdpAnswerMessage(
                senderId: currentUserId,
                recipientId: session.peerId,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                sdp: answer.sdp
            )

            networkService.signalingClient.sendSignal(answerMessage)

            // Durum güncelle
            updateSession { $0.state = .connecting }
            callState = .connecting

            print("CallManager: Gelen arama kabul edildi, SDP Answer gönderildi")

        } catch {
            print("CallManager: Arama kabul hatası: \(error)")
            await cleanupCall()
            throw error
        }
    }

    /**
     * Aramayı reddeder.
     */
    public func rejectCall() async {
        guard let session = currentSession else { return }

        print("CallManager: Arama reddediliyor")

        // CallKit'e bildir
        if let callUUID = callKitManager.getCallUUID(for: session.peerId) {
            callKitManager.endCall(callUUID, reason: .declinedElsewhere)
        }

        // Karşı tarafa red mesajı gönder
        let rejectMessage = CallControlMessage(
            senderId: currentUserId,
            recipientId: session.peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .reject
        )

        networkService.signalingClient.sendSignal(rejectMessage)

        // Temizlik
        updateSession { $0.state = .rejected }
        callState = .rejected

        await cleanupCall()
    }

    /**
     * Aramayı sonlandırır.
     * Android CallManager.endCall() eşdeğeri.
     */
    public func endCall() async {
        guard let session = currentSession else { return }

        print("CallManager: Arama sonlandırılıyor")

        // CallKit'e bildir
        if let callUUID = callKitManager.getCallUUID(for: session.peerId) {
            callKitManager.endCall(callUUID, reason: .remoteEnded)
        }

        // Karşı tarafa hangup mesajı gönder
        let hangupMessage = CallControlMessage(
            senderId: currentUserId,
            recipientId: session.peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .hangup
        )

        networkService.signalingClient.sendSignal(hangupMessage)

        // Temizlik
        updateSession { $0.state = .ended }
        callState = .ended

        await cleanupCall()
    }

    // MARK: - Media Controls

    /**
     * Mikrofon mute durumunu değiştirir.
     * Android CallManager.toggleMute() eşdeğeri.
     */
    public func toggleMute() {
        guard let session = currentSession else { return }

        let newMutedState = !session.isMuted
        webRTCManager.setMicrophoneEnabled(!newMutedState)

        updateSession { $0.isMuted = newMutedState }

        print("CallManager: Mikrofon durumu değiştirildi: \(newMutedState ? "kapalı" : "açık")")
    }

    /**
     * Hoparlör durumunu değiştirir.
     * Android CallManager.toggleSpeaker() eşdeğeri.
     */
    public func toggleSpeaker() {
        guard let session = currentSession else { return }

        let newSpeakerState = !session.isSpeakerOn

        do {
            try audioSessionManager.setSpeaker(enabled: newSpeakerState)
            updateSession { $0.isSpeakerOn = newSpeakerState }
            print("CallManager: Hoparlör durumu değiştirildi: \(newSpeakerState ? "açık" : "kapalı")")
        } catch {
            print("CallManager: Hoparlör durumu değiştirilemedi: \(error)")
        }
    }

    /**
     * Kamera açık/kapalı durumunu değiştirir.
     * Android CallManager.toggleCamera() eşdeğeri.
     */
    public func toggleCamera() {
        guard let session = currentSession,
              session.callType == .video else { return }

        let newCameraState = !session.isCameraEnabled
        webRTCManager.setCameraEnabled(newCameraState)

        updateSession { $0.isCameraEnabled = newCameraState }

        print("CallManager: Kamera durumu değiştirildi: \(newCameraState ? "açık" : "kapalı")")
    }

    /**
     * Ön/arka kamera geçişi yapar.
     * Android CallManager.switchCamera() eşdeğeri.
     */
    public func switchCamera() throws {
        guard let session = currentSession,
              session.callType == .video,
              session.isCameraEnabled else { return }

        try webRTCManager.switchCamera()

        updateSession { $0.isUsingFrontCamera = !$0.isUsingFrontCamera }

        print("CallManager: Kamera pozisyonu değiştirildi: \(session.isUsingFrontCamera ? "arka" : "ön")")
    }

    // MARK: - Public Getters

    /**
     * Aktif aramanın süresini hesaplar.
     * Android CallManager.getCallDuration() eşdeğeri.
     */
    public func getCallDuration() -> TimeInterval? {
        return currentSession?.activeDuration
    }

    /**
     * Arama istatistiklerini döndürür.
     */
    public func getCallStatistics() -> CallStatistics? {
        guard let session = currentSession,
              session.state == .active,
              let duration = session.activeDuration else {
            return nil
        }

        // WebRTC stats (basitleştirilmiş)
        return CallStatistics(
            duration: duration,
            audioBitrate: 64.0, // kbps
            videoBitrate: session.callType == .video ? 500.0 : nil,
            latency: 50.0, // ms
            packetLoss: 0.1, // %
            connectionQuality: connectionQuality
        )
    }

    // MARK: - Incoming Call Handling

    /**
     * Gelen arama sinyalini işler.
     * Android CallManager.handleIncomingCall() eşdeğeri.
     */
    internal func handleIncomingCall(_ signal: SdpOfferMessage, currentUserId: String) async {
        print("CallManager: Gelen arama işleniyor - peerId: \(signal.senderId)")

        // Guard: Aktif arama kontrolü
        guard currentSession == nil || currentSession?.state == .ended else {
            print("CallManager: Gelen arama reddedildi - aktif arama var")
            return
        }

        self.currentUserId = currentUserId
        let callId = UUID().uuidString

        // CallSession oluştur
        let session = CallSession(
            callId: callId,
            peerId: signal.senderId,
            callType: signal.callType,
            direction: .incoming,
            state: .ringing
        )

        currentSession = session
        callState = .ringing

        do {
            // WebRTC PeerConnection oluştur
            let iceServers = getICEServers()
            try webRTCManager.createPeerConnection(
                iceServers: iceServers,
                isVideoCall: signal.callType == .video
            )

            // Remote SDP ayarla
            let remoteSdp = RTCSessionDescription(type: .offer, sdp: signal.sdp)
            try await webRTCManager.setRemoteDescription(remoteSdp)

            // CallKit ile gelen arama bildir
            callKitManager.reportIncomingCall(
                from: signal.senderId,
                isVideo: signal.callType == .video
            )

            print("CallManager: Gelen arama başarıyla işlendi")

        } catch {
            print("CallManager: Gelen arama işleme hatası: \(error)")
            await cleanupCall()
        }
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Audio session route değişikliklerini izle
        audioSessionManager.$currentRoute
            .assign(to: \.audioRoute, on: self)
            .store(in: &cancellables)

        // WebRTC connection durumunu izle
        webRTCManager.$connectionState
            .sink { [weak self] state in
                self?.handleWebRTCStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func setupCallKitCallbacks() {
        callKitManager.onCallAccepted = { [weak self] callUUID, peerId in
            Task { @MainActor in
                try? await self?.acceptCall()
            }
        }

        callKitManager.onCallEnded = { [weak self] callUUID in
            Task { @MainActor in
                await self?.endCall()
            }
        }

        callKitManager.onMuteToggled = { [weak self] callUUID, isMuted in
            Task { @MainActor in
                if let session = self?.currentSession, session.isMuted != isMuted {
                    self?.toggleMute()
                }
            }
        }
    }

    private func setupWebRTCCallbacks() {
        webRTCManager.onIceCandidate = { [weak self] candidate in
            Task { @MainActor in
                await self?.sendIceCandidate(candidate)
            }
        }

        webRTCManager.onConnectionStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleWebRTCStateChange(state)
            }
        }
    }

    private func setupSignalingHandlers() {
        // Signaling mesaj dinleyicisi network service üzerinden yapılacak
        // Bu Android implementation'daki callback pattern'ına benzer
    }

    private func handleWebRTCStateChange(_ state: RTCPeerConnectionState) {
        switch state {
        case .connected:
            if currentSession?.state == .connecting {
                startActiveCall()
            }
        case .disconnected:
            connectionQuality = .poor
        case .failed:
            Task { await cleanupCall() }
        case .closed:
            Task { await cleanupCall() }
        default:
            break
        }
    }

    private func startActiveCall() {
        guard let session = currentSession else { return }

        updateSession {
            $0.state = .active
            $0.startTime = Date().timeIntervalSince1970
        }
        callState = .active

        // Call timer başlat
        startCallTimer()
        connectionQuality = .good

        print("CallManager: Arama aktif duruma geçti")
    }

    private func startCallTimer() {
        callTimer?.invalidate()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // UI güncelleme için timer
                self?.objectWillChange.send()
            }
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }

    private func sendIceCandidate(_ candidate: RTCIceCandidate) async {
        guard let session = currentSession else { return }

        let candidateMessage = IceCandidateMessage(
            senderId: currentUserId,
            recipientId: session.peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )

        networkService.signalingClient.sendSignal(candidateMessage)
        print("CallManager: ICE candidate gönderildi")
    }

    private func updateSession(_ update: (inout CallSession) -> Void) {
        guard var session = currentSession else { return }
        update(&session)
        currentSession = session
    }

    private func cleanupCall() async {
        print("CallManager: Arama temizleniyor")

        stopCallTimer()
        webRTCManager.closePeerConnection()
        audioSessionManager.restoreDefaultConfiguration()

        // 2 saniye sonra session'ı temizle (Android pattern'ı)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.currentSession?.state == .ended {
                self.currentSession = nil
                self.callState = .idle
            }
        }
    }

    private func getICEServers() -> [RTCIceServer] {
        // NetworkManager'dan optimize edilmiş ICE server'ları al
        let iceServerConfigs = networkService.networkManager.getOptimizedICEServers()

        return iceServerConfigs.map { config in
            if let username = config.username, let credential = config.credential {
                return RTCIceServer(urlStrings: config.urls, username: username, credential: credential)
            } else {
                return RTCIceServer(urlStrings: config.urls)
            }
        }
    }
}

// MARK: - Signaling Message Handlers

extension CallManager {

    /**
     * SDP Answer mesajını işler.
     */
    internal func handleSdpAnswer(_ signal: SdpAnswerMessage) async {
        guard let session = currentSession,
              session.peerId == signal.senderId,
              session.direction == .outgoing else { return }

        print("CallManager: SDP Answer işleniyor")

        do {
            let remoteSdp = RTCSessionDescription(type: .answer, sdp: signal.sdp)
            try await webRTCManager.setRemoteDescription(remoteSdp)

            updateSession { $0.state = .connecting }
            callState = .connecting

            print("CallManager: SDP Answer başarıyla işlendi")

        } catch {
            print("CallManager: SDP Answer işleme hatası: \(error)")
            await cleanupCall()
        }
    }

    /**
     * ICE Candidate mesajını işler.
     */
    internal func handleIceCandidate(_ signal: IceCandidateMessage) async {
        guard let session = currentSession,
              session.peerId == signal.senderId else { return }

        print("CallManager: ICE Candidate işleniyor")

        do {
            let iceCandidate = RTCIceCandidate(
                sdp: signal.candidate,
                sdpMLineIndex: signal.sdpMLineIndex,
                sdpMid: signal.sdpMid
            )
            try await webRTCManager.addIceCandidate(iceCandidate)

            print("CallManager: ICE Candidate başarıyla işlendi")

        } catch {
            print("CallManager: ICE Candidate işleme hatası: \(error)")
        }
    }

    /**
     * Call control mesajlarını işler.
     */
    internal func handleCallControl(_ signal: CallControlMessage) async {
        guard let session = currentSession,
              session.peerId == signal.senderId else { return }

        print("CallManager: Call control mesajı: \(signal.action)")

        switch signal.action {
        case .accept:
            if session.direction == .outgoing {
                startActiveCall()
            }
        case .reject:
            updateSession { $0.state = .rejected }
            callState = .rejected
            await cleanupCall()
        case .hangup:
            updateSession { $0.state = .ended }
            callState = .ended
            await cleanupCall()
        case .busy:
            updateSession { $0.state = .busy }
            callState = .busy
            await cleanupCall()
        default:
            break
        }
    }
}