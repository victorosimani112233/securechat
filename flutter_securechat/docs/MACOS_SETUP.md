# Mac'te Kurulum

Bu depo Linux üzerinde geliştirildi. macOS'ta derlemek için gereken her şey
aşağıda. Önce denetim, sonra eksikler.

```bash
./tool/preflight_macos.sh
```

Betik hiçbir şey kurmaz; eksik olan her madde için çalıştırılacak komutu yazar.

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
| Java | 21 | `brew install --cask temurin@21` (yalnız Android için) |

Flutter sürümü farklıysa çalışır ama doğrulanmamıştır; `pubspec.yaml`
sürümleri tam pinli olduğu için çözümleme sapması sınırlıdır.

### SQLCipher neden ayrıca gerekiyor

`flutter test` **ana makinede** (macOS) koşar ve gerçek bir şifreli veritabanı
açar. Bunun için sistemde `libsqlcipher.dylib` bulunmalı. Aranan yollar
`lib/src/storage/encrypted_record_store.dart` içindeki `_resolveLibrary`
listesiyle aynıdır; Homebrew her iki mimaride de bu yollardan birine kurar.

Bu **yalnız testler için**. iOS uygulaması `ios/SQLCipher` altındaki gömülü
kopyayı kullanır, sistemdekini değil.

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
