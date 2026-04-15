import SwiftUI
import Foundation

// MARK: - Navigation Destinations

/// Uygulama içi navigasyon hedefleri
public enum SecureChatDestination: Hashable {
    case conversations
    case chat(conversationId: String)
    case contacts
    case createGroup
    case call(peerId: String, callType: CallType)
    case settings
    case safetyNumber(peerId: String, peerName: String)
    case phoneVerification
    case otpVerification(phoneNumber: String)
}

// MARK: - Navigation Path Manager

/// Navigasyon yolunu yöneten ObservableObject
@MainActor
public class NavigationManager: ObservableObject {
    @Published public var path = NavigationPath()

    public init() {}

    /// Belirtilen hedeffe navigasyon yap
    public func navigate(to destination: SecureChatDestination) {
        path.append(destination)
    }

    /// Bir önceki ekrana dön
    public func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Ana ekrana dön
    public func goToRoot() {
        path.removeLast(path.count)
    }

    /// Belirli bir hedefe git ve tüm yolu temizle
    public func navigateAndClearStack(to destination: SecureChatDestination) {
        path.removeLast(path.count)
        path.append(destination)
    }
}

// MARK: - Navigation Extensions

extension NavigationManager {
    /// Yeni sohbet başlat
    public func startNewChat() {
        navigate(to: .contacts)
    }

    /// Sohbet ekranına git
    public func openChat(conversationId: String) {
        navigate(to: .chat(conversationId: conversationId))
    }

    /// Sesli arama başlat
    public func startVoiceCall(with peerId: String) {
        navigate(to: .call(peerId: peerId, callType: .voice))
    }

    /// Görüntülü arama başlat
    public func startVideoCall(with peerId: String) {
        navigate(to: .call(peerId: peerId, callType: .video))
    }

    /// Ayarlar ekranını aç
    public func openSettings() {
        navigate(to: .settings)
    }

    /// Güvenlik numarası doğrulama ekranını aç
    public func openSafetyNumber(for peerId: String, peerName: String) {
        navigate(to: .safetyNumber(peerId: peerId, peerName: peerName))
    }

    /// Kimlik doğrulama akışını başlat
    public func startAuthentication() {
        navigateAndClearStack(to: .phoneVerification)
    }

    /// Ana uygulama akışını başlat
    public func startMainFlow() {
        navigateAndClearStack(to: .conversations)
    }
}