import Foundation
import AVFoundation
import UIKit

/**
 * iOS AVAudioSession yöneticisi.
 *
 * Bu sınıf:
 * - Audio session kategorilerini yönetir
 * - Arama sırasında audio routing kontrolü sağlar
 * - Bluetooth, hoparlör, kulaklık geçişlerini handle eder
 * - Proximity sensor entegrasyonu
 * - Audio interruption'ları yönetir
 */
public class AudioSessionManager: NSObject {

    // MARK: - Public Properties

    /// Audio session durumu
    @Published public private(set) var isActive: Bool = false

    /// Mevcut audio route bilgisi
    @Published public private(set) var currentRoute: AudioRoute = .receiver

    /// Bluetooth cihaz durumu
    @Published public private(set) var isBluetoothAvailable: Bool = false

    /// Hoparlör durumu
    @Published public private(set) var isSpeakerOn: Bool = false

    // MARK: - Private Properties

    private let audioSession = AVAudioSession.sharedInstance()
    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions?

    private var proximityMonitoringEnabled: Bool = false

    // MARK: - Initialization

    public override init() {
        super.init()
        setupAudioSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        disableProximityMonitoring()
    }

    // MARK: - Public Methods

    /**
     * Arama için audio session'ı yapılandırır.
     * - VoiceChat kategorisine geçer
     * - Audio route'ları ayarlar
     * - Proximity monitoring'i etkinleştirir
     */
    public func configureForCall() throws {
        print("AudioSessionManager: Arama için audio session yapılandırılıyor")

        // Mevcut ayarları kaydet
        previousCategory = audioSession.category
        previousMode = audioSession.mode
        previousOptions = audioSession.categoryOptions

        // VoiceChat kategorisine geç
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )

        // Audio session'ı aktive et
        try audioSession.setActive(true, options: [])

        isActive = true
        updateCurrentRoute()
        enableProximityMonitoring()

        print("AudioSessionManager: Audio session arama için yapılandırıldı")
    }

    /**
     * Audio session'ı normal duruma döndürür.
     */
    public func restoreDefaultConfiguration() {
        print("AudioSessionManager: Varsayılan audio session ayarlarına dönülüyor")

        do {
            // Önceki ayarları geri yükle
            if let category = previousCategory,
               let mode = previousMode,
               let options = previousOptions {
                try audioSession.setCategory(category, mode: mode, options: options)
            } else {
                // Varsayılan ayarlara dön
                try audioSession.setCategory(.ambient, mode: .default, options: [])
            }

            // Audio session'ı deaktive et
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])

            isActive = false
            isSpeakerOn = false
            disableProximityMonitoring()

            print("AudioSessionManager: Varsayılan ayarlara döndü")
        } catch {
            print("AudioSessionManager: Varsayılan ayarlara döndürülürken hata: \(error)")
        }
    }

    /**
     * Hoparlör açık/kapalı durumunu değiştirir.
     */
    public func setSpeaker(enabled: Bool) throws {
        print("AudioSessionManager: Hoparlör durumu değiştiriliyor: \(enabled)")

        if enabled {
            try audioSession.overrideOutputAudioPort(.speaker)
            isSpeakerOn = true
        } else {
            try audioSession.overrideOutputAudioPort(.none)
            isSpeakerOn = false
        }

        updateCurrentRoute()
    }

    /**
     * Bluetooth SCO bağlantısını yönetir.
     */
    public func setBluetoothEnabled(_ enabled: Bool) throws {
        print("AudioSessionManager: Bluetooth SCO \(enabled ? "etkinleştiriliyor" : "devre dışı bırakılıyor")")

        if enabled && isBluetoothAvailable {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
        } else {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker]
            )
        }

        updateCurrentRoute()
    }

    /**
     * Audio interruption'ları handle eder.
     * Örnek: Gelen telefon araması, alarm, vb.
     */
    public func handleAudioInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        print("AudioSessionManager: Audio interruption: \(interruptionType)")

        switch interruptionType {
        case .began:
            // Arama pause edilebilir
            print("AudioSessionManager: Audio interruption başladı")

        case .ended:
            guard let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }

            let interruptionOptions = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if interruptionOptions.contains(.shouldResume) {
                // Audio session'ı yeniden aktive et
                do {
                    try audioSession.setActive(true, options: [])
                    print("AudioSessionManager: Audio session yeniden aktive edildi")
                } catch {
                    print("AudioSessionManager: Audio session yeniden aktive edilemedi: \(error)")
                }
            }

        @unknown default:
            print("AudioSessionManager: Bilinmeyen interruption türü")
        }
    }

    // MARK: - Private Methods

    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProximityStateChange),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        handleAudioInterruption(notification)
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        updateCurrentRoute()
        updateBluetoothAvailability()

        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        print("AudioSessionManager: Audio route değişti: \(reason)")

        switch reason {
        case .newDeviceAvailable:
            print("AudioSessionManager: Yeni audio cihaz bağlandı")

        case .oldDeviceUnavailable:
            print("AudioSessionManager: Audio cihaz çıkarıldı")
            // Bluetooth kulaklık çıkarıldıysa hoparlöre geç
            if currentRoute == .bluetooth {
                try? setSpeaker(enabled: true)
            }

        default:
            break
        }
    }

    @objc private func handleProximityStateChange(_ notification: Notification) {
        let isNear = UIDevice.current.proximityState
        print("AudioSessionManager: Proximity durumu değişti: \(isNear ? "yakın" : "uzak")")

        // Proximity sensor aktifse ve yakın mesafede ise hoparlörü kapat
        if isNear && isSpeakerOn && !isBluetoothAvailable {
            try? setSpeaker(enabled: false)
        }
    }

    private func updateCurrentRoute() {
        let currentRouteDescription = audioSession.currentRoute
        let outputs = currentRouteDescription.outputs

        if outputs.contains(where: { $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP }) {
            currentRoute = .bluetooth
        } else if outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            currentRoute = .speaker
        } else if outputs.contains(where: { $0.portType == .headphones || $0.portType == .bluetoothLE }) {
            currentRoute = .headphones
        } else {
            currentRoute = .receiver
        }

        print("AudioSessionManager: Mevcut audio route: \(currentRoute)")
    }

    private func updateBluetoothAvailability() {
        let availableInputs = audioSession.availableInputs ?? []
        isBluetoothAvailable = availableInputs.contains { input in
            input.portType == .bluetoothHFP
        }
        print("AudioSessionManager: Bluetooth mevcut: \(isBluetoothAvailable)")
    }

    private func enableProximityMonitoring() {
        if !proximityMonitoringEnabled {
            UIDevice.current.isProximityMonitoringEnabled = true
            proximityMonitoringEnabled = true
            print("AudioSessionManager: Proximity monitoring etkinleştirildi")
        }
    }

    private func disableProximityMonitoring() {
        if proximityMonitoringEnabled {
            UIDevice.current.isProximityMonitoringEnabled = false
            proximityMonitoringEnabled = false
            print("AudioSessionManager: Proximity monitoring devre dışı bırakıldı")
        }
    }
}

// MARK: - Supporting Types

/**
 * Audio çıkış türleri
 */
public enum AudioRoute: String, CaseIterable {
    case receiver = "receiver"
    case speaker = "speaker"
    case headphones = "headphones"
    case bluetooth = "bluetooth"

    public var displayName: String {
        switch self {
        case .receiver:
            return "Kulaklık"
        case .speaker:
            return "Hoparlör"
        case .headphones:
            return "Kablolu Kulaklık"
        case .bluetooth:
            return "Bluetooth"
        }
    }

    public var iconName: String {
        switch self {
        case .receiver:
            return "phone"
        case .speaker:
            return "speaker.wave.3.fill"
        case .headphones:
            return "headphones"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        }
    }
}