import Foundation
import WebRTC
import Combine

/**
 * WebRTC PeerConnection yöneticisi.
 *
 * Bu sınıf:
 * - WebRTC PeerConnection yaşam döngüsünü yönetir
 * - ICE candidate exchange işlemlerini coordine eder
 * - SDP offer/answer oluşturur ve yönetir
 * - Data channel'ları P2P mesaj iletimi için yönetir
 * - Media track'leri (ses/video) manage eder
 */
@available(iOS 13.0, *)
public class PeerConnectionManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var connections: [String: PeerState] = [:]
    @Published public private(set) var connectionStatistics: [String: RTCStatistics] = [:]

    // MARK: - Private Properties

    private let signalingClient: SignalingClient
    private let networkManager: NetworkManager

    // WebRTC Infrastructure
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]

    // ICE Configuration
    private var iceServers: [RTCIceServer] = []

    // Media
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var audioSource: RTCAudioSource?
    private var videoSource: RTCVideoSource?

    // Event publishers
    private let dataChannelMessageSubject = PassthroughSubject<DataChannelMessage, Never>()
    public var dataChannelMessages: AnyPublisher<DataChannelMessage, Never> {
        dataChannelMessageSubject.eraseToAnyPublisher()
    }

    private let iceConnectionChangeSubject = PassthroughSubject<(peerId: String, state: RTCIceConnectionState), Never>()
    public var iceConnectionChanges: AnyPublisher<(peerId: String, state: RTCIceConnectionState), Never> {
        iceConnectionChangeSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Constants

    private static let dataChannelLabel = "securechat-messages"
    private static let connectionTimeout: TimeInterval = 30.0

    // MARK: - Initialization

    public init(signalingClient: SignalingClient, networkManager: NetworkManager) {
        self.signalingClient = signalingClient
        self.networkManager = networkManager

        super.init()

        setupWebRTC()
        subscribeToNetworkChanges()
        subscribeToSignalingMessages()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /**
     * Belirli bir peer ile PeerConnection kurar.
     */
    public func createPeerConnection(for peerId: String) async throws -> RTCPeerConnection {
        guard peerConnections[peerId] == nil else {
            throw PeerConnectionError.connectionAlreadyExists
        }

        let config = createRTCConfiguration()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        guard let peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: PeerConnectionDelegate(peerId: peerId, manager: self)
        ) else {
            throw PeerConnectionError.creationFailed
        }

        peerConnections[peerId] = peerConnection
        connections[peerId] = .connecting

        print("Created PeerConnection for peer: \(peerId)")

        return peerConnection
    }

    /**
     * Data channel oluşturur veya mevcut olanı döndürür.
     */
    public func getOrCreateDataChannel(for peerId: String) throws -> RTCDataChannel {
        if let existingChannel = dataChannels[peerId] {
            return existingChannel
        }

        guard let peerConnection = peerConnections[peerId] else {
            throw PeerConnectionError.noPeerConnection
        }

        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        config.isNegotiated = false

        guard let dataChannel = peerConnection.dataChannel(
            forLabel: Self.dataChannelLabel,
            configuration: config
        ) else {
            throw PeerConnectionError.dataChannelCreationFailed
        }

        dataChannel.delegate = DataChannelDelegate(peerId: peerId, manager: self)
        dataChannels[peerId] = dataChannel

        print("Created data channel for peer: \(peerId)")

        return dataChannel
    }

    /**
     * SDP offer oluşturur.
     */
    public func createOffer(for peerId: String) async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnections[peerId] else {
            throw PeerConnectionError.noPeerConnection
        }

        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

            peerConnection.offer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: PeerConnectionError.sdpCreationFailed(error.localizedDescription))
                } else if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp) { error in
                        if let error = error {
                            continuation.resume(throwing: PeerConnectionError.setLocalDescriptionFailed(error.localizedDescription))
                        } else {
                            continuation.resume(returning: sdp)
                        }
                    }
                } else {
                    continuation.resume(throwing: PeerConnectionError.unknownError)
                }
            }
        }
    }

    /**
     * SDP answer oluşturur.
     */
    public func createAnswer(for peerId: String) async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnections[peerId] else {
            throw PeerConnectionError.noPeerConnection
        }

        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

            peerConnection.answer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: PeerConnectionError.sdpCreationFailed(error.localizedDescription))
                } else if let sdp = sdp {
                    peerConnection.setLocalDescription(sdp) { error in
                        if let error = error {
                            continuation.resume(throwing: PeerConnectionError.setLocalDescriptionFailed(error.localizedDescription))
                        } else {
                            continuation.resume(returning: sdp)
                        }
                    }
                } else {
                    continuation.resume(throwing: PeerConnectionError.unknownError)
                }
            }
        }
    }

    /**
     * Remote SDP description set eder.
     */
    public func setRemoteDescription(_ sdp: RTCSessionDescription, for peerId: String) async throws {
        guard let peerConnection = peerConnections[peerId] else {
            throw PeerConnectionError.noPeerConnection
        }

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: PeerConnectionError.setRemoteDescriptionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /**
     * ICE candidate ekler.
     */
    public func addIceCandidate(_ candidate: RTCIceCandidate, for peerId: String) throws {
        guard let peerConnection = peerConnections[peerId] else {
            throw PeerConnectionError.noPeerConnection
        }

        peerConnection.add(candidate) { error in
            if let error = error {
                print("Failed to add ICE candidate for \(peerId): \(error.localizedDescription)")
            }
        }
    }

    /**
     * Data channel üzerinden mesaj gönderir.
     */
    public func sendDataChannelMessage(_ data: Data, to peerId: String) throws {
        guard let dataChannel = dataChannels[peerId] else {
            throw PeerConnectionError.noDataChannel
        }

        guard dataChannel.readyState == .open else {
            throw PeerConnectionError.dataChannelNotOpen
        }

        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dataChannel.sendData(buffer)
    }

    /**
     * Peer bağlantısını kapatır ve temizler.
     */
    public func closePeerConnection(for peerId: String) {
        dataChannels.removeValue(forKey: peerId)?.close()
        peerConnections.removeValue(forKey: peerId)?.close()
        connections.removeValue(forKey: peerId)
        connectionStatistics.removeValue(forKey: peerId)

        print("Closed PeerConnection for peer: \(peerId)")
    }

    /**
     * Tüm bağlantıları temizler.
     */
    public func cleanup() {
        for peerId in peerConnections.keys {
            closePeerConnection(for: peerId)
        }

        localAudioTrack = nil
        localVideoTrack = nil
        audioSource = nil
        videoSource = nil
    }

    // MARK: - Media Methods

    /**
     * Yerel audio track oluşturur ve tüm peer connection'lara ekler.
     */
    public func createLocalAudioTrack() {
        audioSource = peerConnectionFactory.audioSource(with: RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        ))

        localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource!, trackId: "audio0")

        // Add to all existing peer connections
        for (_, peerConnection) in peerConnections {
            if let audioTrack = localAudioTrack {
                peerConnection.add(audioTrack, streamIds: ["stream0"])
            }
        }
    }

    /**
     * Yerel video track oluşturur ve tüm peer connection'lara ekler.
     */
    public func createLocalVideoTrack() {
        // TODO: Implement video capture configuration
        // This will be handled by media-agent when integrated
    }

    // MARK: - Private Methods

    private func setupWebRTC() {
        // Initialize WebRTC
        RTCInitializeSSL()

        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )

        updateICEServers()
    }

    private func createRTCConfiguration() -> RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.iceTransportPolicy = .all

        // Optimize for low latency
        config.iceCandidatePoolSize = 10

        return config
    }

    private func updateICEServers() {
        let iceServerConfigs = networkManager.getOptimizedICEServers()
        iceServers = iceServerConfigs.map { config in
            if let username = config.username, let credential = config.credential {
                return RTCIceServer(urlStrings: config.urls, username: username, credential: credential)
            } else {
                return RTCIceServer(urlStrings: config.urls)
            }
        }
    }

    private func subscribeToNetworkChanges() {
        networkManager.$connectionType
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateICEServers()
            }
            .store(in: &cancellables)
    }

    private func subscribeToSignalingMessages() {
        signalingClient.incomingSignals
            .sink { [weak self] message in
                self?.handleSignalingMessage(message)
            }
            .store(in: &cancellables)
    }

    private func handleSignalingMessage(_ message: SignalMessageProtocol) {
        switch message {
        case let offer as SdpOfferMessage:
            handleSdpOffer(offer)
        case let answer as SdpAnswerMessage:
            handleSdpAnswer(answer)
        case let candidate as IceCandidateMessage:
            handleIceCandidate(candidate)
        default:
            break // Other message types handled elsewhere
        }
    }

    private func handleSdpOffer(_ offer: SdpOfferMessage) {
        Task {
            do {
                let peerConnection = try await createPeerConnection(for: offer.senderId)

                let remoteDescription = RTCSessionDescription(type: .offer, sdp: offer.sdp)
                try await setRemoteDescription(remoteDescription, for: offer.senderId)

                let answer = try await createAnswer(for: offer.senderId)

                let answerMessage = SdpAnswerMessage(
                    senderId: getCurrentUserId(),
                    recipientId: offer.senderId,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    sdp: answer.sdp
                )

                signalingClient.sendSignal(answerMessage)

            } catch {
                print("Failed to handle SDP offer: \(error)")
                connections[offer.senderId] = .disconnected
            }
        }
    }

    private func handleSdpAnswer(_ answer: SdpAnswerMessage) {
        Task {
            do {
                let remoteDescription = RTCSessionDescription(type: .answer, sdp: answer.sdp)
                try await setRemoteDescription(remoteDescription, for: answer.senderId)
            } catch {
                print("Failed to handle SDP answer: \(error)")
                connections[answer.senderId] = .disconnected
            }
        }
    }

    private func handleIceCandidate(_ candidateMessage: IceCandidateMessage) {
        let iceCandidate = RTCIceCandidate(
            sdp: candidateMessage.candidate,
            sdpMLineIndex: candidateMessage.sdpMLineIndex,
            sdpMid: candidateMessage.sdpMid
        )

        do {
            try addIceCandidate(iceCandidate, for: candidateMessage.senderId)
        } catch {
            print("Failed to add ICE candidate: \(error)")
        }
    }

    // Internal method to handle connection state changes
    internal func handleConnectionStateChange(for peerId: String, state: RTCIceConnectionState) {
        let peerState: PeerState

        switch state {
        case .new, .checking:
            peerState = .connecting
        case .connected, .completed:
            peerState = .connectedP2P
        case .disconnected:
            peerState = .disconnected
        case .failed:
            peerState = .disconnected
            // Attempt reconnection
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                // Trigger ICE restart if still needed
            }
        case .closed:
            peerState = .disconnected
        @unknown default:
            peerState = .disconnected
        }

        connections[peerId] = peerState
        iceConnectionChangeSubject.send((peerId: peerId, state: state))
    }

    // Internal method to handle data channel messages
    internal func handleDataChannelMessage(from peerId: String, data: Data) {
        let message = DataChannelMessage(peerId: peerId, data: data, timestamp: Date())
        dataChannelMessageSubject.send(message)
    }

    private func getCurrentUserId() -> String {
        // TODO: Get actual user ID from user session
        return "current_user_id"
    }
}

// MARK: - Delegate Classes

private class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
    private let peerId: String
    private weak var manager: PeerConnectionManager?

    init(peerId: String, manager: PeerConnectionManager) {
        self.peerId = peerId
        self.manager = manager
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Peer \(peerId) signaling state changed: \(stateChanged)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Peer \(peerId) added stream with \(stream.audioTracks.count) audio tracks and \(stream.videoTracks.count) video tracks")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Peer \(peerId) removed stream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Peer \(peerId) should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("Peer \(peerId) ICE connection state changed: \(newState)")
        manager?.handleConnectionStateChange(for: peerId, state: newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("Peer \(peerId) ICE gathering state changed: \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("Peer \(peerId) generated ICE candidate")

        let candidateMessage = IceCandidateMessage(
            senderId: manager?.getCurrentUserId() ?? "",
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )

        manager?.signalingClient.sendSignal(candidateMessage)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Peer \(peerId) removed ICE candidates")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Peer \(peerId) opened data channel: \(dataChannel.label)")
        dataChannel.delegate = DataChannelDelegate(peerId: peerId, manager: manager)
    }
}

private class DataChannelDelegate: NSObject, RTCDataChannelDelegate {
    private let peerId: String
    private weak var manager: PeerConnectionManager?

    init(peerId: String, manager: PeerConnectionManager?) {
        self.peerId = peerId
        self.manager = manager
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel for peer \(peerId) state changed: \(dataChannel.readyState)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        manager?.handleDataChannelMessage(from: peerId, data: buffer.data)
    }
}

// MARK: - Supporting Types

/// Data channel message
public struct DataChannelMessage {
    public let peerId: String
    public let data: Data
    public let timestamp: Date

    public init(peerId: String, data: Data, timestamp: Date) {
        self.peerId = peerId
        self.data = data
        self.timestamp = timestamp
    }
}

/// RTC Statistics placeholder
public struct RTCStatistics {
    public let bytesReceived: Int64
    public let bytesSent: Int64
    public let packetsReceived: Int32
    public let packetsSent: Int32
    public let roundTripTime: TimeInterval

    public init(bytesReceived: Int64, bytesSent: Int64, packetsReceived: Int32, packetsSent: Int32, roundTripTime: TimeInterval) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.packetsReceived = packetsReceived
        self.packetsSent = packetsSent
        self.roundTripTime = roundTripTime
    }
}

/// PeerConnection hataları
public enum PeerConnectionError: Error, LocalizedError {
    case connectionAlreadyExists
    case creationFailed
    case noPeerConnection
    case dataChannelCreationFailed
    case noDataChannel
    case dataChannelNotOpen
    case sdpCreationFailed(String)
    case setLocalDescriptionFailed(String)
    case setRemoteDescriptionFailed(String)
    case unknownError

    public var errorDescription: String? {
        switch self {
        case .connectionAlreadyExists:
            return "Bu peer için bağlantı zaten mevcut"
        case .creationFailed:
            return "PeerConnection oluşturulamadı"
        case .noPeerConnection:
            return "Bu peer için PeerConnection yok"
        case .dataChannelCreationFailed:
            return "Data channel oluşturulamadı"
        case .noDataChannel:
            return "Bu peer için data channel yok"
        case .dataChannelNotOpen:
            return "Data channel açık değil"
        case .sdpCreationFailed(let reason):
            return "SDP oluşturma hatası: \(reason)"
        case .setLocalDescriptionFailed(let reason):
            return "Local description ayarlama hatası: \(reason)"
        case .setRemoteDescriptionFailed(let reason):
            return "Remote description ayarlama hatası: \(reason)"
        case .unknownError:
            return "Bilinmeyen hata"
        }
    }
}