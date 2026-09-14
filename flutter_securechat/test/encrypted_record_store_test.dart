import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/encrypted_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Depolama artik ARTIMLI: yalnizca degisen kayitlar yazilir.
///
/// Onceki depo her degisiklikte tum veriyi yeniden serilestirip sifreleyip
/// yaziyordu; maliyet gecmisle buyuyordu (2 000 mesajlik gecmiste tek gelen
/// mesaj 338 ms disk isi). Bu testler hem sifrelemenin hem de artimliligin
/// korundugunu dogrular.
void main() {
  late Directory directory;
  late List<int> key;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('record_store_');
    key = await LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 3)),
    ).deriveDatabaseKey();
  });

  tearDown(() async => directory.delete(recursive: true));

  File dbFile() => File('${directory.path}/store.db');

  test('veri diskte sifreli durur ve anahtarsiz okunamaz', () async {
    final store = await EncryptedRecordStore.open(file: dbFile(), key: key);
    store.applyChanges(
      upserts: {
        'messages': {
          'm1': {'id': 'm1', 'content': 'COK-GIZLI-ICERIK'},
        },
      },
      deletions: const {},
    );
    store.close();

    final bytes = await dbFile().readAsBytes();
    expect(
      String.fromCharCodes(bytes).contains('COK-GIZLI-ICERIK'),
      isFalse,
      reason: 'mesaj icerigi diskte duz metin olarak duruyor',
    );

    final wrongKey = List<int>.filled(32, 9);
    await expectLater(
      EncryptedRecordStore.open(file: dbFile(), key: wrongKey),
      throwsA(anything),
      reason: 'yanlis anahtarla acilmamali',
    );
  });

  test('kapatip acinca kayitlar geri gelir', () async {
    var store = await EncryptedRecordStore.open(file: dbFile(), key: key);
    store.applyChanges(
      upserts: {
        'conversations': {
          'c1': {'id': 'c1', 'peerName': 'Ayse'},
        },
        'messages': {
          'm1': {'id': 'm1', 'content': 'merhaba'},
          'm2': {'id': 'm2', 'content': 'selam'},
        },
      },
      deletions: const {},
    );
    store.close();

    store = await EncryptedRecordStore.open(file: dbFile(), key: key);
    expect(store.loadCollection('messages'), hasLength(2));
    expect(store.loadCollection('conversations')['c1']!['peerName'], 'Ayse');

    // Silme ve guncelleme
    store.applyChanges(
      upserts: {
        'messages': {
          'm1': {'id': 'm1', 'content': 'duzenlendi'},
        },
      },
      deletions: {
        'messages': {'m2'},
      },
    );
    final messages = store.loadCollection('messages');
    expect(messages, hasLength(1));
    expect(messages['m1']!['content'], 'duzenlendi');
    store.close();
  });

  test('yazma maliyeti gecmis buyudukce artmaz', () async {
    final store = await EncryptedRecordStore.open(file: dbFile(), key: key);
    addTearDown(store.close);
    final body = 'x' * 200;

    int writeCostAt(int existing) {
      final watch = Stopwatch()..start();
      store.applyChanges(
        upserts: {
          'messages': {
            'probe-$existing': {'id': 'probe-$existing', 'content': body},
          },
        },
        deletions: const {},
      );
      return watch.elapsedMicroseconds;
    }

    void fill(int from, int to) {
      store.applyChanges(
        upserts: {
          'messages': {
            for (var index = from; index < to; index++)
              'm$index': {'id': 'm$index', 'content': body},
          },
        },
        deletions: const {},
      );
    }

    fill(0, 200);
    final small = writeCostAt(200);
    fill(200, 5000);
    final large = writeCostAt(5000);

    // Eski depoda bu oran gecmisle dogru orantili buyuyordu (50 -> 2 000
    // mesajda 17 kat). Artimli yazmada sabit kalmali; olcum gurultusune
    // genis pay birakiliyor.
    expect(
      large,
      lessThan(small * 10 + 20000),
      reason: '200 kayitta $small us, 5000 kayitta $large us',
    );
  });
}
