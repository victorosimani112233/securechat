# 01 — Native derleme ve 5 hedef için vendor'lama

**Durum: Android TAMAM · iOS Mac'te bitirilecek** · **Bağımlılık:** yok

## Yapıldı — Android, doğrulandı

`tool/build_native_crypto.sh` üç ABI'yi derleyip `jniLibs`'e koyuyor,
artefaktları doğruluyor ve SHA-256 toplamlarını yazıyor.

```
arm64-v8a      800 KB
armeabi-v7a    598 KB
x86_64         927 KB
```

Script iki şeyi kendisi denetliyor, çünkü ikisinin sessizce bozulması
mümkün: teslim edilen her `.so`'da **debug sembolü kalmadığı**
(`tool/audit_android_release.sh` bunu şart koşuyor ve release'i reddediyor)
ve `sc_abi_version` sembolünün **gerçekten dışa açıldığı** — boş bir
kütüphane sessizce teslim edilmesin.

`Cargo.lock` her koşuda `cargo metadata --locked` ile doğrulanıyor: kripto
çekirdeğinin bağımlılık ağacı sessizce kaymamalı.

Release akışına bağlandı: `tool/build_hardened_android_release.sh` artık
`pub get` sonrası native derlemeyi çağırıyor, yani kaynak ile teslim edilen
ikili ayrışamıyor.

**Doğrulama:** AAB üretildi ve `tool/audit_android_release.sh` PASS verdi;
native kütüphane sayısı **18 → 21** çıktı ve üçü de AAB içinde
`base/lib/<abi>/libsecurechat_crypto.so` yolunda, stripped.

Artefaktlar **depoda vendor'lu**. Projenin deseni bu (`local-repo/` AAR'ları,
`ios/SQLCipher/Sources` amalgamation'ı) ve gerekçesi şu: çıktıları depoya
koymazsak scripti koşmayı unutan herkeste kütüphanesiz bir APK üretilir ve
uygulama `DynamicLibrary.open` sırasında çöker. Üretilebilirlik kaydedilen
toplamlar ve pinli `Cargo.lock` ile sağlanıyor.

`native/securechat_crypto/include/securechat_crypto.h` yazıldı: ABI'nin
otoritatif beyanı, iOS XCFramework'ü de onu istiyor. Sürümün üç yerde
(Rust gövdesi, header, Dart sabiti) ayrışmasını `test/vodozemac_ffi_test.dart`
içindeki tutarlılık testi yakalıyor.

CI'da iki boşluk kapatıldı: flutter işine Rust ve native derleme eklendi
(yoksa 14 Dart FFI testi `markTestSkipped` ile **sessizce atlanıyordu**), ve
atlanan test sayısını kontrol eden bir adım konuldu.

## Kalan — iOS, macOS gerekiyor

Linux'ta Apple hedefleri bağlanamıyor. Hazırlananlar:

- `tool/build_native_crypto.sh ios` — `aarch64-apple-ios` ve
  `aarch64-apple-ios-sim` derler, `xcodebuild -create-xcframework` ile
  birleştirir, `ios/SecureChatCrypto/Artifacts/` altına koyar. macOS
  dışında kendini atlıyor.
- `ios/SecureChatCrypto/Package.swift` — `binaryTarget` ile XCFramework'e
  bakan yerel SwiftPM paketi. `ios/SQLCipher` kaynak vendor'luyor; burada
  aynısı yapılamaz çünkü Xcode Rust derlemez.
- `ios/SecureChatCrypto/README.md` — üretme ve Xcode'a bağlama adımları.

Mac'te yapılacak:

1. `tool/build_native_crypto.sh ios`
2. `ios/SecureChatCrypto`'yu Xcode'da yerel paket olarak ekle, `Runner`
   target'ına bağla, **Do Not Embed** (statik kütüphane).
3. `tool/verify_ios_on_macos.sh`

`project.pbxproj` bilerek elle düzenlenmedi: UUID üretimi ve bölüm sırası
elle yazıldığında projeyi bozuyor. SQLCipher referansı (`5C1FE000…` ile
başlayan girdiler) örnek olarak bakılabilir.

## Sonraki görevler için notlar

**Dart iOS'ta `DynamicLibrary.process()` açıyor** — kütüphane ana ikiliye
statik bağlandığı için ayrı bir dylib yok. Bu zaten kodlu
(`securechat_crypto_ffi.dart`), değiştirmeye gerek yok.

**ABI sürümü şu an 1.** TASK_02 Megolm eklerken 2'ye yükseltecek; Rust
gövdesi, header ve `expectedAbiVersion` birlikte güncellenmeli, yoksa
tutarlılık testi düşer.
