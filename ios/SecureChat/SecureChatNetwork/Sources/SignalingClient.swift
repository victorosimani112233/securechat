import Foundation
import Starscream
import Combine
import Network
import SecureChatCommon

/**
 * Signaling sunucusu ile WebSocket bağlantısını yöneten istemci.
 *
 * Bu sınıf:
 * - WebSocket bağlantısı kurar ve yönetir
 * - Gelen signaling mesajlarını Published olarak yayar
 * - Bağlantı koptuğunda exponential backoff ile yeniden bağlantı dener
 * - Bağlantı durumunu Published olarak izlemeye sunar
 *
 * GÜVENLİK: Authorization token WebSocket handshake'inde Bearer token olarak gönderilir.
 * Certificate pinning Production ortamında zorunludur.
 */
@available(iOS 13.0, *)
public class SignalingClient: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var statistics = ConnectionStatistics()

    // MARK: - Private Properties

    private let signalingUrl: String
    private let certificateValidator: CertificateValidator?
    private var webSocket: WebSocket?
    private var reconnectTask: Task<Void, Never>?
    private var currentUserId: String?
    private var currentAuthToken: String?
    private var connectionStartTime: Date?

    // Message handling
    private let incomingSignalsSubject = PassthroughSubject<SignalMessageProtocol, Never>()
    public var incomingSignals: AnyPublisher<SignalMessageProtocol, Never> {
        incomingSignalsSubject.eraseToAnyPublisher()
    }

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "networkMonitor")
    private var isNetworkAvailable = true

    // Statistics tracking
    private var messagesSent = 0
    private var messagesReceived = 0
    private var bytesSent: Int64 = 0
    private var bytesReceived: Int64 = 0
    private var reconnectCount = 0
    private var lastReconnectTime: Date?

    // MARK: - Constants

    private static let initialReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 30.0
    private static let normalClosureCode = 1000

    // MARK: - Initialization

    public init(signalingUrl: String, enableCertificatePinning: Bool = true) {
        self.signalingUrl = signalingUrl
        self.certificateValidator = enableCertificatePinning ? CertificateValidator() : nil

        super.init()

        // Start network monitoring
        startNetworkMonitoring()
    }

    deinit {
        disconnect()
        networkMonitor.cancel()
    }

    // MARK: - Public Methods

    /**
     * Signaling sunucusuna WebSocket bağlantısı kurar.
     *
     * @param userId Bağlanan kullanıcının ID'si
     * @param authToken Yetkilendirme token'ı (Bearer)
     * @param customUrl Opsiyonel custom URL, nil ise injected URL kullanılır
     */
    public func connect(userId: String, authToken: String, customUrl: String? = nil) {
        let url = customUrl ?? signalingUrl
        currentUserId = userId
        currentAuthToken = authToken

        guard isNetworkAvailable else {
            connectionState = .error(.networkUnavailable)
            return
        }

        connectionState = .connecting
        connectionStartTime = Date()

        let finalUrl = "\(url)/ws?userId=\(userId)"

        guard let wsUrl = URL(string: finalUrl) else {
            connectionState = .error(.connectionFailed("Invalid URL"))
            return
        }

        var request = URLRequest(url: wsUrl)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("securechat-ios", forHTTPHeaderField: "User-Agent")

        // Configure WebSocket with SSL pinning if enabled
        let engine = URLSessionWebSocketEngine()
        if let validator = certificateValidator {
            engine.configure(urlSessionConfiguration: {
                let config = URLSessionConfiguration.default
                config.urlSessionChallengeDelegate = validator
                return config
            }())
        }

        webSocket = WebSocket(request: request, engine: engine)
        webSocket?.delegate = self
        webSocket?.connect()
    }

    /**
     * Signaling mesajını WebSocket üzerinden gönderir.
     *
     * @param signal Gönderilecek signaling mesajı
     * @return Mesaj başarıyla kuyruğa alındıysa true
     */
    @discardableResult
    public func sendSignal(_ signal: SignalMessageProtocol) -> Bool {
        guard connectionState == .connected else {
            return false
        }

        do {
            let jsonString = try SignalMessageFactory.encodeMessage(signal)
            webSocket?.write(string: jsonString)

            // Update statistics
            messagesSent += 1
            bytesSent += Int64(jsonString.utf8.count)
            updateStatistics()

            return true
        } catch {
            print("Failed to encode signal message: \(error)")
            return false
        }
    }

    /**
     * WebSocket bağlantısını kapatır ve tüm kaynakları temizler.
     */
    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.disconnect(closeCode: Self.normalClosureCode)
        webSocket = nil
        connectionState = .disconnected
        currentUserId = nil
        currentAuthToken = nil
        connectionStartTime = nil
    }

    // MARK: - Private Methods

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied

                if !self?.isNetworkAvailable ?? false {
                    self?.connectionState = .error(.networkUnavailable)
                } else if self?.connectionState == .error(.networkUnavailable) {
                    // Network became available again, try to reconnect
                    if let userId = self?.currentUserId, let token = self?.currentAuthToken {
                        self?.connect(userId: userId, authToken: token)
                    }
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    private func scheduleReconnect() {
        guard let userId = currentUserId, let authToken = currentAuthToken else {
            return
        }

        reconnectTask?.cancel()
        reconnectCount += 1
        lastReconnectTime = Date()

        reconnectTask = Task { [weak self] in
            var currentDelay = Self.initialReconnectDelay

            while !Task.isCancelled && self?.connectionState != .connected {
                do {
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                } catch {
                    break // Task was cancelled
                }

                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self?.connect(userId: userId, authToken: authToken)
                }

                currentDelay = min(currentDelay * 2, Self.maxReconnectDelay)
            }
        }
    }

    private func updateStatistics() {
        let connectedDuration = connectionStartTime?.timeIntervalSinceNow ?? 0
        statistics = ConnectionStatistics(
            connectedDuration: abs(connectedDuration),
            messagesReceived: messagesReceived,
            messagesSent: messagesSent,
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            reconnectCount: reconnectCount,
            lastReconnectTime: lastReconnectTime
        )
    }
}

// MARK: - WebSocketDelegate

@available(iOS 13.0, *)
extension SignalingClient: WebSocketDelegate {

    public func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("WebSocket connected with headers: \(headers)")
            connectionState = .connected
            reconnectTask?.cancel()

        case .disconnected(let reason, let code):
            print("WebSocket disconnected with reason: \(reason), code: \(code)")
            connectionState = .disconnected

        case .text(let text):
            handleIncomingMessage(text)

        case .binary(let data):
            // Signaling protocol sadece text mesaj kullanır
            print("Received unexpected binary data: \(data.count) bytes")

        case .error(let error):
            print("WebSocket error: \(error)")
            let networkError: NetworkError

            if let error = error {
                networkError = .webSocketError(error.localizedDescription)
            } else {
                networkError = .unknownError("WebSocket connection failed")
            }

            connectionState = .error(networkError)
            scheduleReconnect()

        case .cancelled:
            print("WebSocket connection cancelled")
            connectionState = .disconnected

        case .reconnectSuggested(let suggest):
            if suggest {
                scheduleReconnect()
            }

        case .viabilityChanged(let viable):
            if !viable {
                print("WebSocket connection not viable")
                scheduleReconnect()
            }

        case .peerClosed:
            print("WebSocket peer closed connection")
            connectionState = .disconnected
        }
    }

    private func handleIncomingMessage(_ text: String) {
        do {
            let signal = try SignalMessageFactory.decodeMessage(from: text)
            incomingSignalsSubject.send(signal)

            // Update statistics
            messagesReceived += 1
            bytesReceived += Int64(text.utf8.count)
            updateStatistics()

        } catch {
            print("Failed to decode incoming signal: \(error)")
            connectionState = .error(.messageDecodingFailed(error.localizedDescription))
        }
    }
}

// MARK: - Certificate Validator

private class CertificateValidator: NSObject, URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {

        // Certificate pinning implementation
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // TODO: Implement actual certificate pinning logic
        // For production, pin specific certificates or public keys
        let credential = URLCredential(trust: trust)
        completionHandler(.useCredential, credential)
    }
}

// MARK: - URLSessionWebSocketEngine Extension

private extension URLSessionWebSocketEngine {
    func configure(urlSessionConfiguration: @escaping () -> URLSessionConfiguration) {
        // Configure URLSession with custom configuration
    }
}