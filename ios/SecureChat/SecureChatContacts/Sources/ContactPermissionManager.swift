import Foundation
import Contacts

/// iOS Contacts framework izin yönetimi.
/// CNContactStore'dan izin durumunu kontrol eder ve gerekli durumlarda izin ister.
public final class ContactPermissionManager: @unchecked Sendable {

    // MARK: - Properties

    private let contactStore: CNContactStore

    // MARK: - Initialization

    public init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    // MARK: - Permission Status

    /// Mevcut izin durumunu döner
    public var permissionStatus: ContactPermissionStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    /// İzin var mı kontrol eder
    public var hasPermission: Bool {
        return permissionStatus.isAuthorized
    }

    // MARK: - Permission Request

    /// Rehber iznini talep eder
    /// - Returns: İzin verildi mi
    @MainActor
    public func requestPermission() async -> Bool {
        // Zaten izin varsa true döner
        if hasPermission {
            return true
        }

        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            return granted
        } catch {
            print("SecureChat: Contact permission request failed: \(error)")
            return false
        }
    }

    /// İzin durumunu kontrol eder, yoksa talep eder
    /// - Returns: İzin durumu (true: izin var, false: izin yok)
    @MainActor
    public func ensurePermission() async -> Bool {
        switch permissionStatus {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await requestPermission()
        }
    }

    // MARK: - Settings Navigation

    /// Kullanıcıyı ayarlar uygulamasına yönlendirir
    /// İzin reddedildiğinde kullanılır
    public func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }

    // MARK: - Permission Status Updates

    /// İzin durumu değişikliklerini dinlemek için NotificationCenter kullanır
    /// iOS'ta CNContactStore değişiklik bildirimi sağlamaz, bu nedenle app foreground'a geldiğinde kontrol yapılmalı
    public func observePermissionChanges(_ handler: @escaping (ContactPermissionStatus) -> Void) {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            handler(self.permissionStatus)
        }
    }

    /// Permission observer'ı temizle
    public func stopObservingPermissionChanges() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
}