import Foundation
import SwiftUI
import Combine
import CallKit

/**
 * CallManager kullanım örneği - SwiftUI entegrasyonu.
 *
 * Bu dosya, CallManager'ın gerçek bir SwiftUI uygulamasında
 * nasıl kullanılacağını gösteren örnek implementasyon içerir.
 */

// MARK: - Example SwiftUI Views

/**
 * Ana arama arayüzü - active call için
 */
struct ActiveCallView: View {
    @ObservedObject var callManager: CallManager
    @State private var callTimer: Timer?

    var body: some View {
        VStack(spacing: 30) {
            // Caller info
            VStack(spacing: 8) {
                AsyncImage(url: URL(string: "https://api.example.com/avatar/\(callManager.currentSession?.peerId ?? "")")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())

                Text(callManager.currentSession?.peerId ?? "Unknown")
                    .font(.title2)
                    .fontWeight(.medium)

                Text(callManager.currentSession?.callKitStatusText ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Video view (for video calls)
            if callManager.currentSession?.callType == .video {
                VideoCallView(callManager: callManager)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            }

            Spacer()

            // Call controls
            CallControlsView(callManager: callManager)
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
        .onAppear {
            startCallTimer()
        }
        .onDisappear {
            stopCallTimer()
        }
    }

    private func startCallTimer() {
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Force UI update for duration display
            callManager.objectWillChange.send()
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
}

/**
 * Arama kontrolleri
 */
struct CallControlsView: View {
    @ObservedObject var callManager: CallManager

    var body: some View {
        HStack(spacing: 40) {
            // Mute button
            CallControlButton(
                icon: callManager.currentSession?.isMuted ?? false ? "mic.slash.fill" : "mic.fill",
                isActive: callManager.currentSession?.isMuted ?? false,
                color: .primary
            ) {
                callManager.toggleMute()
            }

            // Speaker button
            CallControlButton(
                icon: speakerIcon,
                isActive: callManager.currentSession?.isSpeakerOn ?? false,
                color: .blue
            ) {
                callManager.toggleSpeaker()
            }

            // Camera button (video calls only)
            if callManager.currentSession?.callType == .video {
                CallControlButton(
                    icon: callManager.currentSession?.isCameraEnabled ?? false ? "video.fill" : "video.slash.fill",
                    isActive: callManager.currentSession?.isCameraEnabled ?? false,
                    color: .primary
                ) {
                    callManager.toggleCamera()
                }

                // Camera flip button
                if callManager.currentSession?.isCameraEnabled ?? false {
                    CallControlButton(
                        icon: "camera.rotate.fill",
                        isActive: false,
                        color: .primary
                    ) {
                        try? callManager.switchCamera()
                    }
                }
            }

            // End call button
            CallControlButton(
                icon: "phone.down.fill",
                isActive: false,
                color: .red
            ) {
                Task {
                    await callManager.endCall()
                }
            }
        }
    }

    private var speakerIcon: String {
        switch callManager.audioRoute {
        case .speaker:
            return "speaker.wave.3.fill"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .headphones:
            return "headphones"
        case .receiver:
            return "phone.fill"
        }
    }
}

/**
 * Tek bir arama kontrol butonu
 */
struct CallControlButton: View {
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(isActive ? color : Color.gray.opacity(0.3))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/**
 * Video arama için video view
 */
struct VideoCallView: View {
    @ObservedObject var callManager: CallManager

    var body: some View {
        ZStack {
            // Remote video (background)
            RemoteVideoView()
                .clipped()

            // Local video (picture-in-picture)
            VStack {
                HStack {
                    Spacer()
                    LocalVideoView()
                        .frame(width: 120, height: 160)
                        .cornerRadius(8)
                        .padding()
                }
                Spacer()
            }
        }
    }
}

/**
 * Remote video renderer placeholder
 * Gerçek implementasyonda WebRTC RTCVideoRenderer kullanılacak
 */
struct RemoteVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray6

        // WebRTC RTCEAGLVideoView burada kullanılacak
        // let videoView = RTCEAGLVideoView()
        // view.addSubview(videoView)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Video stream updates
    }
}

/**
 * Local video renderer placeholder
 */
struct LocalVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray5
        view.layer.cornerRadius = 8

        // WebRTC local video track burada render edilecek

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Local video updates
    }
}

/**
 * Gelen arama arayüzü (full-screen)
 */
struct IncomingCallView: View {
    @ObservedObject var callManager: CallManager
    let callSession: CallSession

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Caller info
            VStack(spacing: 16) {
                AsyncImage(url: URL(string: "https://api.example.com/avatar/\(callSession.peerId)")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 40))
                        )
                }
                .frame(width: 150, height: 150)
                .clipShape(Circle())

                Text(callSession.peerId)
                    .font(.largeTitle)
                    .fontWeight(.medium)

                Text(callSession.callType == .video ? "Video Arama" : "Sesli Arama")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("Gelen Arama")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Answer/Decline buttons
            HStack(spacing: 80) {
                // Decline button
                Button {
                    Task {
                        await callManager.rejectCall()
                    }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Color.red)
                        .clipShape(Circle())
                }

                // Accept button
                Button {
                    Task {
                        try? await callManager.acceptCall()
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
    }
}

// MARK: - Example Integration Service

/**
 * CallManager'ı diğer servislerle entegre eden örnek servis
 */
@MainActor
class CallService: ObservableObject {
    private let callManager: CallManager
    private let contactsService: ContactsService
    private var cancellables = Set<AnyCancellable>()

    @Published var currentCallSession: CallSession?
    @Published var incomingCall: CallSession?
    @Published var callHistory: [CallHistoryEntry] = []

    init(callManager: CallManager, contactsService: ContactsService) {
        self.callManager = callManager
        self.contactsService = contactsService

        setupBindings()
        setupSignalingHandlers()
    }

    private func setupBindings() {
        // Call session changes
        callManager.$currentSession
            .assign(to: \.currentCallSession, on: self)
            .store(in: &cancellables)

        // Incoming call detection
        callManager.$currentSession
            .compactMap { $0 }
            .filter { $0.direction == .incoming && $0.state == .ringing }
            .assign(to: \.incomingCall, on: self)
            .store(in: &cancellables)

        // Call ended - add to history
        callManager.$currentSession
            .compactMap { $0 }
            .filter { $0.state == .ended }
            .sink { [weak self] session in
                self?.addToCallHistory(session)
            }
            .store(in: &cancellables)
    }

    private func setupSignalingHandlers() {
        // Network service'dan gelen signaling mesajlarını handle et
        // Bu kısım NetworkService ile entegre edilecek

        // Example:
        // networkService.signalingMessages
        //     .compactMap { $0 as? SdpOfferMessage }
        //     .sink { [weak self] offer in
        //         Task { @MainActor in
        //             await self?.handleIncomingCall(offer)
        //         }
        //     }
        //     .store(in: &cancellables)
    }

    // MARK: - Public API

    func startCall(to peerId: String, type: CallType) async throws {
        try await callManager.initiateCall(
            to: peerId,
            callType: type,
            userId: getCurrentUserId()
        )
    }

    func acceptIncomingCall() async throws {
        try await callManager.acceptCall()
        incomingCall = nil
    }

    func declineIncomingCall() async {
        await callManager.rejectCall()
        incomingCall = nil
    }

    func endCurrentCall() async {
        await callManager.endCall()
    }

    // MARK: - Private Methods

    private func handleIncomingCall(_ offer: SdpOfferMessage) async {
        await callManager.handleIncomingCall(offer, currentUserId: getCurrentUserId())
    }

    private func addToCallHistory(_ session: CallSession) {
        let entry = CallHistoryEntry(
            id: session.callId,
            peerId: session.peerId,
            peerName: contactsService.getName(for: session.peerId),
            callType: session.callType,
            direction: session.direction,
            duration: session.duration ?? 0,
            timestamp: Date(),
            wasSuccessful: session.state == .ended
        )

        callHistory.insert(entry, at: 0)

        // Limit history to 100 entries
        if callHistory.count > 100 {
            callHistory = Array(callHistory.prefix(100))
        }
    }

    private func getCurrentUserId() -> String {
        // UserSession'dan alınacak
        return "current-user-id"
    }
}

// MARK: - Supporting Types

struct CallHistoryEntry: Identifiable {
    let id: String
    let peerId: String
    let peerName: String?
    let callType: CallType
    let direction: CallDirection
    let duration: TimeInterval
    let timestamp: Date
    let wasSuccessful: Bool
}

protocol ContactsService {
    func getName(for peerId: String) -> String?
}

// MARK: - Example Usage in App

/*
// App.swift
@main
struct SecureChatApp: App {
    @StateObject private var networkService = NetworkService(...)
    @StateObject private var callManager: CallManager
    @StateObject private var callService: CallService

    init() {
        let network = NetworkService(...)
        let callMgr = CallManager(networkService: network)
        let contacts = ContactsServiceImpl()
        let callSvc = CallService(callManager: callMgr, contactsService: contacts)

        self._networkService = StateObject(wrappedValue: network)
        self._callManager = StateObject(wrappedValue: callMgr)
        self._callService = StateObject(wrappedValue: callSvc)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(callService)
                .environmentObject(callManager)
                .fullScreenCover(item: $callService.incomingCall) { call in
                    IncomingCallView(callManager: callManager, callSession: call)
                }
                .fullScreenCover(item: $callService.currentCallSession) { call in
                    if call.state == .active || call.state == .connecting {
                        ActiveCallView(callManager: callManager)
                    }
                }
        }
    }
}
*/