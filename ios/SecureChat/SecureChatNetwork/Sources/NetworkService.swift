import Foundation
import Combine
import SecureChatCommon

/**
 * High-level Network Service API.
 *
 * Tüm network operasyonları için tek entry point sağlar.
 * Diğer modüller bu servis aracılığıyla network functionality'e erişir.
 */
@available(iOS 13.0, *)
public class NetworkService: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var activeP2PConnections: Set<String> = []
    @Published public private(set) var networkQuality: NetworkConnectionStatus = .unavailable

    // MARK: - Services

    public let signalingClient: SignalingClient
    public let networkManager: NetworkManager
    public let messageQueue: MessageQueue
    public let peerConnectionManager: PeerConnectionManager
    public let p2pMessageTransport: P2PMessageTransport

    // MARK: - Message Publishers

    public var incomingMessages: AnyPublisher<DecryptedP2PMessage, Never> {
        p2pMessageTransport.incomingMessages
    }

    public var deliveryReceipts: AnyPublisher<DeliveryReceiptMessage, Never> {
        p2pMessageTransport.deliveryReceipts
    }

    public var signalingMessages: AnyPublisher<SignalMessageProtocol, Never> {
        signalingClient.incomingSignals
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        signalingUrl: String,
        enableCertificatePinning: Bool = true,
        cryptoService: CryptoServiceProtocol? = nil
    ) {
        // Initialize services
        self.signalingClient = SignalingClient(
            signalingUrl: signalingUrl,
            enableCertificatePinning: enableCertificatePinning
        )
        self.networkManager = NetworkManager()
        self.messageQueue = MessageQueue(
            signalingClient: signalingClient,
            cryptoService: cryptoService
        )
        self.peerConnectionManager = PeerConnectionManager(
            signalingClient: signalingClient,
            networkManager: networkManager
        )
        self.p2pMessageTransport = P2PMessageTransport(
            peerConnectionManager: peerConnectionManager,
            messageQueue: messageQueue,
            cryptoService: cryptoService
        )

        setupBindings()
    }

    // MARK: - Public API

    /**
     * Network servisini başlatır ve signaling sunucusuna bağlanır.
     */
    public func start(userId: String, authToken: String) {
        signalingClient.connect(userId: userId, authToken: authToken)
        networkManager.startMonitoring()
    }

    /**
     * Network servisini durdurur ve tüm bağlantıları kapatır.
     */
    public func stop() {
        signalingClient.disconnect()
        networkManager.stopMonitoring()
        p2pMessageTransport.closeAllConnections()
    }

    /**
     * Mesaj gönderir (P2P veya signaling relay).
     */
    public func sendMessage(
        to recipientId: String,
        content: String,
        messageType: MessageType = .text,
        priority: MessagePriority = .normal
    ) async throws {
        let data = content.data(using: .utf8) ?? Data()

        try await p2pMessageTransport.sendMessage(
            to: recipientId,
            content: data,
            messageType: messageType,
            priority: priority
        )
    }

    /**
     * Dosya gönderir.
     */
    public func sendFile(
        to recipientId: String,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws {
        // Create file transfer message
        let fileMessage = FileTransferMessage(
            senderId: getCurrentUserId(),
            recipientId: recipientId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(fileData.count),
            data: fileData.base64EncodedString()
        )

        signalingClient.sendSignal(fileMessage)
    }

    /**
     * Mesaj okundu bilgisi gönderir.
     */
    public func markMessageAsRead(messageId: String, senderId: String) async {
        await p2pMessageTransport.sendReadReceipt(for: messageId, to: senderId)
    }

    /**
     * Peer ile P2P bağlantı kurar.
     */
    public func initiateP2PConnection(with peerId: String, callType: CallType = .voice) async throws {
        let peerConnection = try await peerConnectionManager.createPeerConnection(for: peerId)
        let offer = try await peerConnectionManager.createOffer(for: peerId)

        let offerMessage = SdpOfferMessage(
            senderId: getCurrentUserId(),
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: offer.sdp,
            callType: callType
        )

        signalingClient.sendSignal(offerMessage)
    }

    /**
     * P2P bağlantı isteğini kabul eder.
     */
    public func acceptP2PConnection(from peerId: String, offer: SdpOfferMessage) async throws {
        let peerConnection = try await peerConnectionManager.createPeerConnection(for: peerId)

        let remoteDescription = RTCSessionDescription(type: .offer, sdp: offer.sdp)
        try await peerConnectionManager.setRemoteDescription(remoteDescription, for: peerId)

        let answer = try await peerConnectionManager.createAnswer(for: peerId)

        let answerMessage = SdpAnswerMessage(
            senderId: getCurrentUserId(),
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: answer.sdp
        )

        signalingClient.sendSignal(answerMessage)
    }

    /**
     * P2P bağlantıyı reddeder.
     */
    public func rejectP2PConnection(from peerId: String, reason: CallAction = .reject) {
        let rejectMessage = CallControlMessage(
            senderId: getCurrentUserId(),
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: reason
        )

        signalingClient.sendSignal(rejectMessage)
    }

    /**
     * P2P bağlantıyı sonlandırır.
     */
    public func terminateP2PConnection(with peerId: String) async {
        let hangupMessage = CallControlMessage(
            senderId: getCurrentUserId(),
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .hangup
        )

        signalingClient.sendSignal(hangupMessage)
        p2pMessageTransport.closeConnection(to: peerId)
    }

    /**
     * Arama kontrolü gönderir (çalıyor, meşgul, vb.).
     */
    public func sendCallControl(to peerId: String, action: CallAction) {
        let controlMessage = CallControlMessage(
            senderId: getCurrentUserId(),
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: action
        )

        signalingClient.sendSignal(controlMessage)
    }

    /**
     * Network istatistiklerini döndürür.
     */
    public func getNetworkStatistics() -> NetworkStatistics {
        let signalingStats = signalingClient.statistics
        let queueStats = messageQueue.getQueueStatistics()

        return NetworkStatistics(
            signalingConnected: isConnected,
            activeP2PConnections: activeP2PConnections.count,
            networkQuality: networkQuality,
            queuedMessages: queueStats.currentQueueSize,
            totalMessagesSent: signalingStats.messagesSent,
            totalMessagesReceived: signalingStats.messagesReceived,
            reconnectCount: signalingStats.reconnectCount
        )
    }

    /**
     * Belirli bir peer'in bağlantı bilgilerini döndürür.
     */
    public func getConnectionInfo(for peerId: String) -> ConnectionInfo? {
        guard let connectionState = peerConnectionManager.connections[peerId] else {
            return nil
        }

        let transportStats = p2pMessageTransport.getTransportStatistics(for: peerId)

        return ConnectionInfo(
            peerId: peerId,
            connectionState: connectionState,
            transportStatistics: transportStats,
            isP2PActive: activeP2PConnections.contains(peerId)
        )
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Signaling connection state
        signalingClient.$connectionState
            .map { state in
                switch state {
                case .connected:
                    return true
                default:
                    return false
                }
            }
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)

        // Network quality
        networkManager.$connectionStatus
            .assign(to: \.networkQuality, on: self)
            .store(in: &cancellables)

        // P2P connections
        p2pMessageTransport.$activeConnections
            .assign(to: \.activeP2PConnections, on: self)
            .store(in: &cancellables)
    }

    private func getCurrentUserId() -> String {
        // TODO: Get actual user ID from user session or storage
        return "current_user_id"
    }
}

// MARK: - Supporting Types

/// Network service genel istatistikleri
public struct NetworkStatistics {
    public let signalingConnected: Bool
    public let activeP2PConnections: Int
    public let networkQuality: NetworkConnectionStatus
    public let queuedMessages: Int
    public let totalMessagesSent: Int
    public let totalMessagesReceived: Int
    public let reconnectCount: Int

    public init(signalingConnected: Bool, activeP2PConnections: Int, networkQuality: NetworkConnectionStatus, queuedMessages: Int, totalMessagesSent: Int, totalMessagesReceived: Int, reconnectCount: Int) {
        self.signalingConnected = signalingConnected
        self.activeP2PConnections = activeP2PConnections
        self.networkQuality = networkQuality
        self.queuedMessages = queuedMessages
        self.totalMessagesSent = totalMessagesSent
        self.totalMessagesReceived = totalMessagesReceived
        self.reconnectCount = reconnectCount
    }
}

/// Belirli bir peer'ın bağlantı bilgileri
public struct ConnectionInfo {
    public let peerId: String
    public let connectionState: PeerState
    public let transportStatistics: P2PTransportStatistics?
    public let isP2PActive: Bool

    public init(peerId: String, connectionState: PeerState, transportStatistics: P2PTransportStatistics?, isP2PActive: Bool) {
        self.peerId = peerId
        self.connectionState = connectionState
        self.transportStatistics = transportStatistics
        self.isP2PActive = isP2PActive
    }

    /// Bağlantı kalite göstergesi
    public var qualityIndicator: ConnectionQuality {
        return connectionState.qualityIndicator
    }

    /// Bağlantı türü açıklaması
    public var connectionDescription: String {
        if isP2PActive {
            return "Doğrudan P2P bağlantı"
        } else if connectionState == .connectedSignaling {
            return "Relay üzerinden bağlı"
        } else {
            return connectionState.displayName
        }
    }
}

// MARK: - Extensions

import WebRTC

extension RTCSessionDescription {
    convenience init(type: RTCSdpType, sdp: String) {
        self.init(type: type, sdp: sdp)
    }
}