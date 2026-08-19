# Kotlin -> Flutter Platform Farklari

Son güncelleme: 2026-08-19

Bu belge Kotlin/Android uygulamasının Flutter ile Android ve iOS'a taşınırken
platform zorunlulukları nedeniyle nerede farklılaştırıldığını ve nedenini tek
yerde açıklar. Ürün davranışının isteğe bağlı olarak sadeleştirildiği bir satır
yoktur. Kaynak bazındaki 271/271 eşleme `SOURCE_AUDIT.md`, test durumu
`MIGRATION_TRACKER.md`, fiziksel Android kanıtı
`DEVICE_PROD_READINESS_TRACKER.md` içindedir.

## Platform Kararları

| Alan | Kotlin/Android davranışı | Flutter Android karşılığı | iOS karşılığı ve değişiklik nedeni |
|---|---|---|---|
| UI ve navigation | Jetpack Compose, Android inset/navigation | Ortak Flutter widget/route ağacı, Android slide geçişi | Aynı widget ağacı; Cupertino route geçişi ve home-indicator safe-area. iOS geri hareketi platform beklentisine uyar. |
| Minimum işletim sistemi | Android `minSdk 26` sözleşmesi korunur | Android 8.0+ hedefi değişmedi | Minimum iOS 15.0. Flutter 3.44.9 ile çözülen `firebase_core` ve `firebase_messaging` Swift paketleri iOS 15 gerektirdiği için iOS 14 hedefi Xcode tarafından derlenemiyor. Ürün özelliği kaldırmak veya push katmanını zayıflatmak yerine destek tabanı yükseltildi. |
| Güvenli anahtar | Android Keystore | `flutter_secure_storage` Keystore backend'i | Keychain backend'i. İşletim sistemlerinin donanım/erişim API'leri farklıdır; anahtar formatı uygulama dışına çıkarılmaz. |
| Yerel şifreli veri | Room + SQLCipher | Authenticated encrypted snapshot database; Android'de tek seferlik Room/SQLCipher importer | Yeni kurulumda aynı encrypted snapshot database. Room yalnız Android legacy formatı olduğu için iOS'ta importer çalışmaz. |
| Ekran gizliliği | `FLAG_SECURE` ekran görüntüsünü engeller | `MainActivity` release'te fail-closed `FLAG_SECURE` | iOS üçüncü taraf uygulamaya tam screenshot engelleme API'si vermez. App-switcher privacy overlay ve screenshot olayı/uyarısı kullanılır; engellendiği iddia edilmez. |
| Sistem çağrısı | Self-managed Telecom `ConnectionService` | Telecom bridge + incoming/ongoing `CallStyle`; Android 14 için `phoneCall` foreground service | CallKit `CXProvider`/`CXCallController`. Android foreground service kavramı iOS'a taşınmaz. |
| Devam eden çağrı UI | Compose `OngoingCallBar` | Global Flutter route bandı ve native notification open/answer route'u | Aynı Flutter bandı; uygulama dışı yüzey CallKit tarafından yönetilir. |
| Kapalı uygulama VoIP | Android FCM/Telecom yolu | Generic metadata-only wake ve Telecom | Normal APNs yolu hazırdır. Terminated-state gerçek VoIP wake için Apple PushKit entitlement, `.voip` token ve server sender gerekir; bunlar Apple hesap/provisioning dış kapısıdır. |
| Background iş | WorkManager/JobScheduler | WorkManager periodic/one-off işler ve foreground catch-up | BGTask best-effort çalışır; iOS exact-time garantisi vermediği için server timestamp + foreground catch-up korunur. |
| Background socket | Android process/WorkManager ile yeniden bağlantı | Network monitor + lifecycle reconnect | iOS arka planda sürekli WebSocket'e güvenilmez; push wake ve foreground reconnect kullanılır. |
| Rehber | ContactsContract | Native MethodChannel üzerinden ContactsProvider | Contacts.framework. İzin ve alan adları platforma göre uygulanır; yalnız normalize telefon ve gerekli display alanları alınır. |
| Kamera/galeri/dosya | Android picker ve FileProvider URI | `image_picker`, `file_picker`, scoped FileProvider | Photos/PHPicker ve iOS document picker/sandbox URL. Kalıcı erişim yalnız uygulama sandbox kopyasına verilir. |
| Medya aç/paylaş | Android content URI + chooser | Allow-list edilmiş app-private dosya için FileProvider | App sandbox URL + iOS share/open controller. Rastgele external path kabul edilmez. |
| PiP | Android platform PiP | Native readiness bridge ve Flutter renderer | iOS PiP uygunluk/izinleri AVKit/WebRTC sınırlarına tabidir; call ekranı boş renderer fallback'i üretmez. |
| Bildirim | FCM + Android notification channels | FCM wake, decrypt sonrası redacted local notification; lock-screen visibility policy | APNs + iOS notification center. Provider payload'ında kişi, mesaj, grup veya içerik tutulmaz. |
| İzinler | Runtime Android dialogları | Contacts/camera/mic/notification kullanıcı aksiyonunda istenir | `Info.plist` usage description ve Apple izin API'leri. Reddetme auth/main route'u kilitlemez; özellik fail-closed kalır. |
| Haptic | Compose `HapticFeedback` helper | `SecureChatHaptics`: send, long-press, swipe threshold, call controls | Flutter `HapticFeedback` platform kanalından iOS sistem haptic'ine gider; özel vibration izni kullanılmaz. |
| Safe area/klavye | Android navigation/IME inset | `SafeArea` + `MediaQuery.viewInsets`; onboarding CTA ve composer testli | Aynı kod iPhone notch/home-indicator ve keyboard inset'ini tüketir. |
| Uygulama içi dil | Android resources | Flutter ARB, runtime locale persistence, RTL | Aynı ARB ve RTL. Android'e özel native notification channel adları ayrı `values-*`; iOS native sistem metinleri OS/CallKit tarafından yerelleştirilir. |
| Release güvenliği | R8, no-backup, no-cleartext | R8 + resource shrink + Dart obfuscation/split symbols; AAB secret/native audit | Xcode Release, entitlements, privacy manifest ve no-codesign/signed Codemagic kapıları. Apple signing materyali repoya yazılmaz. |

## Son Değişikliklerin Yeri ve Nedeni

| Dosya/alan | Değişiklik | Neden |
|---|---|---|
| `lib/src/features/onboarding/launch_flow.dart` | CTA ve indicator bottom safe-area içine alındı | Android navigation bar ve iPhone home indicator'ın içeriği kapatmasını önlemek. |
| `lib/src/features/chat/chat_chrome.part.dart` | Composer input yüzeyi ile mic/send aksiyonu ayrıldı | Metin alanını kullanılabilir genişlikte tutmak, keyboard inset ve 48 dp hedef sağlamak. |
| `lib/src/features/calls/ongoing_call_bar.dart` | Global devam eden çağrı bandı eklendi | Compose davranışının call route'u dışındaki tüm uygun ekranlarda korunması. |
| `lib/src/app.dart` | Call open request ve notification payload navigator hazır olana kadar bekletiliyor | Cold-start sırasında native aksiyonun kaybolmasını önlemek. |
| `lib/src/media/native_call_integration.dart` | Native `open` aksiyonu eklendi | Sistem çağrı bildirimi/CallKit yüzeyinden Flutter call screen'e dönmek. |
| `lib/src/widgets/haptics.dart` | Ortak light/long-press adapter'ı eklendi | Kotlin'deki haptic etkileşimlerini Android ve iOS'ta ortak API ile korumak. |
| `android/.../SecureChatCallNotificationManager.kt` | Tek kimlikli incoming/ongoing `CallStyle` | Android sistem çağrı yüzeyi ve privacy-redacted lock-screen davranışı. |
| `android/.../SecureChatCallService.kt` | `phoneCall` foreground service | Android 14 ongoing `CallStyle` bildiriminin zorunlu lifecycle şartı. |
| `ios/Runner/AppDelegate.swift` | CallKit, APNs/BGTask, privacy overlay ve native bridge | Android API'lerinin iOS'ta karşılığı olmadığı için Apple-native lifecycle kullanmak. |
| `tool/build_hardened_android_release.sh` | Release build'de `--no-pub` kaldırıldı | Flutter'ın release registrant'ını yeniden üretip test-only native pluginleri teslimden çıkarması. |
| `codemagic.yaml` | Verify ve signed-candidate iOS workflow'ları | Linux'ta bulunmayan Xcode compile, simulator XCTest ve Apple signing kapısını GitHub CI'da çalıştırmak. |
| `ios/Runner.xcodeproj/project.pbxproj` | Debug, Release ve Profile deployment target'ları 15.0 yapıldı | Firebase Swift paketlerinin iOS 15 altındaki target'ı reddetmesi; üç yapılandırmada aynı sonucu garanti etmek. |

## Değiştirilmeyen Ürün Sözleşmeleri

- Signal V3 direct/group şifreleme, sender-key dağıtımı ve no-plaintext fallback.
- Signaling discriminator'ları, private group/control routing ve encrypted file
  chunk wire formatı.
- Auth/OTP/refresh/logout/account-delete sözleşmesi.
- Reply/edit/delete/reaction/star/pin/poll/forward ve read receipt davranışları.
- Backup şifreleme formatı, yanlış parola limiti ve atomik restore.
- Privacy varsayılanları: son görülme ve notification preview kapalı; provider
  wake payload'ı metadata-minimal.
- Tema renkleri, üç font ailesi, dört ana sekme, doodle/glass dili ve route
  hiyerarşisi.

## GitHub ve Codemagic

Yeni repoda kök `codemagic.yaml` ile `flutter_securechat/` birlikte commit
edilmelidir. Keystore, provisioning profile, App Store private key, API token,
`.env`, `signing.properties`, private symbol ve build çıktıları commit edilmez.

Firebase uygulama kimliği, üretim endpoint'leri ve sertifika pinleri gizli
değildir. Aşağıdaki public build girdileri iki workflow'un `environment.vars`
bölümünde sabitlenmiştir; bu yüzden Codemagic UI'da ayrıca bir public variable
group oluşturulması gerekmez:

- `SECURECHAT_FIREBASE_IOS_APP_ID`
- `SECURECHAT_API_BASE_URL`
- `SECURECHAT_SIGNALING_URL`
- `SECURECHAT_CERT_PIN_HOST`
- `SECURECHAT_CERT_PIN_SHA256`
- `SECURECHAT_CERT_PIN_SHA256_BACKUP`

Signed workflow yalnızca gizli App Store Connect ve certificate private-key
girdilerini `appstore_credentials` grubundan ister. Workflow eksik girdide
build'e başlamadan fail-closed durur.

## Harici Kalan Kanıtlar

Kod veya placeholder olmayan, bu Linux/Android ortamında üretilemeyen kapılar:

1. Codemagic/macOS üzerinde gerçek Xcode simulator ve no-codesign iPhoneOS
   compile çıktısı.
2. Apple hesabıyla imzalı IPA ve fiziksel iPhone safe-area/Keychain/CallKit turu.
3. PushKit `.voip` entitlement, gerçek token rotation ve terminated-state APNs
   server gönderimi.
4. Gerçek FCM/APNs provider credential ile killed-device wake turu.
5. Final air-gapped paketin macOS Flutter/iOS engine ve SwiftPM supplement'i.

Bu kapılar tamamlanana kadar iOS kaynak hazırlığı `PASS`, iOS cihaz/runtime
kanıtı ise `EXTERNAL BLOCKER` olarak raporlanır.
