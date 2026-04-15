import Foundation
import Combine
import SecureChatCommon

/**
 * P2P mesaj iletim katmanı.
 *
 * DataChannel üzerinden şifreli mesaj gönderme ve alma işlemlerini yönetir.
 * Crypto service ile entegre çalışarak end-to-end encryption sağlar.
 *
 * Bu sınıf:
 * - WebRTC DataChannel üzerinden mesaj gönderir/alır
 * - Signal Protocol ile mesajları şifreler/çözer
 * - Mesaj chunk'lama için büyük mesajları parçalar
 * - Delivery receipt'leri yönetir
 * - Offline olunca MessageQueue'ya fallback eder
 */
@available(iOS 13.0, *)
public class P2PMessageTransport: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var activeConnections: Set<String> = []
    @Published public private(set) var transportStatistics: [String: P2PTransportStatistics] = [:]

    // MARK: - Private Properties

    private let peerConnectionManager: PeerConnectionManager
    private let messageQueue: MessageQueue
    private let cryptoService: CryptoServiceProtocol?

    // Message handling
    private let incomingMessagesSubject = PassthroughSubject<DecryptedP2PMessage, Never>()
    public var incomingMessages: AnyPublisher<DecryptedP2PMessage, Never> {
        incomingMessagesSubject.eraseToAnyPublisher()
    }

    private let deliveryReceiptsSubject = PassthroughSubject<DeliveryReceiptMessage, Never>()
    public var deliveryReceipts: AnyPublisher<DeliveryReceiptMessage, Never> {
        deliveryReceiptsSubject.eraseToAnyPublisher()
    }

    // Message chunking
    private let maxChunkSize = 64000 // 64KB - DataChannel limit
    private var incompleteMessages: [String: IncompleteMessage] = [:]

    // Statistics tracking
    private var messagesSentCount: [String: Int] = [:]
    private var messagesReceivedCount: [String: Int] = [:]
    private var bytesTransferredCount: [String: Int64] = [:]

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        peerConnectionManager: PeerConnectionManager,
        messageQueue: MessageQueue,
        cryptoService: CryptoServiceProtocol? = nil
    ) {
        self.peerConnectionManager = peerConnectionManager
        self.messageQueue = messageQueue
        self.cryptoService = cryptoService

        subscribeToDataChannelMessages()
        subscribeToConnectionStateChanges()
    }

    // MARK: - Public Methods

    /**
     * P2P mesaj gönderir.
     * Bağlantı yoksa MessageQueue'ya fallback eder.
     */
    public func sendMessage(
        to recipientId: String,
        content: Data,
        messageType: MessageType = .text,
        priority: MessagePriority = .normal
    ) async throws {

        // First try P2P
        if activeConnections.contains(recipientId) {
            do {
                try await sendP2PMessage(to: recipientId, content: content, messageType: messageType)
                return
            } catch {
                print("P2P send failed for \(recipientId), falling back to queue: \(error)")
            }
        }

        // Fallback to message queue (signaling relay)
        try await messageQueue.queueMessage(
            recipientId: recipientId,
            content: content,
            messageType: messageType,
            priority: priority
        )
    }

    /**
     * Mesaj okundu bilgisini gönderir.
     */
    public func sendReadReceipt(for messageId: String, to senderId: String) async {
        let receipt = DeliveryReceiptMessage(
            senderId: getCurrentUserId(),
            recipientId: senderId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            messageId: messageId,
            status: "READ"
        )

        if activeConnections.contains(senderId) {
            do {
                let receiptData = try JSONEncoder().encode(receipt)
                try await sendP2PMessage(to: senderId, content: receiptData, messageType: .text)
            } catch {
                print("Failed to send read receipt via P2P: \(error)")
                // Could fallback to signaling if needed
            }
        }
    }

    /**
     * Belirli bir peer için transport istatistiklerini döndürür.
     */
    public func getTransportStatistics(for peerId: String) -> P2PTransportStatistics? {
        return transportStatistics[peerId]
    }

    /**
     * Tüm aktif bağlantıları kapatır.
     */
    public func closeAllConnections() {
        activeConnections.forEach { peerId in
            closeConnection(to: peerId)
        }
    }

    /**
     * Belirli bir peer bağlantısını kapatır.
     */
    public func closeConnection(to peerId: String) {
        activeConnections.remove(peerId)
        peerConnectionManager.closePeerConnection(for: peerId)
        updateTransportStatistics(for: peerId, remove: true)
    }

    // MARK: - Private Methods

    private func subscribeToDataChannelMessages() {
        peerConnectionManager.dataChannelMessages
            .sink { [weak self] message in
                self?.handleDataChannelMessage(message)
            }
            .store(in: &cancellables)
    }

    private func subscribeToConnectionStateChanges() {
        peerConnectionManager.iceConnectionChanges
            .sink { [weak self] (peerId, state) in
                self?.handleConnectionStateChange(peerId: peerId, state: state)
            }
            .store(in: &cancellables)
    }

    private func sendP2PMessage(
        to recipientId: String,
        content: Data,
        messageType: MessageType
    ) async throws {

        // Encrypt message if crypto service available
        let messageToSend: Data
        if let cryptoService = cryptoService {
            let envelope = try await cryptoService.encryptMessage(for: recipientId, content: content)
            let envelopeData = try JSONEncoder().encode(envelope)

            let p2pMessage = P2PMessage(
                messageId: UUID().uuidString,
                senderId: getCurrentUserId(),
                recipientId: recipientId,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                messageType: messageType.rawValue,
                content: envelopeData
            )

            messageToSend = try JSONEncoder().encode(p2pMessage)
        } else {
            // Send as plain text (for debugging only)
            let p2pMessage = P2PMessage(
                messageId: UUID().uuidString,
                senderId: getCurrentUserId(),
                recipientId: recipientId,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                messageType: messageType.rawValue,
                content: content
            )

            messageToSend = try JSONEncoder().encode(p2pMessage)
        }

        // Chunk message if necessary
        if messageToSend.count > maxChunkSize {
            try await sendChunkedMessage(messageToSend, to: recipientId)
        } else {
            try peerConnectionManager.sendDataChannelMessage(messageToSend, to: recipientId)
        }

        // Update statistics
        updateMessageSentStatistics(for: recipientId, bytes: Int64(messageToSend.count))
    }

    private func sendChunkedMessage(_ data: Data, to recipientId: String) async throws {
        let messageId = UUID().uuidString
        let totalChunks = Int(ceil(Double(data.count) / Double(maxChunkSize)))

        for chunkIndex in 0..<totalChunks {
            let startOffset = chunkIndex * maxChunkSize
            let endOffset = min(startOffset + maxChunkSize, data.count)
            let chunkData = data.subdata(in: startOffset..<endOffset)

            let chunk = MessageChunk(
                messageId: messageId,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                data: chunkData
            )

            let chunkJson = try JSONEncoder().encode(chunk)
            try peerConnectionManager.sendDataChannelMessage(chunkJson, to: recipientId)

            // Small delay between chunks to avoid overwhelming the channel
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }

    private func handleDataChannelMessage(_ message: DataChannelMessage) {
        Task {
            do {
                await processIncomingMessage(from: message.peerId, data: message.data)
                updateMessageReceivedStatistics(for: message.peerId, bytes: Int64(message.data.count))
            } catch {
                print("Failed to process incoming message from \(message.peerId): \(error)")
            }
        }
    }

    private func processIncomingMessage(from peerId: String, data: Data) async {
        do {
            // Try to decode as chunk first
            if let chunk = try? JSONDecoder().decode(MessageChunk.self, from: data) {
                await handleMessageChunk(chunk, from: peerId)
                return
            }

            // Try to decode as complete P2P message
            if let p2pMessage = try? JSONDecoder().decode(P2PMessage.self, from: data) {
                await handleCompleteMessage(p2pMessage, from: peerId)
                return
            }

            // Try to decode as delivery receipt
            if let receipt = try? JSONDecoder().decode(DeliveryReceiptMessage.self, from: data) {
                deliveryReceiptsSubject.send(receipt)
                return
            }

            print("Unknown message format from \(peerId)")

        } catch {
            print("Failed to decode message from \(peerId): \(error)")
        }
    }

    private func handleMessageChunk(_ chunk: MessageChunk, from peerId: String) async {
        let key = "\(peerId)_\(chunk.messageId)"

        if var incompleteMsg = incompleteMessages[key] {
            incompleteMsg.chunks[chunk.chunkIndex] = chunk.data

            if incompleteMsg.chunks.count == chunk.totalChunks {
                // Message complete, reassemble
                var completeData = Data()
                for i in 0..<chunk.totalChunks {
                    if let chunkData = incompleteMsg.chunks[i] {
                        completeData.append(chunkData)
                    }
                }

                incompleteMessages.removeValue(forKey: key)

                // Process complete message
                if let p2pMessage = try? JSONDecoder().decode(P2PMessage.self, from: completeData) {
                    await handleCompleteMessage(p2pMessage, from: peerId)
                }
            } else {
                incompleteMessages[key] = incompleteMsg
            }
        } else {
            // First chunk
            var newIncompleteMsg = IncompleteMessage(
                messageId: chunk.messageId,
                totalChunks: chunk.totalChunks,
                chunks: [:],
                receivedAt: Date()
            )
            newIncompleteMsg.chunks[chunk.chunkIndex] = chunk.data
            incompleteMessages[key] = newIncompleteMsg
        }
    }

    private func handleCompleteMessage(_ p2pMessage: P2PMessage, from peerId: String) async {
        do {
            // Decrypt message if crypto service available
            let decryptedContent: Data
            if let cryptoService = cryptoService {
                let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: p2pMessage.content)
                decryptedContent = try await cryptoService.decryptMessage(from: peerId, envelope: envelope)
            } else {
                decryptedContent = p2pMessage.content
            }

            let decryptedMessage = DecryptedP2PMessage(
                messageId: p2pMessage.messageId,
                senderId: p2pMessage.senderId,
                content: decryptedContent,
                messageType: MessageType(rawValue: p2pMessage.messageType) ?? .text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(p2pMessage.timestamp) / 1000.0),
                transportType: .p2p
            )

            incomingMessagesSubject.send(decryptedMessage)

            // Send delivery receipt
            await sendDeliveryReceipt(for: p2pMessage.messageId, to: peerId)

        } catch {
            print("Failed to decrypt message from \(peerId): \(error)")
        }
    }

    private func sendDeliveryReceipt(for messageId: String, to senderId: String) async {
        let receipt = DeliveryReceiptMessage(
            senderId: getCurrentUserId(),
            recipientId: senderId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            messageId: messageId,
            status: "DELIVERED"
        )

        do {
            let receiptData = try JSONEncoder().encode(receipt)
            try peerConnectionManager.sendDataChannelMessage(receiptData, to: senderId)
        } catch {
            print("Failed to send delivery receipt: \(error)")
        }
    }

    private func handleConnectionStateChange(peerId: String, state: RTCIceConnectionState) {
        switch state {
        case .connected, .completed:
            activeConnections.insert(peerId)
            initializeTransportStatistics(for: peerId)
        case .disconnected, .failed, .closed:
            activeConnections.remove(peerId)
        default:
            break
        }
    }

    private func initializeTransportStatistics(for peerId: String) {
        transportStatistics[peerId] = P2PTransportStatistics(
            peerId: peerId,
            connectionEstablishedAt: Date(),
            messagesSent: 0,
            messagesReceived: 0,
            bytesTransferred: 0,
            averageLatency: 0,
            isActive: true
        )
    }

    private func updateMessageSentStatistics(for peerId: String, bytes: Int64) {
        messagesSentCount[peerId, default: 0] += 1
        bytesTransferredCount[peerId, default: 0] += bytes
        updateTransportStatistics(for: peerId)
    }

    private func updateMessageReceivedStatistics(for peerId: String, bytes: Int64) {
        messagesReceivedCount[peerId, default: 0] += 1
        bytesTransferredCount[peerId, default: 0] += bytes
        updateTransportStatistics(for: peerId)
    }

    private func updateTransportStatistics(for peerId: String, remove: Bool = false) {
        if remove {
            transportStatistics.removeValue(forKey: peerId)
            messagesSentCount.removeValue(forKey: peerId)
            messagesReceivedCount.removeValue(forKey: peerId)
            bytesTransferredCount.removeValue(forKey: peerId)
            return
        }

        if var stats = transportStatistics[peerId] {
            stats.messagesSent = messagesSentCount[peerId] ?? 0
            stats.messagesReceived = messagesReceivedCount[peerId] ?? 0
            stats.bytesTransferred = bytesTransferredCount[peerId] ?? 0
            stats.isActive = activeConnections.contains(peerId)

            transportStatistics[peerId] = stats
        }
    }

    private func getCurrentUserId() -> String {
        // TODO: Get actual user ID from user session
        return "current_user_id"
    }
}

// MARK: - Supporting Types

/// P2P mesaj formatı
private struct P2PMessage: Codable {
    let messageId: String
    let senderId: String
    let recipientId: String
    let timestamp: Int64
    let messageType: String
    let content: Data
}

/// Mesaj chunk'ı
private struct MessageChunk: Codable {
    let messageId: String
    let chunkIndex: Int
    let totalChunks: Int
    let data: Data
}

/// Tamamlanmamış mesaj
private struct IncompleteMessage {
    let messageId: String
    let totalChunks: Int
    var chunks: [Int: Data]
    let receivedAt: Date
}

/// Decrypt edilmiş P2P mesajı
public struct DecryptedP2PMessage {
    public let messageId: String
    public let senderId: String
    public let content: Data
    public let messageType: MessageType
    public let timestamp: Date
    public let transportType: TransportType

    public init(messageId: String, senderId: String, content: Data, messageType: MessageType, timestamp: Date, transportType: TransportType) {
        self.messageId = messageId
        self.senderId = senderId
        self.content = content
        self.messageType = messageType
        self.timestamp = timestamp
        self.transportType = transportType
    }

    /// Mesaj içeriğini String olarak döndürür
    public var contentAsString: String {
        return String(data: content, encoding: .utf8) ?? ""
    }
}

/// Transport türü
public enum TransportType: String, CaseIterable {
    case p2p = "p2p"
    case signaling = "signaling"
    case relay = "relay"

    public var displayName: String {
        switch self {
        case .p2p:
            return "Doğrudan P2P"
        case .signaling:
            return "Signaling Relay"
        case .relay:
            return "Relay Server"
        }
    }
}

/// P2P transport istatistikleri
public struct P2PTransportStatistics {
    public let peerId: String
    public let connectionEstablishedAt: Date
    public var messagesSent: Int
    public var messagesReceived: Int
    public var bytesTransferred: Int64
    public var averageLatency: TimeInterval
    public var isActive: Bool

    public init(peerId: String, connectionEstablishedAt: Date, messagesSent: Int, messagesReceived: Int, bytesTransferred: Int64, averageLatency: TimeInterval, isActive: Bool) {
        self.peerId = peerId
        self.connectionEstablishedAt = connectionEstablishedAt
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.bytesTransferred = bytesTransferred
        self.averageLatency = averageLatency
        self.isActive = isActive
    }

    /// Connection uptime
    public var connectionDuration: TimeInterval {
        return Date().timeIntervalSince(connectionEstablishedAt)
    }

    /// Messages per minute rate
    public var messageRate: Double {
        let durationMinutes = connectionDuration / 60.0
        guard durationMinutes > 0 else { return 0 }
        return Double(messagesSent + messagesReceived) / durationMinutes
    }
}

/// Crypto service placeholder protocol (extended)
public protocol CryptoServiceProtocol {
    func encryptMessage(for recipientId: String, content: Data) async throws -> EncryptedEnvelope
    func decryptMessage(from senderId: String, envelope: EncryptedEnvelope) async throws -> Data
}

/// WebRTC ICE connection state extension
import WebRTC
extension RTCIceConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }
}