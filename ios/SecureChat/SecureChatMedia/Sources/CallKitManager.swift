import Foundation
import CallKit
import Combine
import UIKit

/**
 * iOS CallKit entegrasyonu yöneticisi.
 *
 * Bu sınıf:
 * - Sistem çağrı arayüzünü yönetir (Native iOS call screen)
 * - Gelen aramalar için full-screen notification gösterir
 * - Call history entegrasyonu
 * - Siri ve sistem entegrasyonu
 * - Background call handling
 */
public class CallKitManager: NSObject, ObservableObject {

    // MARK: - Public Properties

    /// CallKit provider durumu
    @Published public private(set) var isConfigured: Bool = false

    /// Aktif CallKit çağrıları
    @Published public private(set) var activeCallKitCalls: Set<UUID> = []

    // MARK: - Callbacks

    /// Arama kabul edildi callback'i
    public var onCallAccepted: ((UUID, String) -> Void)?

    /// Arama sonlandırıldı callback'i
    public var onCallEnded: ((UUID) -> Void)?

    /// Arama başlatıldı callback'i (Siri'den veya contacts'tan)
    public var onCallStarted: ((UUID, String) -> Void)?

    /// Mute durumu değişti callback'i
    public var onMuteToggled: ((UUID, Bool) -> Void)?

    // MARK: - Private Properties

    private let provider: CXProvider
    private let callController = CXCallController()
    private var callSessions: [UUID: String] = [:] // UUID -> peerId mapping

    // MARK: - Initialization

    public override init() {
        // CallKit provider konfigürasyonu
        let providerConfiguration = CXProviderConfiguration()
        providerConfiguration.localizedName = "SecureChat"
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]

        // Icon ve ses ayarları
        if let iconImage = UIImage(named: "CallKitIcon") {
            providerConfiguration.iconTemplateImageData = iconImage.pngData()
        }

        // Zil sesi (kendi custom ses dosyamız)
        providerConfiguration.ringtoneSound = "SecureChatRingtone.caf"

        self.provider = CXProvider(configuration: providerConfiguration)

        super.init()

        // Provider delegate'ini ayarla
        provider.setDelegate(self, queue: DispatchQueue.main)

        isConfigured = true
        print("CallKitManager: CallKit yapılandırıldı")
    }

    // MARK: - Public Methods

    /**
     * Giden arama başlatır (CallKit üzerinden).
     * Bu metod kullanıcının arama ekranından arama başlattığında çağrılır.
     */
    public func startOutgoingCall(to peerId: String, isVideo: Bool = false) async throws {
        let callUUID = UUID()
        let handle = CXHandle(type: .generic, value: peerId)

        let startCallAction = CXStartCallAction(call: callUUID, handle: handle)
        startCallAction.isVideo = isVideo

        let transaction = CXTransaction(action: startCallAction)

        print("CallKitManager: Giden arama başlatılıyor: \(peerId)")

        callSessions[callUUID] = peerId

        try await callController.request(transaction)
    }

    /**
     * Gelen arama bildirimini gösterir (CallKit native UI ile).
     * Bu iOS'un native gelen arama ekranını gösterir.
     */
    public func reportIncomingCall(from peerId: String, isVideo: Bool = false) {
        let callUUID = UUID()
        let handle = CXHandle(type: .generic, value: peerId)

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = handle
        callUpdate.hasVideo = isVideo
        callUpdate.localizedCallerName = peerId // TODO: Gerçek isim lookup'ı

        print("CallKitManager: Gelen arama bildiriliyor: \(peerId)")

        callSessions[callUUID] = peerId

        provider.reportNewIncomingCall(with: callUUID, update: callUpdate) { [weak self] error in
            if let error = error {
                print("CallKitManager: Gelen arama bildirilemedi: \(error)")
                self?.callSessions.removeValue(forKey: callUUID)
            } else {
                print("CallKitManager: Gelen arama başarıyla bildirildi")
                self?.activeCallKitCalls.insert(callUUID)
            }
        }
    }

    /**
     * Arama durumunu günceller (bağlanıyor, aktif, vb.).
     */
    public func updateCall(_ callUUID: UUID, state: CallState) {
        let callUpdate = CXCallUpdate()

        switch state {
        case .connecting:
            callUpdate.localizedCallerName = "Bağlanıyor..."
        case .active:
            callUpdate.localizedCallerName = "SecureChat Araması"
        case .ended, .failed, .rejected:
            // Bu durumlar için endCall kullanılmalı
            break
        default:
            break
        }

        provider.reportCall(with: callUUID, updated: callUpdate)
        print("CallKitManager: Arama durumu güncellendi: \(state)")
    }

    /**
     * Aramayı sonlandırır ve CallKit'e bildirir.
     */
    public func endCall(_ callUUID: UUID, reason: CXCallEndedReason = .remoteEnded) {
        print("CallKitManager: Arama sonlandırılıyor: \(reason)")

        provider.reportCall(with: callUUID, endedAt: Date(), reason: reason)
        activeCallKitCalls.remove(callUUID)
        callSessions.removeValue(forKey: callUUID)
    }

    /**
     * Tüm aktif aramaları sonlandırır.
     */
    public func endAllCalls() {
        print("CallKitManager: Tüm aramalar sonlandırılıyor")

        for callUUID in activeCallKitCalls {
            endCall(callUUID, reason: .unanswered)
        }
    }

    /**
     * CallKit arama UUID'sinden peerId'yi getirir.
     */
    public func getPeerId(for callUUID: UUID) -> String? {
        return callSessions[callUUID]
    }

    /**
     * PeerId'den CallKit UUID'sini getirir.
     */
    public func getCallUUID(for peerId: String) -> UUID? {
        return callSessions.first(where: { $0.value == peerId })?.key
    }

    /**
     * CallKit'in call history'sine arama kaydı ekler.
     */
    public func addCallToHistory(
        peerId: String,
        duration: TimeInterval,
        isOutgoing: Bool,
        isVideo: Bool,
        wasSuccessful: Bool
    ) {
        // iOS call history otomatik olarak CallKit üzerinden yönetilir
        // Ek processing gerekirse burada yapılabilir
        print("CallKitManager: Arama geçmişine eklendi: \(peerId), süre: \(duration)s")
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        print("CallKitManager: Provider reset edildi")

        // Tüm aktif aramaları temizle
        activeCallKitCalls.removeAll()
        callSessions.removeAll()
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("CallKitManager: CXStartCallAction - giden arama başlatılıyor")

        // CallKit'ten gelen giden arama isteği
        guard let peerId = callSessions[action.callUUID] else {
            action.fail()
            return
        }

        // Callback ile CallManager'a bildir
        onCallStarted?(action.callUUID, peerId)

        // Action'ı başarılı olarak işaretle
        action.fulfill()
        activeCallKitCalls.insert(action.callUUID)
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("CallKitManager: CXAnswerCallAction - gelen arama kabul edildi")

        guard let peerId = callSessions[action.callUUID] else {
            action.fail()
            return
        }

        // Callback ile CallManager'a bildir
        onCallAccepted?(action.callUUID, peerId)

        // Action'ı başarılı olarak işaretle
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("CallKitManager: CXEndCallAction - arama sonlandırıldı")

        // Callback ile CallManager'a bildir
        onCallEnded?(action.callUUID)

        // Temizlik yap
        activeCallKitCalls.remove(action.callUUID)
        callSessions.removeValue(forKey: action.callUUID)

        // Action'ı başarılı olarak işaretle
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("CallKitManager: CXSetMutedCallAction - mute durumu: \(action.isMuted)")

        // Callback ile CallManager'a bildir
        onMuteToggled?(action.callUUID, action.isMuted)

        // Action'ı başarılı olarak işaretle
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        print("CallKitManager: CXSetHeldCallAction - hold durumu: \(action.isOnHold)")

        // SecureChat hold özelliğini desteklemiyor, ama action'ı fulfill etmeliyiz
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("CallKitManager: Audio session aktive edildi")

        // Audio session CallKit tarafından yönetiliyor
        // Ek audio konfigürasyonu gerekirse burada yapılabilir
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("CallKitManager: Audio session deaktive edildi")

        // Audio session temizliği
    }
}

// MARK: - Extensions

extension CXCallEndedReason {
    var displayName: String {
        switch self {
        case .failed:
            return "Başarısız"
        case .remoteEnded:
            return "Karşı taraf kapattı"
        case .unanswered:
            return "Cevapsız"
        case .answeredElsewhere:
            return "Başka cihazda cevaplandı"
        case .declinedElsewhere:
            return "Başka cihazda reddedildi"
        @unknown default:
            return "Bilinmeyen sebep"
        }
    }
}