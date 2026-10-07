# 01 — Native derleme ve 5 hedef için vendor'lama

**Bağımlılık:** yok · **Tahmin:** 2-3 gün · **Kritik yol:** evet

## Amaç

`native/securechat_crypto` crate'ini beş hedefe derleyip Android ve iOS
derlemelerine bağlamak, ve bunu projenin offline/vendor'lu disiplinine
oturtmak.

```
Android   arm64-v8a, armeabi-v7a, x86_64
iOS       aarch64-apple-ios (cihaz), aarch64-apple-ios-sim (simulator)
```

## Mevcut durum

Crate yazılmış ve host için derleniyor. Android arm64 cross-compile spike'ta
denendi ve geçti:

```bash
export ANDROID_NDK_HOME=/home/user497/Android/Sdk/ndk/28.2.13676358
cd native/securechat_crypto && cargo ndk -t arm64-v8a build --release
```

Hazır olanlar: Rust 1.85.1, cargo-ndk 3.5.4, NDK 28.2.13676358, dört Android
target'ı `rustup`'ta kurulu. iOS target'ları kurulu DEĞİL, Mac'te
`rustup target add aarch64-apple-ios aarch64-apple-ios-sim` gerekir.

Ölçülen boyut: arm64 `.so` 820 KB, stripped 0.55 MB. Karşılaştırma için
APK'daki `libjingle_peerconnection_so.so` 11.5 MB.

## Yapılacaklar

1. **Derleme betiği** — `tool/build_native_crypto.sh`. Beş hedefi derler,
   çıktıları `android/app/src/main/jniLibs/<abi>/` ve iOS için bir
   `.xcframework` veya statik kütüphane olarak yerleştirir. `SECURECHAT_OFFLINE=1`
   verildiğinde `cargo --offline` kullanmalı.

2. **Gradle bağlantısı** — `android/app/build.gradle.kts`. `jniLibs` yolu
   zaten AGP varsayılanı; `ndk.abiFilters` mantığıyla tutarlı olmalı
   (dosyada `split-per-abi` / `target-platform` özelliklerine göre filtre
   kuran bir blok var, native kütüphane de aynı filtreye uymalı).

3. **iOS bağlantısı** — proje Swift Package Manager kullanıyor
   (`ios/SQLCipher/Package.swift` deseni örnek alınabilir: kaynak depoya
   gömülü, derleme anında ağ erişimi gerekmiyor). Statik bağlandığı için
   Dart tarafı `DynamicLibrary.process()` açar; bu zaten kodlanmış.

4. **Doğrulama listesi** — `verification-metadata.xml` ve
   `tool/audit_android_release.sh` ile uyum. Audit, teslim edilen her
   native kütüphanede debug sembolü olmamasını şart koşuyor; `Cargo.toml`
   release profilinde `strip = true` var ama AAB içinde de doğrula.

5. **Reproducible build** — crate sürümünü ve `Cargo.lock`'u pinle,
   artefakt SHA-256'larını `SHA256SUMS` benzeri bir dosyaya yaz.

## Tuzaklar

**Audit fail-closed.** `tool/audit_android_release.sh` artık araç hatasını
"temiz" saymıyor ve PCRE2'li ripgrep şart koşuyor. Kurulum:
`cargo install ripgrep --locked --features pcre2 --force`.

**`panic = "abort"`** release profilinde; bu, `cargo test --release`'in
koşmaması demek. Testler debug profilinde koşar, bu normal.

**APK boyutu.** Fat APK şu an 119.7 MB (üç ABI), arm64-only 45.5 MB. Native
kripto kütüphanesi bunun yanında gürültü; boyut gerekçesiyle ABI düşürme.

## Bitirme ölçütü

- Beş hedef için artefakt üretiliyor ve SHA-256'ları kayıtlı
- `flutter build apk --release --target-platform=android-arm64` geçiyor
- `tool/audit_android_release.sh <aab>` PASS veriyor
- Mac'te `tool/verify_ios_on_macos.sh` geçiyor
- Cihazda `test/vodozemac_ffi_test.dart`'ın integration karşılığı koşuyor

---

## Ortak zemin

Önce [INDEX.md](INDEX.md) oku — mimari kararlar ve herkesi ilgilendiren
tuzaklar orada. Özellikle: vodozemac base64'ü padding'siz üretir, one-time
key'ler Account pickle'ının içinde durur, her encrypt/decrypt sonrası
yeniden pickle gerekir, ve Famedly'nin AGPL Dart binding'ine bakılmaz.

## Bitirme ölçütü

```bash
cd /home/user497/securechat/flutter_securechat
export PATH="/home/user497/flutter/bin:$PATH"
flutter analyze --no-pub     # temiz olmali
flutter test --no-pub        # tamami gecmeli
```
