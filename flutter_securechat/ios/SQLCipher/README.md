# Gömülü SQLCipher (iOS / macOS)

Bu dizin SQLCipher **4.5.6** amalgamation'ını içerir ve uygulama ikilisine
statik olarak bağlanır.

## Neden gerekli

iOS'ta sistem kütüphanesi **düz SQLite**'tır. Düz SQLite, tanımadığı
pragmaları hata vermeden yok sayar — `PRAGMA key` dahil. Bu paket olmadan:

```
sqlite3_open(...)                   → SQLITE_OK
PRAGMA key = "x'...'"               → SQLITE_OK   (sessizce yok sayılır)
SELECT count(*) FROM sqlite_master  → çalışır
```

yani açılış başarılı görünür ve mesaj veritabanı **şifresiz** yazılır.
Doğrulanmış davranış, düz `sqlite3` ile:

```
$ head -c 16 db
00000000: 5351 4c69 7465 2066 6f72 6d61 7420 3300   SQLite format 3.
$ strings db | grep -c GIZLI_MESAJ_ICERIGI
1
```

Aynı test bu amalgamation ile derlendiğinde başlık rastgele bayt, düz metin
eşleşmesi 0.

## Sürüm neden 4.5.6

Android tarafı `net.zetetic:sqlcipher-android:4.5.6` kullanıyor
(`android/app/build.gradle.kts`). İki platform aynı sürümde tutuldu.

## Neden CocoaPods paketi değil

`sqlcipher_flutter_libs` üç nedenle uygun değil:

1. Yalnız podspec sunuyor; bu projenin iOS derlemesi Swift Package Manager
   üzerinden yürüyor (`ios/Package.resolved.lock`, `validate_swift_package_lock.dart`).
2. Android tarafını `4.10.0`'a zorluyor — mevcut `4.5.6` pinine ve Gradle
   doğrulama listesine çakışıyor.
3. Podspec'i `VALID_ARCHS[sdk=iphonesimulator*] = x86_64` yazıyor; Apple
   Silicon simülatörünü kırar.

## Kaynak ve yeniden üretim

| | |
|---|---|
| Kaynak | `https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.5.6.tar.gz` |
| Arşiv sha256 | `e4a527e38e67090c1d2dc41df28270d16c15f7ca5210a3e7ec4c4b8fda36e28f` |
| Üretim | `./configure --enable-tempstore=yes CFLAGS="-DSQLITE_HAS_CODEC" && make sqlite3.c` |

Yeniden üretmek veya depodakiyle karşılaştırmak için:

```bash
./tool/vendor_sqlcipher.sh --check   # karşılaştırır, yazmaz
./tool/vendor_sqlcipher.sh           # yeniden üretir
```

Üretilen dosyaların sha256 değerleri:

```
7af665dc951ec807d6d1f189d047c542ceb867fc9109919e39e0c6817ac51c55  Sources/CSQLCipher/sqlite3.c
ff3c42d15dd2b4b04cf69f399f766ff0602743e67ca3087a326a408cd7b9ebe1  Sources/CSQLCipher/include/sqlite3.h
b184dd1586d935133d37ad76fa353faf0a1021ff2fdedeedcc3498fff74bbb94  Sources/CSQLCipher/include/sqlite3ext.h
```

## Derleme tanımları

`Package.swift` içinde gerekçeleriyle birlikte. Güvenlik açısından kritik
olan ikisi:

- `SQLITE_TEMP_STORE=2` — geçici tablolar diske **düz metin** yazılmaz.
- `SQLITE_OMIT_LOAD_EXTENSION` — çalışma anında eklenti yükleme kapalı.

## Ölü kod ayıklamasına karşı

Tüm kullanım Dart FFI üzerinden olduğu için Swift/ObjC tarafından hiçbir
SQLCipher simgesine başvurulmaz ve bağlayıcı statik kütüphaneyi tamamen
atabilir. `AppDelegate` bunu önlemek için `SQLCipherRuntime.ensureLinked()`
çağırır. Dart tarafındaki `PRAGMA cipher_version` denetimi ise son savunma
hattıdır: bağlanan kütüphane SQLCipher değilse depo **açılmaz**.
