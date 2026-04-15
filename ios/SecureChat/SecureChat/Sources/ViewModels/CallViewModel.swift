import SwiftUI
import Combine
import SecureChatMedia
import SecureChatNetwork

/// Arama ekranı ViewModel'i.
/// WebRTC arama oturumunu ve arama kontrollerini yönetir.
@MainActor
public class CallViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var uiState = CallUIState()
    @Published public var callSession: CallSession?
    @Published public var callDuration: TimeInterval = 0

    // MARK: - Private Properties

    private let peerId: String
    private let callType: CallType
    private let callManager: CallManager
    private var cancellables = Set<AnyCancellable>()
    private var durationTimer: Timer?

    // MARK: - Initialization

    public init(peerId: String, callType: CallType,
               callManager: CallManager = CallManager.shared) {
        self.peerId = peerId
        self.callType = callType
        self.callManager = callManager

        uiState.isVideoCall = (callType == .video)
        setupSubscriptions()
        initiateCall()
    }

    // MARK: - Public Methods

    /// Aramayı sonlandır
    public func endCall() {
        Task {
            await callManager.endCall()
            stopDurationTimer()
        }
    }

    /// Ses kapatma/açma
    public func toggleMute() {
        Task {
            await callManager.toggleMute()
        }
    }

    /// Hoparlör kapatma/açma
    public func toggleSpeaker() {
        Task {
            await callManager.toggleSpeaker()
        }
    }

    /// Kamera kapatma/açma (görüntülü aramada)
    public func toggleCamera() {
        guard callType == .video else { return }

        Task {
            await callManager.toggleCamera()
        }
    }

    /// Kamera değiştirme (ön/arka)
    public func switchCamera() {
        guard callType == .video else { return }

        Task {
            await callManager.switchCamera()
        }
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        // Arama durumunu dinle
        callManager.currentCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in
                self?.updateCallSession(call)
            }
            .store(in: &cancellables)
    }

    private func initiateCall() {
        Task {
            do {
                try await callManager.startCall(to: peerId, type: callType)
                startDurationTimer()
            } catch {
                print("Arama başlatılırken hata oluştu: \(error)")
            }
        }
    }

    private func updateCallSession(_ call: Call?) {
        guard let call = call else {
            self.callSession = nil
            self.uiState.callSession = nil
            return
        }

        let session = CallSession(
            id: call.id,
            peerId: call.peerId,
            peerName: call.peerName,
            type: call.type,
            state: call.state,
            startTime: call.startTime,
            isMuted: call.isMuted,
            isSpeakerOn: call.isSpeakerOn,
            isCameraEnabled: call.isCameraEnabled
        )

        self.callSession = session
        self.uiState.callSession = session
        self.uiState.isMuted = call.isMuted
        self.uiState.isSpeakerOn = call.isSpeakerOn
        self.uiState.isCameraEnabled = call.isCameraEnabled

        // Arama aktif olduğunda timer'ı başlat
        if call.state == .active {
            startDurationTimer()
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.callSession?.startTime else { return }

            let duration = Date().timeIntervalSince(startTime)
            self.callDuration = duration
            self.uiState.callDuration = duration
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    deinit {
        stopDurationTimer()
    }
}

// MARK: - Extensions

extension CallViewModel {
    /// Arama süresini formatla
    public var formattedDuration: String {
        let minutes = Int(callDuration) / 60
        let seconds = Int(callDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Arama durumu metni
    public var callStateText: String {
        guard let state = callSession?.state else { return "" }

        switch state {
        case .ringing:
            return "Aranıyor..."
        case .connecting:
            return "Bağlanıyor..."
        case .active:
            return formattedDuration
        case .reconnecting:
            return "Yeniden bağlanıyor..."
        case .ended:
            return "Arama sona erdi"
        }
    }
}