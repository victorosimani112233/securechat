import 'dart:ffi';
import 'dart:io';

import 'package:flutter_securechat/src/storage/encrypted_record_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
// Paket ici import: `FfiSqlite3` fabrikasi `package:sqlite3/sqlite3.dart`
// tarafindan disa aktarilmiyor ama BELIRLI bir kutuphaneye baglanmis bir
// ornek uretmenin tek yolu bu. Bu testin butun degeri gercek bir DUZ SQLite
// kutuphanesine baglanabilmesinde; taklit bir nesne ile yapilsaydi asil
// tehlikeyi — Apple platformlarinin sistem kutuphanesinin davranisini — hic
// sinamazdi.
// ignore: implementation_imports
import 'package:sqlite3/src/ffi/implementation.dart';

/// Sistemin DUZ SQLite kutuphanesi. Adi platforma gore degisir.
///
/// Bu kutuphane her Unix'te bulunur; SQLCipher'in aksine ayrica kurulmaz.
/// Bulunamazsa test atlanmaz, basarisiz olur: "duz SQLite tehlikeli"
/// degismezi sinanamiyorsa bunun sessiz kalmamasi gerekir.
DynamicLibrary _openPlainSqlite() {
  final candidates = <String>[
    if (Platform.isMacOS) ...['libsqlite3.dylib', '/usr/lib/libsqlite3.dylib'],
    if (Platform.isLinux) ...['libsqlite3.so.0', 'libsqlite3.so'],
  ];
  final failures = <String>[];
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError catch (error) {
      failures.add('$candidate (${error.message})');
    }
  }
  throw StateError('Duz SQLite bulunamadi. Denenenler: ${failures.join(', ')}');
}

/// Depo acilisindaki "baglanan kutuphane gercekten SQLCipher mi" denetimi.
///
/// Bu denetim olmadan iOS'ta veritabani sifresiz yaziliyordu ve acilis
/// basarili gorunuyordu. Buradaki testler once tehlikenin gercek oldugunu
/// gosterir, sonra denetimin onu yakaladigini.
void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('cipher_guard');
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  test('duz SQLite PRAGMA key kabul eder ama DUZ METIN yazar', () {
    final plain = FfiSqlite3(_openPlainSqlite());
    final path = '${workspace.path}/plain.db';
    final database = plain.open(path);

    // Hata YOK: duz SQLite tanimadigi pragmayi sessizce yok sayar. Kirilgan
    // nokta tam olarak burasi.
    database.execute('PRAGMA key = "x\'${'ab' * 32}\'";');
    database.execute('CREATE TABLE t (v TEXT);');
    database.execute("INSERT INTO t VALUES ('GIZLI_MESAJ_ICERIGI');");
    database.dispose();

    final raw = String.fromCharCodes(File(path).readAsBytesSync());
    expect(
      raw.startsWith('SQLite format 3'),
      isTrue,
      reason: 'sifreli bir dosyada duz SQLite basligi bulunmamali',
    );
    expect(
      raw.contains('GIZLI_MESAJ_ICERIGI'),
      isTrue,
      reason: 'duz SQLite icerigi sifrelemeden yazar',
    );
  });

  test('denetim duz SQLite baglantisini reddeder', () {
    final plain = FfiSqlite3(_openPlainSqlite());
    final database = plain.openInMemory();
    addTearDown(database.dispose);

    expect(
      () => EncryptedRecordStore.assertCipherAvailable(database),
      throwsA(isA<StorageEncryptionUnavailableException>()),
    );
  });

  test('degisken adi sozlesmesi sabit', () {
    // `tool/build_sqlcipher_macos.sh` ve belgeler bu adi kullaniyor.
    expect(
      EncryptedRecordStore.libraryPathVariable,
      'SECURECHAT_SQLCIPHER_PATH',
    );
  });

  test('gercek depo hem acilir hem diske sifreli yazar', () async {
    final file = File('${workspace.path}/store.db');
    final store = await EncryptedRecordStore.open(
      file: file,
      key: List<int>.generate(32, (index) => index),
    );
    store.applyChanges(
      upserts: {
        'messages': {
          'm1': <String, Object?>{'body': 'GIZLI_MESAJ_ICERIGI'},
        },
      },
      deletions: const {},
    );
    store.close();

    final raw = String.fromCharCodes(file.readAsBytesSync());
    expect(raw.startsWith('SQLite format 3'), isFalse);
    expect(raw.contains('GIZLI_MESAJ_ICERIGI'), isFalse);
  });

  test('denetim SQLCipher baglantisini gecirir', () async {
    // Deponun kendi cozumlemesini kullaniyoruz: kutuphane yollari platforma
    // gore degisiyor ve burada tekrar yazilsaydi ikisi zamanla ayrisirdi.
    // Bir kez acmak `_resolveLibrary`'yi tetikler, sonrasinda genel
    // `sqlite3` ornegi de SQLCipher'a bagli olur.
    final store = await EncryptedRecordStore.open(
      file: File('${workspace.path}/resolve.db'),
      key: List<int>.generate(32, (index) => index),
    );
    store.close();

    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    expect(
      () => EncryptedRecordStore.assertCipherAvailable(database),
      returnsNormally,
    );
    expect(database.select('PRAGMA cipher_version;'), isNotEmpty);
  });
}
