// swift-tools-version: 5.9
import PackageDescription

// Elcim kripto cekirdegini uygulama ikilisine statik olarak baglar.
//
// NEDEN BINARY TARGET: `ios/SQLCipher` paketi kaynagi (C amalgamation'i)
// vendor'layip Xcode'a derletiyor. Burada ayni sey yapilamaz, cunku cekirdek
// Rust'ta ve Xcode Rust derlemez. Bu yuzden onceden derlenmis statik
// kutuphaneler bir XCFramework'e paketlenip vendor'lanir; derleme aninda ag
// erisimi yine gerekmez.
//
// XCFramework'u `tool/build_native_crypto.sh ios` uretir ve YALNIZ macOS'ta
// kosar. Artifacts/ dizini bos ise paket cozumlenmez; once o scripti
// kosturun.
//
// Dart tarafi iOS'ta `DynamicLibrary.process()` aciyor: kutuphane ana
// ikiliye statik baglandigi icin ayri bir dylib yoktur.
let package = Package(
  name: "SecureChatCrypto",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "SecureChatCrypto", targets: ["SecureChatCryptoBinary"])
  ],
  targets: [
    .binaryTarget(
      name: "SecureChatCryptoBinary",
      path: "Artifacts/SecureChatCrypto.xcframework"
    )
  ]
)
