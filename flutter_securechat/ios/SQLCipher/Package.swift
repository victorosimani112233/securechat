// swift-tools-version: 5.9
import PackageDescription

// SQLCipher 4.5.6 amalgamation'i uygulama ikilisine statik olarak baglar.
//
// Neden gerekli: iOS'ta sistemde yalniz DUZ SQLite bulunur. Duz SQLite
// `PRAGMA key` ifadesini TANIMADIGI pragmalar gibi sessizce yok sayar — hata
// dondurmez. Bu paket olmadan `EncryptedRecordStore` acilisi basarili gorunur
// ama veritabani SIFRESIZ yazilir. Android tarafinda ayni is
// `net.zetetic:sqlcipher-android:4.5.6` ile yapiliyor; surum bilerek ayni
// tutuldu.
//
// Neden CocoaPods degil: iOS derlemesi Swift Package Manager uzerinden
// yurutuluyor (`flutter config --enable-swift-package-manager`, kilit dosyasi
// `ios/Package.resolved.lock`). `sqlcipher_flutter_libs` paketi yalniz
// podspec sunuyor, Android tarafinda 4.10.0'a zorluyor ve simulator icin
// `VALID_ARCHS = x86_64` yaziyor — Apple Silicon simulatorunu kirar.
//
// Neden uzak bagimlilik degil: kaynak depoya gomulu oldugu icin derleme
// aninda ag erisimi gerekmez ve dogrulanacak bir indirme kalmaz. Kaynagin
// nereden geldigi ve saglama toplamlari `README.md` icinde.
let package = Package(
  name: "SQLCipher",
  platforms: [.iOS(.v15), .macOS(.v10_15)],
  products: [
    .library(name: "SQLCipher", targets: ["SQLCipher"])
  ],
  targets: [
    .target(
      name: "CSQLCipher",
      path: "Sources/CSQLCipher",
      sources: ["sqlite3.c"],
      publicHeadersPath: "include",
      cSettings: [
        // SQLCipher'i etkinlestiren zorunlu tanim.
        .define("SQLITE_HAS_CODEC"),
        // Apple platformlarinda sifreleme saglayicisi CommonCrypto.
        // Alternatifi OpenSSL'i ayrica paketlemek olurdu.
        .define("SQLCIPHER_CRYPTO_CC"),
        // GUVENLIK: gecici tablolar ve siralama tamponlari yalniz bellekte
        // tutulur. Varsayilan deger bunlari diske DUZ METIN olarak yazar;
        // sifreli bir veritabaninin yaninda duz metin gecici dosya birakmak
        // sifrelemeyi anlamsiz kilar.
        .define("SQLITE_TEMP_STORE", to: "2"),
        // Dart birden fazla isolate'ten erisebiliyor.
        .define("SQLITE_THREADSAFE", to: "1"),
        // Bu tanim olmadan mesgul-bekleme cozunurlugu 1 SANIYEYE duser
        // (`os_unix.c` icindeki `HAVE_USLEEP` dali). configure betigi normalde
        // bunu kendisi tanimlar; amalgamation'i dogrudan derledigimiz icin
        // elle vermek gerekiyor.
        .define("HAVE_USLEEP", to: "1"),
        // GUVENLIK: calisma aninda rastgele eklenti yuklemeyi kapatir.
        // `package:sqlite3` bu simgelere hic bakmiyor (FFI aramalari
        // `late final`, yani tembel; kullanilmayan simge cozulmez).
        .define("SQLITE_OMIT_LOAD_EXTENSION"),
      ],
      linkerSettings: [
        // CommonCrypto libSystem icinde; `SecRandomCopyBytes` Security
        // icinde; saglayici ayrica CoreFoundation'a bakiyor.
        .linkedFramework("Security"),
        .linkedFramework("CoreFoundation"),
      ]
    ),
    .target(
      name: "SQLCipher",
      dependencies: ["CSQLCipher"],
      path: "Sources/SQLCipher"
    ),
  ]
)
