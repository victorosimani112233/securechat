import SwiftUI

/// Arama ekranı
/// WebRTC arama oturumunu yönetir, ses/görüntülü arama kontrollerini sağlar
public struct CallView: View {

    let peerId: String
    let callType: CallType

    @StateObject private var viewModel: CallViewModel
    @EnvironmentObject private var navigationManager: NavigationManager
    @Environment(\.scenePhase) private var scenePhase

    public init(peerId: String, callType: CallType) {
        self.peerId = peerId
        self.callType = callType
        self._viewModel = StateObject(wrappedValue: CallViewModel(peerId: peerId, callType: callType))
    }

    public var body: some View {
        ZStack {
            // Arka plan
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.blue.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                // Arama bilgileri
                callInfoView

                Spacer()

                // Arama kontrolleri
                callControlsView
                    .padding(.bottom, 60)
            }

            // Video görünüm (görüntülü aramada)
            if callType == .video && viewModel.callSession?.state == .active {
                videoView
            }
        }
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .callEnded)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                navigationManager.goBack()
            }
        }
        .onChange(of: viewModel.callSession?.state) { state in
            if state == .ended {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    navigationManager.goBack()
                }
            }
        }
    }

    // MARK: - Call Info View

    private var callInfoView: some View {
        VStack(spacing: 16) {
            // Avatar
            GradientAvatar(
                name: viewModel.callSession?.peerName ?? peerId,
                size: 120
            )
            .shadow(color: .black.opacity(0.3), radius: 10)

            // İsim
            Text(viewModel.callSession?.peerName ?? peerId)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            // Durum
            Text(viewModel.callStateText)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Call Controls

    private var callControlsView: some View {
        HStack(spacing: 40) {
            // Ses kapatma
            CallControlButton(
                icon: viewModel.uiState.isMuted ? "mic.slash.fill" : "mic.fill",
                backgroundColor: viewModel.uiState.isMuted ? .red : .white.opacity(0.3),
                foregroundColor: viewModel.uiState.isMuted ? .white : .white
            ) {
                viewModel.toggleMute()
            }

            // Hoparlör (sadece sesli aramada)
            if callType == .voice {
                CallControlButton(
                    icon: viewModel.uiState.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                    backgroundColor: viewModel.uiState.isSpeakerOn ? .blue : .white.opacity(0.3),
                    foregroundColor: .white
                ) {
                    viewModel.toggleSpeaker()
                }
            }

            // Kamera kontrolü (sadece görüntülü aramada)
            if callType == .video {
                CallControlButton(
                    icon: viewModel.uiState.isCameraEnabled ? "video.fill" : "video.slash.fill",
                    backgroundColor: viewModel.uiState.isCameraEnabled ? .white.opacity(0.3) : .red,
                    foregroundColor: .white
                ) {
                    viewModel.toggleCamera()
                }

                CallControlButton(
                    icon: "camera.rotate.fill",
                    backgroundColor: .white.opacity(0.3),
                    foregroundColor: .white
                ) {
                    viewModel.switchCamera()
                }
            }

            // Aramayı sonlandır
            CallControlButton(
                icon: "phone.down.fill",
                backgroundColor: .red,
                foregroundColor: .white,
                size: 64
            ) {
                viewModel.endCall()
            }
        }
    }

    // MARK: - Video View

    private var videoView: some View {
        ZStack {
            // Remote video (tam ekran)
            Rectangle()
                .fill(Color.black)
                .overlay {
                    Text("Video Stream")
                        .foregroundColor(.white)
                        .font(.title2)
                }

            // Local video (küçük pencere, sağ üst)
            VStack {
                HStack {
                    Spacer()

                    Rectangle()
                        .fill(Color.gray.opacity(0.8))
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            Text("Siz")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                        .shadow(radius: 10)
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Call Control Button

/// Arama kontrol butonu
struct CallControlButton: View {
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    let size: CGFloat
    let action: () -> Void

    init(icon: String, backgroundColor: Color, foregroundColor: Color,
         size: CGFloat = 56, action: @escaping () -> Void) {
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .buttonStyle(CallButtonStyle())
    }
}

// MARK: - Call Button Style

struct CallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let callEnded = Notification.Name("callEnded")
}

// MARK: - Preview

#Preview("Voice Call") {
    CallView(peerId: "sample-peer", callType: .voice)
        .environmentObject(NavigationManager())
}

#Preview("Video Call") {
    CallView(peerId: "sample-peer", callType: .video)
        .environmentObject(NavigationManager())
}