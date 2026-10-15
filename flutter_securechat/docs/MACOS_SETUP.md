# Mac'te Kurulum

Bu depo Linux üzerinde geliştirildi. macOS'ta derlemek için gereken her şey
aşağıda. Önce denetim, sonra eksikler.

```bash
./tool/preflight_macos.sh
```

Betik hiçbir şey kurmaz; eksik olan her madde için çalıştırılacak komutu yazar.

**Tek komut (2026-10-15):** aşağıdaki adımların hepsini — main'e geçme,
Xcode dizini, Rust ve iOS hedefleri, SQLCipher, canlı sunucu girdileri,
kripto çekirdeği — `tool/ios_build.sh` yapar:

```bash
./tool/ios_build.sh                        # kapı: testler + release derleme + simülatör XCTest
./tool/ios_build.sh install                # bağlı iPhone'a canlı sunucuyla kur
./tool/ios_build.sh install --personal grj # ücretsiz Apple ID (push kapalı)
```

Commitlenmemiş değişiklik varsa durur; yalnız kişisel imza / Xcode takım
ayarı (`Runner.entitlements`, `project.pbxproj`) geri alınır.

Betik hatayla biterse bütün çıktı GitHub'da `ios-build-logs` dalına
`logs/<zaman>-<mod>-<commit>.txt` olarak gönderilir; `main`'e dokunmaz.
Okumak için: `git fetch <github-remote> ios-build-logs && git show
FETCH_HEAD:logs/<dosya>`. Göndermemek için `IOS_BUILD_NO_UPLOAD=1`.

## 1 · Depoyu taşıma

`origin` uzak sunucusu bir **LAN adresi** (`git remote -v` ile görürsünüz).
Mac aynı ağda değilse oradan klonlanamaz. Çalışan uzak sunucu GitHub:

```bash
git clone https://github.com/victorosimani112233/securechat.git
cd securechat/flutter_securechat
```

Taşımadan önce Linux tarafında gönderilmemiş commit kalmadığını doğrulayın:

```bash
git log --branches --not --remotes --oneline   # boş çıktı beklenir
```

**Kopyalamayın:** `android/local.properties` (Linux yolları içerir, Flutter
yeniden üretir), `build/`, `.dart_tool/`, `qa/mock/state/`, `qa/mock/tls/`.
Son ikisi Signal oturum durumu ve TLS özel anahtarı içerir ve zaten
`.gitignore`'da.

## 2 · Araç zinciri

| Araç | Sürüm | Kurulum |
|---|---|---|
| Flutter | 3.44.9 (stable, rev `6b182d2c75`) | https://docs.flutter.dev/get-started/install/macos |
| Dart | 3.12.2 | Flutter ile gelir |
| Xcode | 26.0 | App Store |
| SQLCipher | herhangi bir 4.x | `brew install sqlcipher` |
| Rust | stable (rustup) | `curl https://sh.rustup.rs -sSf \| sh`, sonra `rustup target add aarch64-apple-ios aarch64-apple-ios-sim` |
| Java | 21 | `brew install --cask temurin@21` (yalnız Android için) |

Flutter sürümü farklıysa çalışır ama doğrulanmamıştır; `pubspec.yaml`
sürümleri tam pinli olduğu için çözümleme sapması sınırlıdır.

### Homebrew kurulumunun yan etkisi

Homebrew, Command Line Tools kurarken **aktif geliştirici dizinini kendine
çevirebiliyor**. Bu olduğunda:

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

`xcrun` bütün araçları bu dizinden çözdüğü için iPhoneOS SDK'sı kaybolur,
`xcodebuild` çalışmaz, `simctl` boş döner. Düzeltmesi:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Preflight betiği bunu ilk sırada denetler; bir kez doğru olması yetmiyor.

### iOS platformu ile simülatör runtime'ı ayrı şeyler

| | ne için | nasıl kurulur |
|---|---|---|
| iPhoneOS SDK | **cihaz** için derleme | Xcode platformu — `xcodebuild -downloadPlatform iOS` |
| Simulator runtime | simülatörü çalıştırma | ayrı `.dmg` — `xcodebuild -importPlatform <dosya>.dmg` |

Runtime'ı kurmuş olmak cihaz SDK'sını getirmez. `flutter build ios --release
--no-codesign` cihaz SDK'sını ister.

### Rust neden gerekiyor (2026-10-14)

Şifreleme çekirdeği (`native/securechat_crypto`, vodozemac) Rust'ta ve Xcode
onu derlemez. `tool/build_native_crypto.sh ios` cihaz ve simülatör için
statik kütüphaneleri üretip `ios/SecureChatCrypto/Artifacts/` altına
XCFramework olarak koyar; `Runner` hedefi bu yerel paketi bağlar ve
`ios/Flutter/SecureChatCrypto.xcconfig` her C ABI simgesini ikiliye zorla
alır. `tool/verify_ios_on_macos.sh` ve `tool/run_ios_device.sh` bu adımı
kendisi koşturur ve derlenen `Runner` ikilisinde simgelerin hepsini denetler.
Artefakt üretilmeden Xcode'da doğrudan derlerseniz paket çözümlenmez
("Artifacts/SecureChatCrypto.xcframework bulunamadı"): önce betiği koşturun.

### SQLCipher neden ayrıca gerekiyor

`flutter test` **ana makinede** (macOS) koşar ve gerçek bir şifreli veritabanı
açar. Bunun için sistemde `libsqlcipher.dylib` bulunmalı. Aranan yollar
`lib/src/storage/encrypted_record_store.dart` içindeki `_resolveLibrary`
listesiyle aynıdır; Homebrew her iki mimaride de bu yollardan birine kurar.

Bu **yalnız testler için**. iOS uygulaması `ios/SQLCipher` altındaki gömülü
kopyayı kullanır, sistemdekini değil.

#### Homebrew olmadan

Homebrew kurulumu ağ ister. Kısıtlı bağlantıda gerek yok — kaynak zaten
depoda, derleyici zaten Xcode ile geliyor:

```bash
./tool/build_sqlcipher_macos.sh
```

`~/.securechat/lib/libsqlcipher.dylib` üretir, ürettiği kütüphanenin gerçekten
SQLCipher olduğunu doğrular ve tanıtma komutunu yazar:

```bash
export SECURECHAT_SQLCIPHER_PATH="$HOME/.securechat/lib/libsqlcipher.dylib"
```

Bu değişken tanımlıysa standart yollardan önce o dosya denenir.

## 3 · Doğrulama sırası

```bash
flutter pub get
flutter analyze
flutter test
dart tool/audit_ios_readiness.dart
```

`audit_ios_readiness.dart` iOS tarafındaki sözleşmeleri denetler; SQLCipher'ın
uygulama ikilisine bağlı olduğunu da burada doğrular.

## 4 · iOS derlemesi

```bash
flutter build ios --release --no-codesign
```

İmzalı derleme ve simülatör testleri dahil tam kapı:

```bash
export SECURECHAT_FIREBASE_IOS_APP_ID=...
export SECURECHAT_API_BASE_URL=...
export SECURECHAT_SIGNALING_URL=...
export SECURECHAT_CERT_PIN_HOST=...
export SECURECHAT_CERT_PIN_SHA256=...
export SECURECHAT_CERT_PIN_SHA256_BACKUP=...
./tool/verify_ios_on_macos.sh
```

Bu değerler `codemagic.yaml` içindeki ortam değişkenleriyle aynı (CI artık
kullanılmıyorsa da dosya, hangi girdilerin gerektiğinin kaydı olarak duruyor).

### Xcode sürümü ve simülatör

Proje belirli bir Xcode sürümüne bağlı değil; SDK, kurulu Xcode'un içinden
gelir. Ayarlanması gereken bir "SDK sürümü" yok.

Simülatör adı da sabit değil: `verify_ios_on_macos.sh` kurulu iPhone
simülatörlerinden ilkini seçer ve hangisini seçtiğini yazar. Belirli bir
cihaz isterseniz:

```bash
IOS_SIMULATOR_NAME="iPhone 17 Pro" ./tool/verify_ios_on_macos.sh
```

Xcode 16'dan beri Xcode.app simülatör imajı olmadan geliyor. Kurulu simülatör
yoksa gate testleri atlamaz, açık bir hatayla durur. `flutter build ios
--release --no-codesign` için simülatör gerekmez.

### Deployment target

`15.0` — üç yerde aynı olmak zorunda: `project.pbxproj` (üç yapılandırma),
`ios/SQLCipher/Package.swift` ve `tool/audit_ios_readiness.dart` içindeki
`_minimumIosVersion`. Audit tool üçünün eşitliğini denetler.

Yükseltmek **kullanıcı kaybettirir**: bu sürümün altındaki cihazlar
güncelleme alamaz. Yalnız Xcode gerçekten reddediyorsa yükseltin.

### CocoaPods gerekmiyor

iOS derlemesi Swift Package Manager kullanıyor
(`flutter config --enable-swift-package-manager`). Depoda `Podfile` yok ve
olmamalı.

## 5 · İlk açılışta beklenmedik bir hata görürseniz

```
StorageEncryptionUnavailableException: Baglanan SQLite kutuphanesi
SQLCipher degil; sifrelenmemis bir veritabani yazmamak icin depo acilmadi.
```

Bu mesaj bir arıza değil, bir **koruma**. Uygulama düz SQLite'a bağlanmış
demektir ve veritabanını şifresiz yazmaktansa açmamayı seçmiştir.

- macOS'ta testlerde görülürse: `brew install sqlcipher`
- iOS cihazında/simülatöründe görülürse: gömülü paket bağlanmamış demektir.
  `dart tool/audit_ios_readiness.dart` hangi halkanın koptuğunu söyler.

Ayrıntı: `ios/SQLCipher/README.md`.
