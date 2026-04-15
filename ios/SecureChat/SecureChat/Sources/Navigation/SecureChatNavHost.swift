import SwiftUI

/// Ana navigasyon container'ı - tüm uygulama ekranlarını yönetir
public struct SecureChatNavHost: View {

    @StateObject private var navigationManager = NavigationManager()
    @State private var startDestination: SecureChatDestination = .conversations

    public init(startDestination: SecureChatDestination = .conversations) {
        self._startDestination = State(initialValue: startDestination)
    }

    public var body: some View {
        NavigationStack(path: $navigationManager.path) {
            destinationView(for: startDestination)
                .navigationDestination(for: SecureChatDestination.self) { destination in
                    destinationView(for: destination)
                }
        }
        .environmentObject(navigationManager)
        .tint(Color("AccentColor"))
    }

    @ViewBuilder
    private func destinationView(for destination: SecureChatDestination) -> some View {
        switch destination {
        case .conversations:
            ConversationsView()

        case .chat(let conversationId):
            ChatView(conversationId: conversationId)

        case .contacts:
            ContactsView()

        case .createGroup:
            CreateGroupView()

        case .call(let peerId, let callType):
            CallView(peerId: peerId, callType: callType)

        case .settings:
            SettingsView()

        case .safetyNumber(let peerId, let peerName):
            SafetyNumberView(peerId: peerId, peerName: peerName)

        case .phoneVerification:
            PhoneVerificationView()

        case .otpVerification(let phoneNumber):
            OtpVerificationView(phoneNumber: phoneNumber)
        }
    }
}

// MARK: - Preview

#Preview {
    SecureChatNavHost(startDestination: .conversations)
}