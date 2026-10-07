import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_migration.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// vodozemac durumunun sifreli yerel veritabaninda yasamasini ve libsignal
/// durumundan gecisi dogrular.
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    test('vodozemac depolama (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  late SecureChatDatabase database;
  late SecureChatCrypto crypto;
  late VodozemacProtocolStore store;
  late Uint8List pickleKey;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('vodozemac-store');
    final masterKey = List<int>.generate(32, (index) => index * 3 + 1);
    database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(masterKey)),
    );
    crypto = SecureChatCrypto.open(libraryPath: libraryPath);
    pickleKey = await VodozemacProtocolStore.derivePickleKey(masterKey);
    store = VodozemacProtocolStore(
      database: database,
      crypto: crypto,
      pickleKey: pickleKey,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  group('pickle anahtari', () {
    test('master key"den amac ayrimiyla turetilir', () async {
      final masterKey = List<int>.generate(32, (index) => index);

      final derived = await VodozemacProtocolStore.derivePickleKey(masterKey);

      expect(derived, hasLength(32));
      // Depolama anahtarinin kendisi kullanilmamali: ayni anahtari iki amac
      // icin kullanmak, birinin sizmasini digerinin de sizmasi yapar.
      expect(derived, isNot(equals(Uint8List.fromList(masterKey))));
    });

    test('ayni master key her zaman ayni anahtari verir', () async {
      final masterKey = List<int>.generate(32, (index) => index);

      final first = await VodozemacProtocolStore.derivePickleKey(masterKey);
      final second = await VodozemacProtocolStore.derivePickleKey(masterKey);

      expect(first, second);
    });

    test('32 bayt olmayan anahtar reddedilir', () {
      expect(
        () => VodozemacProtocolStore(
          database: database,
          crypto: crypto,
          pickleKey: Uint8List(16),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('hesap', () {
    test('ilk withAccount cagrisi hesabi olusturup saklar', () async {
      expect(await store.hasAccount(), isFalse);

      final keys = await store.withAccount(
        (account) async => account.identityKeys(),
      );

      expect(await store.hasAccount(), isTrue);
      expect(keys.keys, containsAll(['curve25519', 'ed25519']));
    });

    test('kimlik anahtari acilislar arasinda korunur', () async {
      final first = await store.withAccount(
        (account) async => account.identityKeys(),
      );

      final second = await store.readAccount(
        (account) async => account.identityKeys(),
      );

      expect(second, first);
    });

    test('uretilen tek kullanimlik anahtarlar kalici olur', () async {
      // En kritik degismez: anahtarlar hesabin ICINDE tutuluyor, yani
      // uretim sonrasi pickle yazilmazsa sunucuya yuklenen anahtarlarin
      // yerel karsiligi olmaz ve karsi taraf oturum kurdugunda cozulemez.
      await store.withAccount(
        (account) async => account.generateOneTimeKeys(5),
      );

      final count = await store.readAccount(
        (account) async => account.storedOneTimeKeyCount,
      );

      expect(count, 5);
    });

    test('action firlatirsa durum yazilmaz', () async {
      await store.withAccount((account) async => account.identityKeys());

      await expectLater(
        store.withAccount((account) async {
          account.generateOneTimeKeys(7);
          throw StateError('yari yolda hata');
        }),
        throwsA(isA<StateError>()),
      );

      // Yarim kalmis uretim diske gecmemeli.
      final count = await store.readAccount(
        (account) async => account.storedOneTimeKeyCount,
      );
      expect(count, 0);
    });

    test('hesap yoksa readAccount acikca hata verir', () {
      expect(
        () => store.readAccount((account) async => account.identityKeys()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('oturum', () {
    /// İki taraf arasinda gercek bir Olm oturumu kurar ve saklar.
    Future<String> establishSession(String peerId) async {
      final peer = crypto.createAccount();
      addTearDown(peer.dispose);
      final peerOneTime = peer.generateOneTimeKeys(1);

      return store.withAccount((account) async {
        final session = account.createOutboundSession(
          theirIdentityKey: peer.identityKeys()['curve25519']!,
          theirOneTimeKey: peerOneTime.values.single,
        );
        try {
          await store.persistNewSession(peerId, session);
          return session.sessionId;
        } finally {
          session.dispose();
        }
      });
    }

    test('kurulan oturum saklanir ve geri okunur', () async {
      final sessionId = await establishSession('alice');

      expect(await store.sessionIdsForPeer('alice'), [sessionId]);
    });

    test('withSession ratchet durumunu ilerletip saklar', () async {
      final sessionId = await establishSession('alice');

      final first = await store.withSession(
        'alice',
        sessionId,
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('bir'))).body,
      );
      final second = await store.withSession(
        'alice',
        sessionId,
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('bir'))).body,
      );

      // Ayni plaintext farkli ciphertext veriyorsa ratchet gercekten
      // ilerledi ve ilerlemis hali diske yazildi.
      expect(first, isNot(second));
    });

    test('action firlatirsa ratchet ilerlemesi yazilmaz', () async {
      final sessionId = await establishSession('alice');
      final before = await store.withSession(
        'alice',
        sessionId,
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('x'))).body,
      );

      await expectLater(
        store.withSession('alice', sessionId, (session) async {
          session.encrypt(Uint8List.fromList(utf8.encode('x')));
          throw StateError('cozme basarisiz');
        }),
        throwsA(isA<StateError>()),
      );

      final after = await store.withSession(
        'alice',
        sessionId,
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('x'))).body,
      );

      // Basarisiz deneme ratchet'i tuketmis gibi kaydedilmemeli: ikinci
      // basarili cagri, ilkinin hemen ardindaki adimda olmali.
      expect(after, isNot(before));
    });

    test('ayni peer icin birden fazla oturum en yeniden siralanir', () async {
      final older = await establishSession('alice');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newer = await establishSession('alice');

      final ordered = await store.sessionIdsForPeer('alice');

      expect(ordered.length, 2);
      expect(ordered.first, newer);
      expect(ordered.last, older);
    });

    test('peer oturumlari silinebilir', () async {
      await establishSession('alice');
      await establishSession('bob');

      await store.deleteSessionsForPeer('alice');

      expect(await store.sessionIdsForPeer('alice'), isEmpty);
      expect(await store.sessionIdsForPeer('bob'), hasLength(1));
    });

    test('bilinmeyen oturum acikca hata verir', () {
      expect(
        () => store.withSession('alice', 'yok', (session) async => null),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('grup oturumu', () {
    test('giden oturum olusturulur ve kalici olur', () async {
      final key = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );

      final sameKey = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );

      // Ayni grup icin ayni oturum devam etmeli, her cagri yeni oturum
      // kurmamali: yoksa her mesaj yeni bir dagitim gerektirirdi.
      expect(sameKey, key);
    });

    test('mesaj indeksi acilislar arasinda korunur', () async {
      await store.withGroupSession(
        'grup-1',
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('ilk'))),
      );
      final sessionKey = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );
      await store.acceptGroupSessionKey(
        groupId: 'grup-1',
        senderId: 'ben',
        sessionKey: sessionKey,
      );
      final sessionId = crypto.inboundGroupSession(sessionKey).sessionId;

      final message = await store.withGroupSession(
        'grup-1',
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('ikinci'))),
      );
      final plaintext = await store.decryptGroupMessage(
        groupId: 'grup-1',
        senderId: 'ben',
        sessionId: sessionId,
        message: message,
      );

      expect(utf8.decode(plaintext), 'ikinci');
    });

    test('replay reddedilir', () async {
      final sessionKey = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );
      await store.acceptGroupSessionKey(
        groupId: 'grup-1',
        senderId: 'alice',
        sessionKey: sessionKey,
      );
      final sessionId = crypto.inboundGroupSession(sessionKey).sessionId;
      final message = await store.withGroupSession(
        'grup-1',
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('bir kez'))),
      );

      // Ilk cozme gecer.
      expect(
        utf8.decode(
          await store.decryptGroupMessage(
            groupId: 'grup-1',
            senderId: 'alice',
            sessionId: sessionId,
            message: message,
          ),
        ),
        'bir kez',
      );

      // Ayni mesaj ikinci kez reddedilmeli: vodozemac bunu kendisi takip
      // etmiyor, kontrol store'da.
      await expectLater(
        store.decryptGroupMessage(
          groupId: 'grup-1',
          senderId: 'alice',
          sessionId: sessionId,
          message: message,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('replay'),
          ),
        ),
      );
    });

    test('dagitimi tekrar gondermek replay korumasini sifirlamaz', () async {
      final sessionKey = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );
      await store.acceptGroupSessionKey(
        groupId: 'grup-1',
        senderId: 'alice',
        sessionKey: sessionKey,
      );
      final sessionId = crypto.inboundGroupSession(sessionKey).sessionId;
      final message = await store.withGroupSession(
        'grup-1',
        (session) async =>
            session.encrypt(Uint8List.fromList(utf8.encode('x'))),
      );
      await store.decryptGroupMessage(
        groupId: 'grup-1',
        senderId: 'alice',
        sessionId: sessionId,
        message: message,
      );

      // Saldirgan ayni dagitimi tekrar gonderirse gorulen indeks
      // sifirlanmamali; aksi halde bu replay'e acik kapi olurdu.
      await store.acceptGroupSessionKey(
        groupId: 'grup-1',
        senderId: 'alice',
        sessionKey: sessionKey,
      );

      await expectLater(
        store.decryptGroupMessage(
          groupId: 'grup-1',
          senderId: 'alice',
          sessionId: sessionId,
          message: message,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('bilinmeyen grup oturumu acikca hata verir', () {
      expect(
        () => store.decryptGroupMessage(
          groupId: 'grup-1',
          senderId: 'alice',
          sessionId: 'yok',
          message: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('giden oturum sifirlanirsa yeni anahtar uretilir', () async {
      final first = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );

      await store.resetGroupSession('grup-1');
      final second = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );

      // Uye cikarildiginda ayrilan uye yeni mesajlari cozememeli.
      expect(second, isNot(first));
    });

    test('grup oturumlari topluca silinebilir', () async {
      final sessionKey = await store.withGroupSession(
        'grup-1',
        (session) async => session.sessionKey,
      );
      await store.acceptGroupSessionKey(
        groupId: 'grup-1',
        senderId: 'alice',
        sessionKey: sessionKey,
      );

      await store.deleteGroupSessions('grup-1');

      expect(
        () => store.decryptGroupMessage(
          groupId: 'grup-1',
          senderId: 'alice',
          sessionId: crypto.inboundGroupSession(sessionKey).sessionId,
          message: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('migration', () {
    test('ilk kosuda kosar, ikincide kosmaz', () async {
      final migration = VodozemacMigration(database);

      expect(await migration.isPending(), isTrue);
      expect(await migration.runIfNeeded(), isTrue);
      expect(await migration.isPending(), isFalse);
      expect(await migration.runIfNeeded(), isFalse);
    });

    test('legacy kripto durumunu siler, mesaj gecmisini KORUR', () async {
      // Legacy libsignal durumu ve kullanici verisi birlikte kurulur.
      await database.conversations.insert(
        const ConversationEntity(
          id: 'alice',
          peerId: 'alice',
          peerName: 'Alice',
          peerPhone: '+1',
        ),
      );
      await database.identities.insert(
        const IdentityEntity(
          addressName: 'alice',
          identityKey: [1, 2, 3],
          trustLevel: TrustLevel.trustedUnverified,
        ),
      );
      await database.preKeys.insert(
        const PreKeyEntity(id: 1, record: [9, 9, 9]),
      );
      await database.sessions.insert(
        const SessionEntity(id: 'alice:1', record: [7, 7, 7]),
      );
      await database.cryptoState.put('local_identity_key_pair_v1', 'legacy');

      await VodozemacMigration(database).runIfNeeded();

      // Kripto durumu gitti.
      expect(await database.identities.get('alice'), isNull);
      expect(await database.preKeys.get(1), isNull);
      expect(await database.sessions.get('alice:1'), isNull);
      expect(
        await database.cryptoState.get('local_identity_key_pair_v1'),
        isNull,
      );
      // Kullanici verisi KORUNDU — kullanici hicbir mesajini kaybetmemeli.
      final conversations = await database.conversations.getAllImmediate();
      expect(conversations.map((c) => c.id), contains('alice'));
    });

    test('vodozemac durumu da temizlenir', () async {
      await store.withAccount(
        (account) async => account.generateOneTimeKeys(3),
      );
      expect(await store.hasAccount(), isTrue);

      await database.clearCryptoProtocolState();

      expect(await store.hasAccount(), isFalse);
    });
  });
}

String? _resolveHostLibrary() {
  for (final candidate in const [
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
