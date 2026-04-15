import SwiftUI
import Combine

/// Ayarlar ekranı ViewModel'i.
/// Kullanıcı tercihlerini ve uygulama ayarlarını yönetir.
@MainActor
public class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var uiState = SettingsUIState()

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        loadUserProfile()
        loadSettings()
    }

    // MARK: - Public Methods

    /// Bildirim ayarını değiştir
    public func toggleNotifications() {
        uiState.isNotificationsEnabled.toggle()
        saveNotificationSetting()
    }

    /// Biyometrik kilidi ayarını değiştir
    public func toggleBiometrics() {
        uiState.isBiometricsEnabled.toggle()
        saveBiometricSetting()
    }

    /// Tema ayarını değiştir
    public func updateTheme(_ isDark: Bool) {
        uiState.isDarkMode = isDark
        saveThemeSetting()
    }

    /// Kullanıcı profilini güncelle
    public func updateUserProfile(name: String? = nil, phoneNumber: String? = nil) {
        guard var profile = uiState.userProfile else { return }

        if let name = name {
            profile = UserProfile(
                id: profile.id,
                name: name,
                phoneNumber: profile.phoneNumber,
                profileImageUrl: profile.profileImageUrl
            )
        }

        if let phoneNumber = phoneNumber {
            profile = UserProfile(
                id: profile.id,
                name: profile.name,
                phoneNumber: phoneNumber,
                profileImageUrl: profile.profileImageUrl
            )
        }

        uiState.userProfile = profile
        saveUserProfile()
    }

    /// Uygulama verilerini temizle
    public func clearAppData() {
        // TODO: Tüm uygulama verilerini temizle
        // Bu işlem kullanıcıyı oturum açma ekranına yönlendirir
    }

    /// Uygulamayı paylaş
    public func shareApp() {
        let shareText = """
        SecureChat - Güvenli Mesajlaşma Uygulaması

        Uçtan uca şifreli, güvenli mesajlaşma için SecureChat'i deneyin!
        """

        let activityViewController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true)
        }
    }

    // MARK: - Private Methods

    private func loadUserProfile() {
        // Simüle edilmiş kullanıcı profili yükleme
        // Gerçek implementasyonda UserDefaults veya Keychain'den gelecek
        uiState.userProfile = UserProfile(
            id: "current_user_id",
            name: "Kullanıcı Adı",
            phoneNumber: "+90 555 123 4567",
            profileImageUrl: nil
        )
    }

    private func loadSettings() {
        // Simüle edilmiş ayar yükleme
        uiState.isNotificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
        uiState.isBiometricsEnabled = UserDefaults.standard.bool(forKey: "biometrics_enabled")
        uiState.isDarkMode = UserDefaults.standard.bool(forKey: "dark_mode_enabled")
    }

    private func saveNotificationSetting() {
        UserDefaults.standard.set(uiState.isNotificationsEnabled, forKey: "notifications_enabled")
    }

    private func saveBiometricSetting() {
        UserDefaults.standard.set(uiState.isBiometricsEnabled, forKey: "biometrics_enabled")
    }

    private func saveThemeSetting() {
        UserDefaults.standard.set(uiState.isDarkMode, forKey: "dark_mode_enabled")
    }

    private func saveUserProfile() {
        // TODO: Kullanıcı profilini kaydet
    }
}