# SecureChatCrypto — iOS paketi

`native/securechat_crypto` crate'inin iOS artefaktlarini uygulama ikilisine
baglar. Kaynak Rust'ta oldugu icin `ios/SQLCipher` gibi kaynak-vendor'lama
yapilamiyor; onun yerine onceden derlenmis statik kutuphaneler bir
XCFramework olarak vendor'lanir.

## Uretme — macOS gerekli

```bash
tool/build_native_crypto.sh ios
```

Script `aarch64-apple-ios` (cihaz) ve `aarch64-apple-ios-sim` (simulator)
hedeflerini derler, `xcodebuild -create-xcframework` ile birlestirir ve
`Artifacts/SecureChatCrypto.xcframework` altina koyar. Dosya toplamlari
`Artifacts/SHA256SUMS` icine yazilir.

Linux'ta bu adim atlanir: Apple hedefleri Xcode toolchain'i olmadan
baglanamaz.

## Xcode projesine baglama — Mac'te yapilacak

`ios/SQLCipher` ile ayni desen: yerel Swift paketi referansi.

1. Xcode'da `Runner.xcworkspace` acin.
2. Proje navigator'unde `ios/SecureChatCrypto` dizinini surukleyip birakin;
   Xcode onu `XCLocalSwiftPackageReference` olarak ekler.
3. `Runner` target → **General** → **Frameworks, Libraries, and Embedded
   Content** → `SecureChatCrypto` ekleyin. Statik kutuphane oldugu icin
   **Do Not Embed** secili kalmali.
4. `tool/verify_ios_on_macos.sh` kosturun.

`project.pbxproj` elle duzenlenmedi: UUID uretimi ve bolum sirasi elle
yazildiginda projeyi bozabiliyor. SQLCipher referansi
(`5C1FE000...` ile baslayan girdiler) nasil gorundugune ornek olarak
bakilabilir.

## Dogrulama

```bash
# Kutuphane ana ikiliye baglandi mi
nm -gU "$(find ~/Library/Developer/Xcode/DerivedData -name Runner -type f | head -1)" \
  | grep sc_abi_version
```

Dart tarafi `DynamicLibrary.process()` ile acar ve `sc_abi_version()`
degerini `expectedAbiVersion` ile karsilastirir; eslesmezse yanlis artefaktla
sessizce calismak yerine acik hata verir.
