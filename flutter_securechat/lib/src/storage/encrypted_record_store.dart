import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

/// Depo SIFRELI olarak acilamadi.
///
/// Bu istisna bilerek "acamadim" anlamina gelir, "sifresiz actim" anlamina
/// degil. Sifreleme saglanamiyorsa mesaj veritabanini duz metin yazmaktansa
/// hic acmamak dogru davranistir; cagiran taraf bunu kullaniciya bildirmeli.
class StorageEncryptionUnavailableException implements Exception {
  const StorageEncryptionUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'StorageEncryptionUnavailableException: $message';
}

/// SQLCipher uzerinde calisan, ARTIMLI yazan kayit deposu.
///
/// Neden gerekti: onceki depo tum veriyi tek bir sifreli JSON dosyasinda
/// tutuyordu ve her degisiklikte dosyanin TAMAMINI yeniden serilestirip
/// sifreleyip yaziyordu. Maliyet gecmisle birlikte buyuyordu — olculen
/// degerler: 50 mesajda 7 ms, 2 000 mesajda 120 ms. Gercek bir gelen mesaj
/// akisi uc yazma yaptigi icin 2 000 mesajlik gecmiste tek mesaj 338 ms
/// disk isi cikariyordu. Burada yalnizca DEGISEN kayitlar yazilir; maliyet
/// gecmis boyutundan bagimsizdir.
///
/// Neden bu kutuphane: `libsqlcipher.so` uygulamanin APK'sinda ZATEN var
/// (`net.zetetic:sqlcipher-android`, Gradle dogrulama listesinde kayitli).
/// `sqlite3` paketinin 3.x surumu kendi ikililerini derleme kancasiyla
/// getiriyor; bu, projenin bagimlilik dogrulama sistemini atlardi. 2.x
/// surumu kutuphaneyi disaridan almamiza izin verir, yani yeni bir native
/// artefakt eklenmez.
class EncryptedRecordStore {
  EncryptedRecordStore._(this._database);

  final Database _database;
  static bool _libraryResolved = false;

  /// YALNIZCA TEST: bir sonraki yazmayi islem ORTASINDA basarisiz kilar.
  ///
  /// "Bellek ve disk birlikte geri alinir" degismezi ancak gercek bir yazma
  /// hatasiyla sinanabilir. Dosyayi salt-okunur yapmak ise ise yaramiyor:
  /// POSIX izinleri acik dosya tanitici uzerinde denetlenmez. Disk doldurmak
  /// da bir test ortaminda uretilebilir degil. Bu yuzden dar, acikca
  /// isaretlenmis bir kanca birakildi.
  @visibleForTesting
  bool failMidTransaction = false;

  /// Kayit tablosu: koleksiyon + kimlik basina bir satir, degeri entity JSON.
  ///
  /// Entity'lerin hepsinde zaten `toJson`/`fromJson` var; iliskisel bir sema
  /// cikarmak 14 koleksiyon icin sutun sutun esleme demekti ve bu gecisin
  /// riskini gereksiz yere buyuturdu. Yazma maliyetini dusuren sey satir
  /// basina yazabilmek; sutunlarin tipli olmasi degil.
  static const _schema = '''
CREATE TABLE IF NOT EXISTS records (
  collection TEXT NOT NULL,
  id         TEXT NOT NULL,
  data       TEXT NOT NULL,
  PRIMARY KEY (collection, id)
);
CREATE INDEX IF NOT EXISTS records_collection_idx ON records (collection);
''';

  static Future<EncryptedRecordStore> open({
    required File file,
    required List<int> key,
  }) async {
    _resolveLibrary();
    await file.parent.create(recursive: true);
    final database = sqlite3.open(file.path);
    try {
      // Anahtari vermeden ONCE: baglanan kutuphane gercekten SQLCipher mi?
      assertCipherAvailable(database);
      // Ham anahtar: parola degil, zaten HKDF ile turetilmis 32 bayt.
      // SQLCipher'in kendi KDF'ini calistirmak hem gereksiz hem yavas olurdu.
      final hex = key
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      database.execute('PRAGMA key = "x\'$hex\'";');
      // Anahtarin dogrulugunu hemen dogrula: yanlis anahtarla ilk gercek
      // sorguya kadar hata gorunmezdi.
      database.select('SELECT count(*) FROM sqlite_master;');
      // WAL: yazmalar dosyanin sonuna eklenir, sayfalar yerinde yeniden
      // yazilmaz. Artimli yazmanin karsiligini burada aliyoruz.
      database.execute('PRAGMA journal_mode = WAL;');
      database.execute('PRAGMA synchronous = NORMAL;');
      database.execute(_schema);
    } catch (_) {
      // Acilan tanitici sizmasin: yanlis anahtar, SQLCipher yoklugu veya
      // bozuk dosya durumlarinin hepsi buradan gecer.
      database.dispose();
      rethrow;
    }
    return EncryptedRecordStore._(database);
  }

  /// Baglanan kutuphanenin SQLCipher oldugunu dogrular; degilse ACMAZ.
  ///
  /// Duz SQLite, TANIMADIGI pragmalari hata vermeden yok sayar — `PRAGMA key`
  /// dahil. Bu denetim olmadan duz SQLite'a baglanan bir platformda acilis
  /// BASARILI gorunur ve veritabani sifresiz yazilir; hicbir yerde iz kalmaz.
  /// iOS'ta tam olarak bu durum vardi: sistem kutuphanesi duz SQLite ve
  /// `_resolveLibrary` icin bir iOS dali yoktu.
  ///
  /// Ayirt edici: duz SQLite `PRAGMA cipher_version` icin HIC SATIR
  /// dondurmez, SQLCipher `4.5.6 community` gibi bir deger dondurur.
  @visibleForTesting
  static void assertCipherAvailable(Database database) {
    final ResultSet result;
    try {
      result = database.select('PRAGMA cipher_version;');
    } on SqliteException catch (error) {
      throw StorageEncryptionUnavailableException(
        'PRAGMA cipher_version calistirilamadi: ${error.message}',
      );
    }
    if (result.isEmpty || result.first.values.first == null) {
      throw const StorageEncryptionUnavailableException(
        'Baglanan SQLite kutuphanesi SQLCipher degil; sifrelenmemis bir '
        'veritabani yazmamak icin depo acilmadi.',
      );
    }
  }

  /// Her platformda SQLCipher'i baglar. Kutuphanenin adi ve yeri platforma
  /// gore degisir; hicbirinde varsayilan cozumlemeye GUVENILMEZ.
  ///
  /// Varsayilan cozumleme (`package:sqlite3` icindeki `_defaultOpen`) Apple
  /// platformlarinda sistemin DUZ SQLite'ina duser. Duz SQLite `PRAGMA key`i
  /// sessizce yok saydigi icin sonuc, hata vermeyen ve sifresiz yazan bir
  /// veritabani olur. `assertCipherAvailable` bu durumu yakalar; buradaki
  /// overrideler ise hic olusmamasini saglar.
  static void _resolveLibrary() {
    if (_libraryResolved) return;
    _libraryResolved = true;
    sqlite_open.open
      ..overrideFor(
        sqlite_open.OperatingSystem.android,
        // APK icinde: net.zetetic:sqlcipher-android.
        () => DynamicLibrary.open('libsqlcipher.so'),
      )
      ..overrideFor(
        sqlite_open.OperatingSystem.linux,
        // Dagitim paketi; testler bu yolda kosuyor.
        () => _openFirst(_hostCandidates(const [
          'libsqlcipher.so.0',
          'libsqlcipher.so',
        ])),
      )
      ..overrideFor(
        sqlite_open.OperatingSystem.iOS,
        // `ios/SQLCipher` paketi uygulama IKILISINE statik baglanir, ayri bir
        // dylib yoktur. `process()` once ana ikiliye bakar, dolayisiyla
        // gomulu SQLCipher iOS'un sistem SQLite'ini golgeler.
        DynamicLibrary.process,
      )
      ..overrideFor(
        sqlite_open.OperatingSystem.macOS,
        // Mac yalniz GELISTIRME makinesi: `flutter test` burada kosuyor.
        // Homebrew iki farkli one ek kullanir (Apple Silicon /opt/homebrew,
        // Intel /usr/local) ve ikisi de dyld'nin varsayilan arama yolunda
        // DEGILDIR — bu yuzden tam yollar denenir.
        () => _openFirst(_hostCandidates(const [
          'libsqlcipher.dylib',
          '/opt/homebrew/lib/libsqlcipher.dylib',
          '/opt/homebrew/opt/sqlcipher/lib/libsqlcipher.dylib',
          '/usr/local/lib/libsqlcipher.dylib',
          '/usr/local/opt/sqlcipher/lib/libsqlcipher.dylib',
        ])),
      );
  }

  /// Kutuphanenin yerini dısarıdan bildirmeye yarayan degisken.
  ///
  /// Gelistirme makinesinde SQLCipher her zaman bir paket yoneticisinden
  /// gelmiyor. Homebrew kurulumu ag ister; kisitli baglantida
  /// `tool/build_sqlcipher_macos.sh` depodaki gomulu kaynaktan yerel bir
  /// kutuphane uretiyor ve o dosya standart yollarin hicbirinde olmuyor.
  /// `/usr/local/lib` altina kopyalamak sudo gerektirir; `DYLD_LIBRARY_PATH`
  /// ise macOS'ta SIP tarafindan temizlenebiliyor. Acik bir degisken ikisini
  /// de gerektirmez.
  static const libraryPathVariable = 'SECURECHAT_SQLCIPHER_PATH';

  /// Once degiskenin gosterdigi yol, sonra platformun alisildik yerleri.
  static List<String> _hostCandidates(List<String> defaults) {
    final override = Platform.environment[libraryPathVariable];
    return [
      if (override != null && override.isNotEmpty) override,
      ...defaults,
    ];
  }

  /// Adaylari sirayla dener, ilk acilani dondurur.
  ///
  /// Hicbiri acilmazsa denenen TUM yollari iceren bir hata firlatir: tek
  /// adayin adini tasiyan `ArgumentError` mesaji, kurulumun neresinin eksik
  /// oldugunu anlatmaya yetmiyordu.
  static DynamicLibrary _openFirst(List<String> candidates) {
    final failures = <String>[];
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError catch (error) {
        failures.add('$candidate (${error.message})');
      }
    }
    throw StorageEncryptionUnavailableException(
      'SQLCipher kutuphanesi bulunamadi. Denenen yollar: '
      '${failures.join(', ')}',
    );
  }

  /// Bir koleksiyonun tamamini kimlik -> JSON olarak okur.
  Map<String, Map<String, Object?>> loadCollection(String collection) {
    final rows = _database.select(
      'SELECT id, data FROM records WHERE collection = ?;',
      [collection],
    );
    return {
      for (final row in rows)
        row['id'] as String:
            (jsonDecode(row['data'] as String) as Map).cast<String, Object?>(),
    };
  }

  /// Degisen kayitlari tek islemde yazar.
  ///
  /// [upserts] koleksiyon -> (kimlik -> JSON), [deletions] koleksiyon ->
  /// silinecek kimlikler. Islem atomiktir: yarim yazilmis bir durum kalmaz.
  ///
  /// [clearFirst] verildiginde once tum kayitlar silinir. Silme ve yeniden
  /// yazma AYNI islemde olmali: ayri yapilsaydi, araya giren bir hata
  /// deponun bos kalmasina yol acardi.
  void applyChanges({
    required Map<String, Map<String, Map<String, Object?>>> upserts,
    required Map<String, Set<String>> deletions,
    bool clearFirst = false,
  }) {
    if (upserts.isEmpty && deletions.isEmpty && !clearFirst) return;
    _database.execute('BEGIN IMMEDIATE;');
    try {
      if (clearFirst) _database.execute('DELETE FROM records;');
      // `INSERT OR REPLACE`, `ON CONFLICT ... DO UPDATE` yerine bilerek
      // kullanilir: UPSERT sozdizimi SQLite 3.24+ gerektirir ve test
      // ortamindaki sistem SQLCipher'i (3.4.1) bunu desteklemiyor. Tabloda
      // yabanci anahtar veya tetikleyici olmadigi icin ikisi esdegerdir.
      final insert = _database.prepare(
        'INSERT OR REPLACE INTO records (collection, id, data) '
        'VALUES (?, ?, ?);',
      );
      final delete = _database.prepare(
        'DELETE FROM records WHERE collection = ? AND id = ?;',
      );
      try {
        for (final entry in upserts.entries) {
          for (final record in entry.value.entries) {
            insert.execute([entry.key, record.key, jsonEncode(record.value)]);
          }
        }
        for (final entry in deletions.entries) {
          for (final id in entry.value) {
            delete.execute([entry.key, id]);
          }
        }
        if (failMidTransaction) {
          failMidTransaction = false;
          throw StateError('injected storage failure');
        }
      } finally {
        insert.dispose();
        delete.dispose();
      }
      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Gecis dogrulamasi icin toplam kayit sayisi.
  int count() =>
      _database.select('SELECT count(*) AS n FROM records;').first['n'] as int;

  void close() {
    // WAL'i ana dosyaya isle. Aksi halde son yazmalar yalnizca `-wal` yan
    // dosyasinda kalir; veritabani dosyasinin tek basina kopyalanmasi
    // (yedek, adli inceleme, testteki bozulma senaryosu) EKSIK bir depo
    // uretir ve bu depo bos gibi acilir.
    _database.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    _database.dispose();
  }
}
