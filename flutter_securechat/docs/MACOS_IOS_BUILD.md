# macOS iOS Build ve Air-Gap Tamamlama Rehberi

Bu rehber tracker'daki 21, 24 ve 26 numarali dis bagimli maddeleri gercek bir
Mac uzerinde kapatmak icindir. Linux bundle'daki `flutter_sdk.tar.gz` macOS'ta
calismaz. Flutter kaynaklari ortaktir; iOS derleme araci ve cache'i Mac'te
hazirlanir.

## Sunucu gereksinimi

- Gercek Apple Silicon Mac (M1 veya ustu), en az 16 GB RAM ve 100 GB bos alan.
- Full admin/root erisimi; Xcode, Keychain ve command-line tool ayari yapilabilmeli.
- Flutter stable `3.44.9`, revision `6b182d2c7585eba26d4edce0f97630effd256c33`.
- Xcode ve Xcode command-line tools; Xcode lisansi kabul edilmis olmali.
- iOS 15.0 veya daha yeni simulator runtime'i; fiziksel test icin iOS 15+ cihaz.
- Ilk cache hazirlama turunda internet. Son air-gap kaniti ag kapaliyken yapilir.
- Gercek cihaz testi icin Apple Developer hesabi, Team ID ve kayitli cihaz.

## Gizli girdiler

Asagidakileri repo veya offline bundle'a eklemeyin:

- Apple Distribution/Development private key ve `.p12` parolasi.
- App Store Connect API key veya Apple hesap parolasi.
- APNs `.p8` private key.

Signing certificate Mac Keychain'e, provisioning profile ise kullanici
profil dizinine guvenli kanaldan kurulur. Explicit App ID proje bundle ID'siyle
eslesmelidir. Push notification ve VoIP kullanilacaksa ilgili capability'ler
App ID/provisioning profile icinde acik olmalidir.

## Ilk online cache hazirlama

1. Xcode'u bir kez acin, platform lisanslarini kabul edin ve iOS simulator
   runtime'ini kurun.
2. Apple Silicon icin Flutter 3.44.9 macOS SDK'sini kurun; Linux SDK arsivini
   kullanmayin.
3. `flutter_securechat_source.tar.gz` arsivini acin. Bu arsiv generated mutlak
   yollar tasimaz; `flutter pub get` bunlari Mac yollarina gore yeniden uretir.
4. Proje kokunde calistirin:

```bash
flutter config --enable-swift-package-manager
flutter precache --ios
flutter pub get
./tool/verify_ios_on_macos.sh
```

Proje Xcode'da local `FlutterGeneratedPluginSwiftPackage` kullanir. Native
pluginlerin Swift package kaynaklari ilk turda resolve edilip Xcode/SwiftPM
cache'ine alinmalidir. `ios/Flutter/ephemeral`, `Generated.xcconfig` ve plugin
path manifestleri generated dosyalardir; tasinmaz, her makinede yeniden uretilir.
Dogrulama betigi remote Swift dependency varsa Xcode'un urettigi
`Package.resolved` dosyasini `ios/Package.resolved.lock` olarak sabitler ve
SwiftPM JSON semasini Dart ile dogrulayip SHA-256 degerini loglar. JSON lock
dosyasi `plutil` ile kontrol edilmez; Xcode 26 `plutil -lint` bu girdiyi plist
olarak yorumlayabilir. Bu dosya source review'e alinmalidir.

## Signing ve fiziksel cihaz

Xcode'da `ios/Runner.xcodeproj` icin gercek organization Team ve explicit bundle
ID secin. Once otomatik signing ile kayitli iPhone'da debug build calistirin.
Ardindan:

```bash
IOS_SIGNED_BUILD=1 ./tool/verify_ios_on_macos.sh
```

Bu secenek `flutter build ipa --release` calistirir. IPA veya archive'i teslim
ederken signing certificate/key'i arsive dahil etmeyin.

## PushKit ve kapali uygulama aramasi

Mevcut istemci CallKit arayuzunu ve normal APNs/FCM mesaj wake-up yolunu tasir.
Kapali uygulamayi gercek VoIP aramasinda uyandirmak icin ayrica:

- App ID'de Push Notifications ve VoIP/PushKit capability,
- provisioning profile/entitlement,
- `.voip` topic ile APNs gonderen server endpoint'i,
- token register/rotation ve production APNs testi

gerekir. Bu server/Apple girdileri olmadan normal mesaj push'u test edilebilir,
fakat kapali uygulama VoIP parity tamamlandi sayilmaz.

## Air-gapped yeniden dogrulama

Online tur basarili olduktan sonra Mac'i agdan ayirin. Ayni checkout ve cache ile:

```bash
IOS_OFFLINE=1 ./tool/verify_ios_on_macos.sh
```

Bu tur `pub get --offline`, `Package.resolved.lock` disina cikmadan ve automatic
package resolution kapali olarak, analyze, tum Flutter testleri, simulator build
ve codesign'siz release device build'i
gecmelidir. Sonra asagidakileri ayri macOS supplement olarak arsivleyin:

- macOS/Apple Silicon Flutter 3.44.9 SDK ve iOS engine cache,
- Pub cache,
- Xcode/SwiftPM resolved package cache,
- kaynak arsivi, `ios/Package.resolved.lock` ve Xcode live `Package.resolved`,
- build/test log ozeti ve SHA-256 manifest.

Xcode uygulamasini veya Apple signing private key'lerini bundle'a kopyalamayin.
Xcode Mac'te kurulu kalir; supplement yalniz tekrar indirilebilir dependency
cache'lerini ve build kanitlarini tasir.

## Kapanis kaniti

Tracker 21/26 ancak simulator, codesign'siz release, fiziksel cihaz ve offline
cache turu basarili oldugunda kapanir. Tracker 24 ise ancak gercek PushKit
tokeniyle kapali uygulama gelen arama testi server tarafiyla gectiginde kapanir.
