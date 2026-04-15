import Foundation
import Combine
import SecureChatCommon

/**
 * Offline mesaj kuyruğu yöneticisi.
 *
 * P2P bağlantısı olmadığında mesajları geçici olarak signaling server üzerinden
 * relay eder ve P2P bağlantı kurulduğunda kuyruktaki mesajları direkt iletir.
 *
 * Bu sınıf:
 * - Offline gönderilen mesajları kuyruklar
 * - P2P bağlantı kurulduğunda mesajları iletir
 * - Mesaj delivery durumlarını takip eder
 * - Retry logic ve exponential backoff sağlar
 */
@available(iOS 13.0, *)
public class MessageQueue: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var queueSize: Int = 0
    @Published public private(set) var queueStatus: QueueStatus = .idle

    // MARK: - Private Properties

    private let signalingClient: SignalingClient
    private let cryptoService: CryptoServiceProtocol?
    private var pendingMessages: [PendingMessage] = []
    private let queueQueue = DispatchQueue(label: "messageQueue", qos: .utility)

    // Retry configuration
    private let maxRetryCount = 5
    private let initialRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0

    // Active retry tasks
    private var retryTasks: [String: Task<Void, Never>] = [:]

    // Statistics
    private var totalMessagesQueued = 0
    private var totalMessagesDelivered = 0
    private var totalMessagesFailed = 0

    // MARK: - Initialization

    public init(signalingClient: SignalingClient, cryptoService: CryptoServiceProtocol? = nil) {
        self.signalingClient = signalingClient
        self.cryptoService = cryptoService

        // Monitor connection state to process queue
        signalingClient.$connectionState
            .sink { [weak self] state in
                if state == .connected {
                    self?.processQueue()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Methods

    /**
     * Mesajı kuyruğa ekler ve göndermeye çalışır.
     */
    public func queueMessage(
        recipientId: String,
        content: Data,
        messageType: MessageType = .text,
        priority: MessagePriority = .normal
    ) async throws {
        let message = PendingMessage(
            id: UUID().uuidString,
            recipientId: recipientId,
            content: content,
            messageType: messageType,
            priority: priority,
            timestamp: Date(),
            retryCount: 0
        )

        await addToQueue(message)
        totalMessagesQueued += 1

        // Immediate send attempt if connected
        if signalingClient.connectionState == .connected {
            await attemptSendMessage(message)
        }
    }

    /**
     * Belirli bir alıcı için kuyruktaki tüm mesajları döndürür.
     */
    public func getPendingMessages(for recipientId: String) async -> [PendingMessage] {
        return await withCheckedContinuation { continuation in
            queueQueue.async { [weak self] in
                let messages = self?.pendingMessages.filter { $0.recipientId == recipientId } ?? []
                continuation.resume(returning: messages)
            }
        }
    }

    /**
     * Kuyruktaki tüm mesajları temizler.
     */
    public func clearQueue() async {
        await withCheckedContinuation { continuation in
            queueQueue.async { [weak self] in
                self?.pendingMessages.removeAll()
                self?.retryTasks.values.forEach { $0.cancel() }
                self?.retryTasks.removeAll()

                DispatchQueue.main.async {
                    self?.queueSize = 0
                    self?.queueStatus = .idle
                }

                continuation.resume()
            }
        }
    }

    /**
     * Belirli bir mesajı kuyruktan kaldırır.
     */
    public func removeMessage(withId messageId: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            queueQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                let initialCount = self.pendingMessages.count
                self.pendingMessages.removeAll { $0.id == messageId }

                // Cancel retry task if exists
                self.retryTasks[messageId]?.cancel()
                self.retryTasks.removeValue(forKey: messageId)

                let removed = self.pendingMessages.count < initialCount

                DispatchQueue.main.async {
                    self.queueSize = self.pendingMessages.count
                    if self.pendingMessages.isEmpty {
                        self.queueStatus = .idle
                    }
                }

                continuation.resume(returning: removed)
            }
        }
    }

    /**
     * Kuyruk istatistiklerini döndürür.
     */
    public func getQueueStatistics() -> QueueStatistics {
        return QueueStatistics(
            totalQueued: totalMessagesQueued,
            totalDelivered: totalMessagesDelivered,
            totalFailed: totalMessagesFailed,
            currentQueueSize: queueSize,
            status: queueStatus
        )
    }

    // MARK: - Private Methods

    @MainActor
    private func addToQueue(_ message: PendingMessage) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            // Insert message maintaining priority order
            let insertIndex = self.pendingMessages.firstIndex { existingMessage in
                message.priority.rawValue > existingMessage.priority.rawValue
            } ?? self.pendingMessages.endIndex

            self.pendingMessages.insert(message, at: insertIndex)

            DispatchQueue.main.async {
                self.queueSize = self.pendingMessages.count
                self.queueStatus = .processing
            }
        }
    }

    private func processQueue() {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            for message in self.pendingMessages {
                Task { [weak self] in
                    await self?.attemptSendMessage(message)
                }
            }
        }
    }

    private func attemptSendMessage(_ message: PendingMessage) async {
        do {
            // Encrypt message if crypto service is available
            let messageToSend: SignalMessageProtocol

            if let cryptoService = cryptoService {
                // Encrypt the message content
                let encryptedContent = try await cryptoService.encryptMessage(
                    for: message.recipientId,
                    content: message.content
                )

                let envelope = try JSONEncoder().encode(encryptedContent)
                let encodedEnvelope = envelope.base64EncodedString()

                messageToSend = EncryptedMessageSignal(
                    senderId: getCurrentUserId(),
                    recipientId: message.recipientId,
                    timestamp: Int64(message.timestamp.timeIntervalSince1970 * 1000),
                    envelope: encodedEnvelope
                )
            } else {
                // Send as plain text (for debugging/testing only)
                let plainText = String(data: message.content, encoding: .utf8) ?? ""
                messageToSend = EncryptedMessageSignal(
                    senderId: getCurrentUserId(),
                    recipientId: message.recipientId,
                    timestamp: Int64(message.timestamp.timeIntervalSince1970 * 1000),
                    envelope: plainText
                )
            }

            // Attempt to send
            let success = signalingClient.sendSignal(messageToSend)

            if success {
                await handleMessageSuccess(message)
            } else {
                await handleMessageFailure(message, error: MessageQueueError.sendFailed)
            }

        } catch {
            await handleMessageFailure(message, error: error)
        }
    }

    private func handleMessageSuccess(_ message: PendingMessage) async {
        totalMessagesDelivered += 1

        _ = await removeMessage(withId: message.id)

        print("Message \(message.id) delivered successfully")
    }

    private func handleMessageFailure(_ message: PendingMessage, error: Error) async {
        let updatedMessage = PendingMessage(
            id: message.id,
            recipientId: message.recipientId,
            content: message.content,
            messageType: message.messageType,
            priority: message.priority,
            timestamp: message.timestamp,
            retryCount: message.retryCount + 1,
            lastError: error
        )

        if updatedMessage.retryCount >= maxRetryCount {
            totalMessagesFailed += 1
            _ = await removeMessage(withId: message.id)
            print("Message \(message.id) failed permanently after \(maxRetryCount) attempts")
            return
        }

        // Update message in queue
        await updateMessageInQueue(updatedMessage)

        // Schedule retry
        scheduleRetry(for: updatedMessage)
    }

    @MainActor
    private func updateMessageInQueue(_ message: PendingMessage) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            if let index = self.pendingMessages.firstIndex(where: { $0.id == message.id }) {
                self.pendingMessages[index] = message
            }
        }
    }

    private func scheduleRetry(for message: PendingMessage) {
        let retryDelay = min(
            initialRetryDelay * pow(2.0, Double(message.retryCount - 1)),
            maxRetryDelay
        )

        let retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                await self?.attemptSendMessage(message)
            } catch {
                // Task was cancelled
            }
        }

        retryTasks[message.id] = retryTask
    }

    private func getCurrentUserId() -> String {
        // TODO: Get actual user ID from user session or storage
        return "current_user_id"
    }
}

// MARK: - Supporting Types

/// Kuyruktaki bekleyen mesaj
public struct PendingMessage: Identifiable, Equatable {
    public let id: String
    public let recipientId: String
    public let content: Data
    public let messageType: MessageType
    public let priority: MessagePriority
    public let timestamp: Date
    public let retryCount: Int
    public let lastError: Error?

    public init(
        id: String,
        recipientId: String,
        content: Data,
        messageType: MessageType,
        priority: MessagePriority,
        timestamp: Date,
        retryCount: Int = 0,
        lastError: Error? = nil
    ) {
        self.id = id
        self.recipientId = recipientId
        self.content = content
        self.messageType = messageType
        self.priority = priority
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.lastError = lastError
    }

    public static func == (lhs: PendingMessage, rhs: PendingMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Mesaj türü
public enum MessageType: String, CaseIterable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case file = "file"
}

/// Mesaj önceliği
public enum MessagePriority: Int, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public var displayName: String {
        switch self {
        case .low:
            return "Düşük"
        case .normal:
            return "Normal"
        case .high:
            return "Yüksek"
        case .urgent:
            return "Acil"
        }
    }
}

/// Kuyruk durumu
public enum QueueStatus: String, CaseIterable {
    case idle = "idle"
    case processing = "processing"
    case paused = "paused"
    case error = "error"

    public var displayName: String {
        switch self {
        case .idle:
            return "Beklemede"
        case .processing:
            return "İşleniyor"
        case .paused:
            return "Duraklatıldı"
        case .error:
            return "Hata"
        }
    }
}

/// Kuyruk istatistikleri
public struct QueueStatistics {
    public let totalQueued: Int
    public let totalDelivered: Int
    public let totalFailed: Int
    public let currentQueueSize: Int
    public let status: QueueStatus

    public init(totalQueued: Int, totalDelivered: Int, totalFailed: Int, currentQueueSize: Int, status: QueueStatus) {
        self.totalQueued = totalQueued
        self.totalDelivered = totalDelivered
        self.totalFailed = totalFailed
        self.currentQueueSize = currentQueueSize
        self.status = status
    }

    /// Başarı oranı
    public var successRate: Double {
        guard totalQueued > 0 else { return 0.0 }
        return Double(totalDelivered) / Double(totalQueued)
    }

    /// Başarısızlık oranı
    public var failureRate: Double {
        guard totalQueued > 0 else { return 0.0 }
        return Double(totalFailed) / Double(totalQueued)
    }
}

/// MessageQueue hataları
public enum MessageQueueError: Error, LocalizedError {
    case sendFailed
    case encryptionFailed(String)
    case queueFull
    case invalidMessage
    case noConnection

    public var errorDescription: String? {
        switch self {
        case .sendFailed:
            return "Mesaj gönderilemedi"
        case .encryptionFailed(let reason):
            return "Şifreleme hatası: \(reason)"
        case .queueFull:
            return "Mesaj kuyruğu dolu"
        case .invalidMessage:
            return "Geçersiz mesaj"
        case .noConnection:
            return "Bağlantı yok"
        }
    }
}

/// Crypto service protocol (placeholder)
public protocol CryptoServiceProtocol {
    func encryptMessage(for recipientId: String, content: Data) async throws -> EncryptedEnvelope
}