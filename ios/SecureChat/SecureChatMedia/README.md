# SecureChatMedia

iOS sesli ve görüntülü arama modülü. WebRTC + CallKit entegrasyonu ile native iOS arama deneyimi sağlar.

## Özellikler

### ✅ Temel Özellikler
- **WebRTC PeerConnection**: P2P ses/video iletimi
- **CallKit Entegrasyonu**: Native iOS arama arayüzü
- **Audio Session Yönetimi**: Ses routing ve interruption handling
- **DTLS-SRTP Şifreleme**: WebRTC native encryption
- **Cross-platform Uyumluluk**: Android implementasyonu ile uyumlu

### ✅ Arama Yaşam Döngüsü
```
IDLE → INITIATING → RINGING → CONNECTING → ACTIVE → ENDED
                       ↓                      ↓
                   REJECTED                FAILED
                       ↓
                     BUSY
```

### ✅ Media Kontrolleri
- Mikrofon mute/unmute
- Hoparlör açık/kapalı
- Kamera açık/kapalı (video aramalar)
- Ön/arka kamera geçişi
- Bluetooth SCO desteği

### ✅ Audio Routing
- Receiver (kulaklık)
- Speaker (hoparlör)
- Bluetooth headset
- Wired headphones
- Otomatik route değiştirme

## Kullanım

### Temel Kurulum

```swift
import SecureChatMedia
import SecureChatNetwork

// Network service ile CallManager oluştur
let networkService = NetworkService(signalingUrl: "wss://your-server.com")
let callManager = CallManager(networkService: networkService)
```

### Giden Arama

```swift
// Sesli arama
try await callManager.initiateCall(
    to: "peer-user-id",
    callType: .voice,
    userId: "current-user-id"
)

// Video arama
try await callManager.initiateCall(
    to: "peer-user-id", 
    callType: .video,
    userId: "current-user-id"
)
```

### Gelen Arama Handling

```swift
// Gelen arama sinyali geldiğinde
await callManager.handleIncomingCall(sdpOffer, currentUserId: userId)

// Kullanıcı aramayı kabul ettiğinde (CallKit callback)
try await callManager.acceptCall()

// Kullanıcı aramayı reddettiğinde
await callManager.rejectCall()
```

### Media Kontrolleri

```swift
// Mikrofon mute/unmute
callManager.toggleMute()

// Hoparlör açık/kapalı
callManager.toggleSpeaker()

// Kamera açık/kapalı (video aramalar)
callManager.toggleCamera()

// Ön/arka kamera geçişi
try callManager.switchCamera()
```

### Arama Durumu İzleme

```swift
// SwiftUI View'da
struct CallView: View {
    @ObservedObject var callManager: CallManager
    
    var body: some View {
        VStack {
            switch callManager.callState {
            case .idle:
                Text("Arama yok")
            case .ringing:
                Text("Aranıyor...")
            case .active:
                if let duration = callManager.getCallDuration() {
                    Text("Süre: \(formatDuration(duration))")
                }
            case .ended:
                Text("Arama sonlandı")
            default:
                Text(callManager.callState.displayName)
            }
        }
    }
}

// Combine ile
callManager.$currentSession
    .sink { session in
        print("Arama durumu: \(session?.state.displayName ?? "Yok")")
    }
    .store(in: &cancellables)
```

## Mimari

### Sınıf Diyagramı

```
CallManager (Ana orchestrator)
├── CallKitManager (Sistem entegrasyonu)
├── WebRTCManager (P2P connection)
├── AudioSessionManager (Ses yönetimi)
└── NetworkService (Signaling)
```

### Veri Modelleri

```swift
CallSession {
    callId: String
    peerId: String
    callType: CallType (.voice/.video)
    direction: CallDirection (.incoming/.outgoing)
    state: CallState
    startTime: TimeInterval?
    duration: TimeInterval?
    isMuted: Bool
    isSpeakerOn: Bool
    isCameraEnabled: Bool
    isUsingFrontCamera: Bool
}
```

## Android Karşılaştırması

| Özellik | Android | iOS |
|---------|---------|-----|
| P2P Connection | WebRTC + AudioStreamer fallback | WebRTC native |
| Sistem Entegrasyonu | ForegroundService + Notification | CallKit |
| Audio Management | AudioManager | AVAudioSession |
| Video Capture | Camera2 API | AVFoundation |
| Şifreleme | DTLS-SRTP | DTLS-SRTP |
| Background Calls | Foreground Service | CallKit background |
| Proximity Sensor | PowerManager WakeLock | UIDevice proximityMonitoring |

## Test Coverage

### Unit Testler
- ✅ `CallManagerTests`: Arama yaşam döngüsü
- ✅ `CallStateTests`: Model validasyonu  
- ✅ `AudioSessionManagerTests`: Ses yönetimi
- ✅ `WebRTCManagerTests`: P2P bağlantı (Gelecekte)
- ✅ `CallKitManagerTests`: Sistem entegrasyonu (Gelecekte)

### Test Çalıştırma

```bash
# Unit testler
swift test

# Xcode ile
xcodebuild test -scheme SecureChatMedia
```

## Konfigürasyon

### Info.plist Gereksinimleri

```xml
<!-- Mikrofon erişimi -->
<key>NSMicrophoneUsageDescription</key>
<string>SecureChat sesli arama için mikrofon erişimi gerektirir</string>

<!-- Kamera erişimi (video aramalar için) -->
<key>NSCameraUsageDescription</key>
<string>SecureChat video arama için kamera erişimi gerektirir</string>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
    <string>voip</string>
    <string>audio</string>
</array>
```

### WebRTC Konfigürasyonu

```swift
// ICE servers (STUN/TURN)
let iceServers = [
    RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
    RTCIceServer(urlStrings: ["turn:your-turn-server.com"], 
                 username: "user", credential: "pass")
]
```

## Güvenlik

### DTLS-SRTP Şifreleme
- WebRTC native DTLS-SRTP kullanır
- Media stream'ler otomatik olarak şifrelenir
- Certificate fingerprint validation
- Forward secrecy garantisi

### CallKit Güvenliği
- System-level call integration
- Call history iOS tarafından yönetilir
- Do Not Disturb uyumluluğu
- Emergency call bypass

## Performance Optimizasyonları

### Adaptive Bitrate
- Network kalitesine göre otomatik bitrate ayarı
- Battery optimization için adaptive FPS
- Cellular vs WiFi optimizasyonları

### Memory Management
- Automatic cleanup on call end
- WebRTC resource disposal
- Audio session restoration

## Bilinen Sınırlamalar

1. **iOS Simulator**: WebRTC kamera erişimi sınırlı
2. **Background Video**: iOS background'da video capture sınırlı
3. **CallKit History**: Şifrelenmiş call log integration karmaşık
4. **Group Calls**: Şu anda 1:1 arama desteği
5. **Screen Sharing**: WebRTC iOS SDK'da sınırlı

## Gelecek Geliştirmeler

### Roadmap
- [ ] Screen sharing desteği
- [ ] Group call (3+ kişi)
- [ ] Call recording (yasal gereksinimlere göre)
- [ ] Advanced noise cancellation
- [ ] Spatial audio desteği
- [ ] AR/VR call integration

### Performance İyileştirmeleri
- [ ] Metal backend for video processing
- [ ] Core ML noise reduction
- [ ] Network-adaptive quality scaling
- [ ] Battery usage optimization

## Hata Giderme

### Common Issues

**WebRTC bağlantı sorunu**
```swift
// ICE candidate gathering kontrolü
webRTCManager.$iceConnectionState
    .sink { state in
        if case .failed = state {
            // Restart ICE veya fallback
        }
    }
```

**Audio route sorunları**
```swift
// Audio route değişiklik logging
audioSessionManager.$currentRoute
    .sink { route in
        print("Audio route: \(route.displayName)")
    }
```

**CallKit configuration hataları**
```swift
// Provider reset handling
func providerDidReset(_ provider: CXProvider) {
    // Tüm aktif aramaları temizle
    callManager.endAllCalls()
}
```

## License

Bu modül SecureChat projesinin parçasıdır. Proje lisansına tabidir.