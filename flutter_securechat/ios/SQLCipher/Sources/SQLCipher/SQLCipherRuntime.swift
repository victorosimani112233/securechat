import CSQLCipher
import Foundation

/// SQLCipher'in uygulama ikilisinde KALMASINI garanti eder.
///
/// Statik kutuphaneler baglayiciya "hicbir simgesine basvurulmayan nesne
/// dosyasini atla" der. `sqlite3.c` tek bir nesne dosyasi oldugu icin TEK bir
/// simgeye basvurmak SQLCipher'in tamamini ikiliye ceker. Swift veya
/// Objective-C tarafindan hic cagrilmadigi icin — tum kullanim Dart FFI
/// uzerinden — bu basvuru olmadan baglayici sessizce her seyi atar ve
/// uygulama iOS'un DUZ SQLite'ina duser.
///
/// Dart tarafi bu duruma karsi ayrica `PRAGMA cipher_version` denetimi
/// yapiyor; oradaki denetim son savunma hatti, buradaki basvuru ise sorunun
/// hic olusmamasi icin.
public enum SQLCipherRuntime {
  /// Baglanan SQLite kutuphanesinin surumu, orn. `3.41.2`.
  @discardableResult
  public static func ensureLinked() -> String {
    guard let version = sqlite3_libversion() else { return "" }
    return String(cString: version)
  }

  /// Baglanan kutuphanenin gercekten SQLCipher olup olmadigi.
  ///
  /// Duz SQLite `PRAGMA cipher_version` icin HIC SATIR dondurmez; SQLCipher
  /// ise `4.5.6 community` gibi bir deger dondurur. Ayni denetim Dart
  /// tarafinda da yapilir — bu surum yalniz Runner XCTest'inden cagrilabilsin
  /// diye burada.
  public static func cipherVersion() -> String? {
    var database: OpaquePointer?
    guard sqlite3_open(":memory:", &database) == SQLITE_OK else { return nil }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA cipher_version;", -1, &statement, nil) == SQLITE_OK
    else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW,
          let value = sqlite3_column_text(statement, 0)
    else { return nil }
    return String(cString: value)
  }
}
