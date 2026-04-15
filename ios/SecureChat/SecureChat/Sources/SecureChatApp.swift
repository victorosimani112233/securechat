import SwiftUI

/// SecureChat iOS uygulamasının ana giriş noktası
@main
public struct SecureChatApp: App {

    @StateObject private var navigationManager = NavigationManager()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            SecureChatNavHost(startDestination: determineStartDestination())
                .environmentObject(navigationManager)
                .preferredColorScheme(getColorScheme())
                .onAppear {
                    configureApp()
                }
        }
    }

    // MARK: - Private Methods

    private func determineStartDestination() -> SecureChatDestination {
        // Kullanıcının daha önce giriş yapıp yapmadığını kontrol et
        let isUserLoggedIn = UserDefaults.standard.bool(forKey: "user_logged_in")

        if isUserLoggedIn {
            return .conversations
        } else {
            return .phoneVerification
        }
    }

    private func getColorScheme() -> ColorScheme? {
        let isDarkModeEnabled = UserDefaults.standard.bool(forKey: "dark_mode_enabled")

        if isDarkModeEnabled {
            return .dark
        } else {
            return nil // Sistem ayarını kullan
        }
    }

    private func configureApp() {
        // Uygulama başlatma yapılandırmaları
        configureSecuritySettings()
        configureNotifications()
    }

    private func configureSecuritySettings() {
        // Ekran görüntüsü alma koruması
        #if !DEBUG
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Ekran görüntüsü alındığında uyarı göster
            showScreenshotAlert()
        }
        #endif
    }

    private func configureNotifications() {
        // Push notification izni iste
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                UserDefaults.standard.set(granted, forKey: "notifications_enabled")
            }
        }
    }

    private func showScreenshotAlert() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: "Güvenlik Uyarısı",
            message: "Ekran görüntüsü alınması güvenlik açısından önerilmez. Kişisel bilgilerinizi korumaya dikkat edin.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Tamam", style: .default))

        rootViewController.present(alert, animated: true)
    }
}

// MARK: - User Notification Extensions

import UserNotifications

extension UNUserNotificationCenter {
    /// Bildirim izni durumunu kontrol et
    func checkNotificationPermission() async -> Bool {
        let settings = await notificationSettings()
        return settings.authorizationStatus == .authorized
    }
}