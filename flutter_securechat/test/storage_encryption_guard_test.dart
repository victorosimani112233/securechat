import 'dart:ffi';
import 'dart:io';

import 'package:flutter_securechat/src/storage/encrypted_record_store.dart';
import 'package:flutter_test/flutter_test.dart';
// Paket ici import: `FfiSqlite3` fabrikasi `package:sqlite3/sqlite3.dart`
// tarafindan disa aktarilmiyor ama BELIRLI bir kutuphaneye baglanmis bir
// ornek uretmenin tek yolu bu. Bu testin butun degeri gercek bir DUZ SQLite
// kutuphanesine baglanabilmesinde; taklit bir nesne ile yapilsaydi asil
// tehlikeyi — iOS'un sistem kutuphanesinin davranisini — hic sinamazdi.
// ignore: implementation_imports
import 'package:sqlite3/src/ffi/implementation.dart';

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
    final plain = FfiSqlite3(DynamicLibrary.open('libsqlite3.so.0'));
    final path = '${workspace.path}/plain.db';
    final database = plain.open(path);
    addTearDown(database.dispose);

    // Hata YOK: duz SQLite tanimadigi pragmayi sessizce yok sayar. Kirilgan
    // nokta tam olarak burasi.
    database.execute('PRAGMA key = "x\'${'ab' * 32}\'";');
    database.execute('CREATE TABLE t (v TEXT);');
    database.execute("INSERT INTO t VALUES ('GIZLI_MESAJ_ICERIGI');");
    database.dispose();

    final bytes = File(path).readAsBytesSync();
    final raw = String.fromCharCodes(bytes);
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
    final plain = FfiSqlite3(DynamicLibrary.open('libsqlite3.so.0'));
    final database = plain.openInMemory();
    addTearDown(database.dispose);

    expect(
      () => EncryptedRecordStore.assertCipherAvailable(database),
      throwsA(isA<StorageEncryptionUnavailableException>()),
    );
  });

  test('denetim SQLCipher baglantisini gecirir', () {
    final cipher = FfiSqlite3(DynamicLibrary.open('libsqlcipher.so.0'));
    final database = cipher.openInMemory();
    addTearDown(database.dispose);

    expect(
      () => EncryptedRecordStore.assertCipherAvailable(database),
      returnsNormally,
    );
    expect(database.select('PRAGMA cipher_version;'), isNotEmpty);
  });

  envOverrideTests();

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
}

/// Kutuphanenin yeri ortam degiskeniyle bildirilebilmeli.
///
/// Gelistirme makinesinde SQLCipher her zaman bir paket yoneticisinden
/// gelmiyor: Homebrew kurulumu ag ister ve kisitli baglantida kutuphane
/// depodaki gomulu kaynaktan elle uretiliyor. O dosya standart yollarin
/// hicbirinde olmadigi icin disaridan bildirilebilmesi gerekiyor.
void envOverrideTests() {
  test('degisken adi sozlesmesi sabit', () {
    expect(
      EncryptedRecordStore.libraryPathVariable,
      'SECURECHAT_SQLCIPHER_PATH',
      reason:
          'tool/build_sqlcipher_macos.sh ve belgeler bu adi kullaniyor; '
          'degistirilirse ikisi de guncellenmeli',
    );
  });
}
