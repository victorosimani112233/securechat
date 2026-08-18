# Dependency, License and Supply-Chain Audit

Bu denetim gizlilik tehdidinin bir parcasi olarak ele alinir. Mesaj icerigi
sunucuda tutulmasa bile degistirilmis bir build dependency'si cihazdaki Signal
anahtarlarini, rehberi veya plaintext'i disari aktarabilir. Bu nedenle kaynak
kilidi ve artefakt dogrulamasi release icin fail-closed kapidir.

## Sonuc

- Linux/Android/Pub/Gradle kilidi: **PASS**
- Hardened signaling ve bot Maven kilidi: **PASS**
- Air-gapped yerel Maven repo kapsami: **PASS**
- iOS SwiftPM kilidi: **macOS uzerinde tamamlanacak dis build kapisi**
- Lisans bildirimi: **PASS**, uygulama Ayarlar ekranindan erisilebilir
- GPL dagitim karari: **release oncesi hukuk/uyum onayi gerekli**

## Kilitleme ve byte dogrulamasi

### Dart ve Flutter

- `pubspec.yaml` icindeki tum hosted dogrudan dependency'ler tek bir kesin
  surume sabitlenir; caret/range/`any` kullanilmaz.
- `pubspec.lock` tum hosted dogrudan ve transitive paketler icin Pub tarafindan
  saglanan 64 haneli SHA-256 degerini tasir.
- Guncel lock 129 hosted paketin 129'unda SHA-256 tasir; kalan 5 girdi Flutter
  SDK kaynagidir.
- Git veya yerel path dependency'si kabul edilmez. Flutter SDK paketleri bu
  kurala dahil degildir; SDK revision'i macOS ve Linux build rehberlerinde
  ayrica sabittir.
- `flutter pub get --offline` lock degismeden gecmek zorundadir.

### Android ve hardened server

- Android Gradle 9.1.0 wrapper ZIP'i
  `a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806`
  SHA-256 degerine sabittir.
- Hardened server Gradle 8.5 wrapper ZIP'i
  `9d926787066a081739e8200858338b4a69e837c3a821a33aca9db09dd4a41026`
  SHA-256 degerine sabittir.
- `android/gradle/verification-metadata.xml` gercek `assembleDebug` dependency
  grafiginden uretilir; guncel manifest 1.243 component ve 2.261 SHA-256 kaydi
  tasir.
- `server_hardened/gradle/verification-metadata.xml` signaling ve bot
  dependency grafigindeki her POM/JAR icin SHA-256 tasir; guncel manifest 544
  component ve 829 SHA-256 kaydi tasir.
- Metadata veya artefakt checksum'i uyusmazsa Gradle build/test baslamadan
  durur. Wildcard `trusted-artifact`, ignored key, `mavenLocal()` ve HTTP repo
  istisnasi yoktur.
- `flutter_webrtc` upstream Gradle betigi JitPack eklese de Android settings
  `RepositoriesMode.PREFER_SETTINGS` uygular; plugin tarafindan eklenen repo
  dependency resolution'a katilmaz. Tek JitPack-origin artefakti olan commit
  sabitli `audioswitch`, byte-for-byte dogrulanmis AAR/POM ile
  `android/vendor/maven` altina alinmistir. Vendored AAR SHA-256 degeri
  `c8240221daa9a96d4ea01a4dc6f6f6b10b4903d2a71f9b57f838bdfeb6c3fcbc`'dir.
- Effective allow-list vendored repo, Google Maven, Maven Central ve yalniz
  `io.flutter` grubuna acik resmi Flutter engine Maven endpoint'idir. Flutter
  plugininin runtime'da repo eklemesine guvenilmez; bu explicit engine girdisi
  air-gapped cache kimligini de kararli tutar.
- Java 2.8.1 wire-parity testi icin gereken `signal-protocol-java`,
  `curve25519-java` ve `protobuf-javalite` JAR'lari Codemagic'te resmi Maven
  Central HTTPS endpoint'inden indirilir ve kullanilmadan once sabit SHA-256
  degerleriyle dogrulanir. Air-gapped test ayni artefaktlari paketlenmis Gradle
  cache'inden ve ayni checksum kontroluyle cozer.
- Ilk checksum tabani, daha once basarili build/test uretmis mevcut cache ve
  resmi Google/Maven Central/Gradle depolarindan olusturuldu. Bu ilk guven
  seremonisi bagimsiz temiz makinede yeniden uretilip diff edilmeden mutlak
  supply-chain kaniti sayilmaz; sonraki tum degisiklikler review gerektirir.

### Air-gapped build

- `tool/make_offline_bundle.sh`, Flutter SDK, Pub cache, Gradle cache ve Android
  SDK'nin yaninda hardened server'in gercek `local-repo` Maven agacini da
  `maven_local_repo.tar.gz` olarak paketler.
- Kaynak arsivi iki Gradle verification manifestini ve iki wrapper checksum'ini
  tasir. Dis bundle `SHA256SUMS.txt` ile yeniden dogrulanir.
- Restore sonrasi hem Android `assembleDebug --offline` hem de
  `:signaling-server:test :bot-api:test --offline` calismalidir.
- Nihai cok-GB bundle, yalniz tum migration/release kapilari bittiginde yeniden
  uretilir; gelistirme turlarinda stale teslim paketi final diye isaretlenmez.

### AGP/Kotlin compatibility warning

Flutter 3.44.9 + AGP 9.0.1 ile bugun build gecmektedir. Bununla birlikte
`file_picker 10.3.10`, `flutter_webrtc 1.6.0` ve transitive
`workmanager_android 0.10.6` halen legacy Kotlin Gradle Plugin uygular. Bu
nedenle `android.builtInKotlin=false` ve `android.newDsl=false` gecici uyumluluk
bayraklari zorunludur; AGP 10 bunlari kaldiracagini bildirir.

Bu uyari gizlenmez ve "sonsuza kadar desteklenir" diye yorumlanmaz. Flutter,
AGP veya bu uc plugin yukseltilecekse once Built-in Kotlin uyumlulugu, native
method kayitlari, tum testler, debug/release APK/AAB ve iki Gradle checksum
manifesti yeniden uretilir. Mevcut pinli toolchain icin bu bir build hatasi
degil, kontrollu gelecek-upgrade blocker'idir.

## iOS ve Swift Package Manager

Flutter'in `FlutterGeneratedPluginSwiftPackage` girdisi Xcode projesinde local
package reference'tir. Linux Xcode dependency graphini resolve edemedigi icin
asagidaki davranis `tool/verify_ios_on_macos.sh` ile Mac kapisina baglidir:

1. Online ilk tur package dependency'lerini resolve eder.
2. Remote Swift package varsa Xcode'un `Package.resolved` dosyasini
   `ios/Package.resolved.lock` olarak saklar.
3. Offline tur kilit yoksa durur; kilidi geri yukler ve
   `-onlyUsePackageVersionsFromResolvedFile` ile
   `-disableAutomaticPackageResolution` uygular.
4. Local-only graph'ta otomatik remote resolution yine kapatilir.

Mac'te uretilmis lock dosyasi source review'e girmeden iOS release alinmaz.
Apple signing/APNs private key'leri lock veya offline bundle'a eklenmez.

## Dogrudan Pub lisans envanteri

Bu siniflandirma yerel Pub cache'indeki ilgili surumun `LICENSE` dosyasindan
okunmustur; hukuki gorus degildir.

| Paket | Surum | Lisans |
|---|---:|---|
| connectivity_plus | 7.3.1 | BSD-3-Clause |
| crypto | 3.0.7 | BSD-3-Clause |
| cryptography | 2.9.0 | Apache-2.0 |
| file_picker | 10.3.10 | MIT |
| firebase_core | 4.13.0 | BSD-3-Clause |
| firebase_messaging | 16.5.0 | BSD-3-Clause |
| flutter_local_notifications | 22.3.0 | BSD-3-Clause |
| flutter_secure_storage | 10.3.1 | BSD-3-Clause |
| flutter_webrtc | 1.6.0 | MIT |
| image_picker | 1.2.2 | BSD-3-Clause |
| just_audio | 0.10.6 | MIT |
| libsignal_protocol_dart | 0.8.2 | GPL-3.0 |
| path_provider | 2.1.6 | BSD-3-Clause |
| record | 7.1.1 | BSD-3-Clause |
| web_socket_channel | 3.0.3 | BSD-3-Clause |
| workmanager | 0.10.7 | MIT |

Android native transitive `audioswitch` artefakti Apache-2.0 lisanslidir.
Lisans metni kaynakta `assets/licenses/audioswitch_APACHE-2.0.txt` olarak
tutulur ve uygulama acilisinda Flutter license registry'ye kaydedilir.

Flutter build'i dependency lisans metinlerini lisans registry/NOTICES
artefaktina ekler. Uygulamadaki Ayarlar > Acik kaynak lisanslari aksiyonu bu
registry'yi `showLicensePage` ile kullaniciya acar.

## GPL-3.0 release kapisi

`libsignal_protocol_dart 0.8.2`, Kotlin istemcinin Signal Protocol V3 wire/state
uyumlulugunu korumak icin kullanilir ve GPL-3.0 lisanslidir. Uygulama binary'sini
dagitmak, Flutter uygulamasinin ilgili kaynaklarini, lisans metnini ve gerekli
kurulum/degisiklik bilgisini GPL ile uyumlu bicimde saglama yukumlulugu
dogurabilir. Play Store/App Store release'i su uc kanit olmadan onaylanmaz:

1. GPL uyumunun hukuk/uyum sorumlusu tarafindan yazili degerlendirilmesi.
2. Dagitilan binary ile tam eslesen kaynak snapshot'i ve build talimatlari.
3. Uygulama ici lisans bildirimi ile dagitim kanalindaki kaynak/teklif
   erisiminin calisir olmasi.

Bu kosullar kriptografik pariteyi zayiflatmak icin paketi sessizce degistirme
izni vermez. Lisans karari farkli bir Signal binding gerektirirse wire/state
capraz testlerinin tamami yeni implementasyonla yeniden gecmelidir.

## Otomatik kapilar

`test/supply_chain_gate_test.dart` su regresyonlari engeller:

- exact olmayan dogrudan Pub surumu,
- checksum'siz hosted lock girdisi veya Git/path dependency,
- wrapper checksum eksigi,
- Gradle verification metadata eksigi veya wildcard guven bypass'i,
- HTTP/JitPack/`mavenLocal()` repo,
- offline bundle'da yerel Maven repo eksigi,
- macOS SwiftPM resolved/offline gate'inin kaldirilmasi,
- uygulama ici lisans sayfasinin kaldirilmasi.
