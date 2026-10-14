import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_crypto_service.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/peer_identity_review_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Iki gercek taraf arasinda uctan uca akisi dogrular: bundle cekme, oturum
/// kurma, direct ve grup mesajlasma, kimlik pinleme ve bozuk oturumdan
/// kurtulma.
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    test('vodozemac servisi (atlandi: native kutuphane derlenmemis)', () {
      markTestSkipped(
        'Derlemek icin: cd native/securechat_crypto && cargo build --release',
      );
    }, skip: true);
    return;
  }

  late _Party alice;
  late _Party bob;

  setUp(() async {
    final crypto = SecureChatCrypto.open(libraryPath: libraryPath);
    alice = await _Party.create('alice', crypto);
    bob = await _Party.create('bob', crypto);
    // Her taraf digerinin bundle'ini cekebilsin.
    alice.directory['bob'] = bob;
    bob.directory['alice'] = alice;
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });
  });

  group('direct mesajlar', () {
    test('oturum kurulur ve mesaj iki yonlu tasinir', () async {
      final envelope = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'merhaba bob',
      );

      expect(envelope, startsWith(VodozemacCryptoService.directPrefix));
      expect(
        await bob.service.decryptDirect(senderId: 'alice', envelope: envelope),
        'merhaba bob',
      );

      // Ters yon: Bob cevap verir.
      final reply = await bob.service.encryptDirect(
        recipientId: 'alice',
        plaintext: 'merhaba alice',
      );
      expect(
        await alice.service.decryptDirect(senderId: 'bob', envelope: reply),
        'merhaba alice',
      );
    });

    test('cevap gelene kadar PreKey tipi surer, sonra normale doner', () async {
      // Olm, karsi taraftan BIR MESAJ GELENE kadar PreKey tipi uretmeye
      // devam eder: oturumun kuruldugunu ancak bir cevap kanitlar. Bu
      // protokol davranisi, servisin tekrar teslim mantigini da etkiliyor.
      final first = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'bir',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: first);
      final second = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'iki',
      );
      expect(first, startsWith('OLM:v1:0:'));
      expect(second, startsWith('OLM:v1:0:'));

      // Bob cevap verir ve Alice onu cozer: oturum artik onaylandi.
      final reply = await bob.service.encryptDirect(
        recipientId: 'alice',
        plaintext: 'cevap',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: second);
      await alice.service.decryptDirect(senderId: 'bob', envelope: reply);

      final third = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'uc',
      );
      expect(third, startsWith('OLM:v1:1:'));
    });

    test('ayni plaintext farkli ciphertext uretir', () async {
      final first = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'ayni',
      );
      final second = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'ayni',
      );

      expect(first, isNot(second));
    });

    test('tekrar teslim edilen cerceve oturumu YOK ETMEZ', () async {
      final first = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'bir',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: first);
      final second = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'iki',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: second);

      // Ayni cerceve tekrar gelirse cozulemez, ama oturum ayakta kalmali:
      // aksi halde tekrar oynatilan tek bir cerceve oturumu yok etmenin
      // yolu olurdu.
      await expectLater(
        bob.service.decryptDirect(senderId: 'alice', envelope: second),
        throwsA(isA<SecureChatCryptoException>()),
      );
      expect(await bob.store.sessionIdsForPeer('alice'), isNotEmpty);

      // Oturum gercekten calisiyor: yeni mesaj hala cozuluyor.
      final third = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'uc',
      );
      expect(
        await bob.service.decryptDirect(senderId: 'alice', envelope: third),
        'uc',
      );
    });

    // QA 2026-10-13 T16: tek bir bozuk ya da eski cerceve (sunucu tasir)
    // saglam oturumu siliyordu; her yeniden baglantida tekrar teslim edilen
    // eski bir mesaj konusmayi yeniden kopariyordu.
    test('bozuk ciphertext cozulemez ama oturumu silmez', () async {
      final envelope = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'bir',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: envelope);
      final next = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'iki',
      );
      // Govdeyi boz: MAC dogrulanmaz.
      final tampered = '${next.substring(0, next.length - 8)}AAAAAAAA';

      await expectLater(
        bob.service.decryptDirect(senderId: 'alice', envelope: tampered),
        throwsA(isA<SignalSessionUnusableException>()),
      );
      expect(await bob.store.sessionIdsForPeer('alice'), isNotEmpty);
      expect(
        await bob.service.decryptDirect(senderId: 'alice', envelope: next),
        'iki',
      );
    });

    test(
      'silinmis eski oturumdan gec gelen mesaj yeni oturumu bozmaz',
      () async {
        final first = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: 'eski-1',
        );
        await bob.service.decryptDirect(senderId: 'alice', envelope: first);
        // Eski oturumla sifrelenmis ama gec teslim edilecek mesaj.
        final late = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: 'eski-2',
        );
        // Iki taraf eski oturumu birakir; Alice yeni oturum kurar.
        await bob.service.resetPeerSession('alice');
        expect(await alice.service.rebuildPeerSession('bob'), isTrue);
        final fresh = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: 'yeni-1',
        );
        expect(
          await bob.service.decryptDirect(senderId: 'alice', envelope: fresh),
          'yeni-1',
        );

        await expectLater(
          bob.service.decryptDirect(senderId: 'alice', envelope: late),
          throwsA(isA<SignalSessionUnusableException>()),
        );

        final after = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: 'yeni-2',
        );
        expect(
          await bob.service.decryptDirect(senderId: 'alice', envelope: after),
          'yeni-2',
        );
      },
    );

    // QA 2026-10-13 T14: oturumu kaybeden taraf, karsi tarafin bir sey
    // yapmasina gerek kalmadan baglantiyi yeni oturumla kendisi onarir.
    test('cozemeyen taraf yeni oturum acinca karsi taraf ona gecer', () async {
      final hello = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'merhaba',
      );
      await bob.service.decryptDirect(senderId: 'alice', envelope: hello);
      final reply = await bob.service.encryptDirect(
        recipientId: 'alice',
        plaintext: 'cevap',
      );
      await alice.service.decryptDirect(senderId: 'bob', envelope: reply);
      // Bob oturumu kaybeder (yeniden kurulum, bozuk durum...).
      await bob.store.deleteSessionsForPeer('alice');
      final lost = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'kayip',
      );
      await expectLater(
        bob.service.decryptDirect(senderId: 'alice', envelope: lost),
        throwsA(isA<SignalSessionUnusableException>()),
      );

      expect(await bob.service.openFreshSession('alice'), isTrue);
      final reset = await bob.service.encryptDirect(
        recipientId: 'alice',
        plaintext: 'sifirla',
      );
      expect(
        await alice.service.decryptDirect(senderId: 'bob', envelope: reset),
        'sifirla',
      );

      final after = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: 'onarildi',
      );
      expect(
        await bob.service.decryptDirect(senderId: 'alice', envelope: after),
        'onarildi',
      );
    });

    test('yeni oturum acmak var olan oturumlari silmez', () async {
      await alice.service.ensureSession('bob');
      final before = await alice.store.sessionIdsForPeer('bob');
      expect(await alice.service.openFreshSession('bob'), isTrue);
      final after = await alice.store.sessionIdsForPeer('bob');
      expect(after, hasLength(before.length + 1));
      expect(after.skip(1), containsAll(before));
    });

    test('desteklenmeyen zarf reddedilir', () {
      expect(
        () => bob.service.decryptDirect(
          senderId: 'alice',
          envelope: 'E2EE:v1:PREKEY:1:AAAA',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('bundle yoksa oturum kurulamaz ve mesaj gonderilmez', () async {
      expect(await alice.service.ensureSession('kimse'), isFalse);
      await expectLater(
        alice.service.encryptDirect(
          recipientId: 'kimse',
          plaintext: 'gitmemeli',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('kimlik pinleme', () {
    test('ilk oturumda kimlik pinlenir', () async {
      await alice.service.ensureSession('bob');

      final pinned = await alice.database.identities.get('bob');
      expect(pinned, isNotNull);
      // ed25519 || curve25519 = 64 bayt. Yalniz birini pinlemek digerini
      // degistirilebilir birakirdi.
      expect(pinned!.identityKey, hasLength(64));
      expect(pinned.trustLevel, TrustLevel.trustedUnverified);
    });

    test('kimlik degisirse oturum kurulmaz — fail closed', () async {
      await alice.service.ensureSession('bob');
      // Bob cihaz degistirir: yeni hesap, yeni kimlik.
      await bob.replaceIdentity();

      await expectLater(
        alice.service.rebuildPeerSession('bob'),
        throwsA(isA<PeerIdentityChangedException>()),
      );
      expect(alice.rotationNotices, ['bob']);
    });

    test('inceleme ve onay yeni kimligi kabul eder', () async {
      await alice.service.ensureSession('bob');
      await bob.replaceIdentity();

      final review = await alice.service.reviewPeerIdentity('bob');
      expect(review.previousIdentity, isNotNull);
      expect(review.currentIdentity, isNot(review.previousIdentity));

      await alice.service.approvePeerIdentity(review);

      final pinned = await alice.database.identities.get('bob');
      expect(pinned!.trustLevel, TrustLevel.trustedVerified);
      // Onay sonrasi yeni oturum kurulabilir.
      expect(await alice.service.ensureSession('bob'), isTrue);
    });

    test('ayni inceleme iki kez onaylanamaz', () async {
      await alice.service.ensureSession('bob');
      await bob.replaceIdentity();
      final review = await alice.service.reviewPeerIdentity('bob');
      await alice.service.approvePeerIdentity(review);

      await expectLater(
        alice.service.approvePeerIdentity(review),
        throwsA(isA<PeerIdentityReviewStaleException>()),
      );
    });
  });

  group('grup mesajlari', () {
    test('dagitim, sifreleme ve cozme', () async {
      final distribution = await alice.service.createSenderKeyDistribution(
        groupId: 'grup-1',
        senderId: 'alice',
      );
      await bob.service.processSenderKeyDistribution(
        senderId: 'alice',
        plaintext: distribution,
      );

      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        plaintext: 'gruba merhaba',
      );

      expect(envelope, startsWith(VodozemacCryptoService.groupPrefix));
      expect(
        await bob.service.decryptGroup(
          senderId: 'alice',
          groupId: 'grup-1',
          envelope: envelope,
        ),
        'gruba merhaba',
      );
    });

    test('zarf grup kimligini acik tasimaz', () async {
      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'gizli-grup-kimligi',
        plaintext: 'x',
      );

      expect(envelope, isNot(contains('gizli-grup-kimligi')));
      // Sunucu yalnizca opak yonlendirme jetonunu gorur.
      expect(
        groupRoutingTokenFromEnvelope(envelope),
        await groupRoutingToken('gizli-grup-kimligi'),
      );
    });

    test('dagitim almayan uye cozemez', () async {
      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        plaintext: 'gizli',
      );

      await expectLater(
        bob.service.decryptGroup(
          senderId: 'alice',
          groupId: 'grup-1',
          envelope: envelope,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('sira disi gelen grup mesajlari kaybolmaz', () async {
      // Eski kontrol "indeks <= gorulen en yuksek" ise reddediyordu: 2'den
      // sonra gelen MESRU 1 replay sayilip sessizce dusuyordu. Offline kuyruk
      // ve es zamanli gonderimde gercek bir mesaj kaybiydi.
      final distribution = await alice.service.createSenderKeyDistribution(
        groupId: 'grup-1',
        senderId: 'alice',
      );
      await bob.service.processSenderKeyDistribution(
        senderId: 'alice',
        plaintext: distribution,
      );
      final envelopes = [
        for (final text in ['sifir', 'bir', 'iki'])
          await alice.service.encryptGroup(
            senderId: 'alice',
            groupId: 'grup-1',
            plaintext: text,
          ),
      ];

      final received = <String>[];
      for (final index in [2, 0, 1]) {
        received.add(
          await bob.service.decryptGroup(
            senderId: 'alice',
            groupId: 'grup-1',
            envelope: envelopes[index],
          ),
        );
      }
      expect(received, ['iki', 'sifir', 'bir']);

      // Sira disi kabul replay korumasini gevsetmez: her biri yalniz bir kez.
      for (final envelope in envelopes) {
        await expectLater(
          bob.service.decryptGroup(
            senderId: 'alice',
            groupId: 'grup-1',
            envelope: envelope,
          ),
          throwsA(isA<StateError>()),
        );
      }
    });

    test('replay reddedilir', () async {
      final distribution = await alice.service.createSenderKeyDistribution(
        groupId: 'grup-1',
        senderId: 'alice',
      );
      await bob.service.processSenderKeyDistribution(
        senderId: 'alice',
        plaintext: distribution,
      );
      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        plaintext: 'bir kez',
      );
      await bob.service.decryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        envelope: envelope,
      );

      await expectLater(
        bob.service.decryptGroup(
          senderId: 'alice',
          groupId: 'grup-1',
          envelope: envelope,
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

    test('sifirlanan oturum sonrasi eski dagitim ise yaramaz', () async {
      final first = await alice.service.createSenderKeyDistribution(
        groupId: 'grup-1',
        senderId: 'alice',
      );
      await bob.service.processSenderKeyDistribution(
        senderId: 'alice',
        plaintext: first,
      );

      // Uye cikarilir: giden oturum atilir, yeni anahtar uretilir.
      await alice.service.resetLocalSenderKey('grup-1', 'alice');
      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        plaintext: 'yeni anahtarla',
      );

      // Eski dagitimi tutan taraf yeni mesaji cozemez.
      await expectLater(
        bob.service.decryptGroup(
          senderId: 'alice',
          groupId: 'grup-1',
          envelope: envelope,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('yonlendirme jetonu uyusmazsa reddedilir', () async {
      final envelope = await alice.service.encryptGroup(
        senderId: 'alice',
        groupId: 'grup-1',
        plaintext: 'x',
      );

      expect(
        () => bob.service.decryptGroup(
          senderId: 'alice',
          groupId: 'baska-grup',
          envelope: envelope,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// Kendi veritabani, deposu ve servisi olan bir taraf.
class _Party {
  _Party._({
    required this.id,
    required this.database,
    required this.store,
    required this.directory,
    required this.directoryRef,
  });

  static Future<_Party> create(String id, SecureChatCrypto crypto) async {
    final directory = await Directory.systemTemp.createTemp('vodozemac-$id');
    final masterKey = List<int>.generate(32, (index) => index + id.length);
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(masterKey)),
    );
    final store = VodozemacProtocolStore(
      database: database,
      crypto: crypto,
      pickleKey: await VodozemacProtocolStore.derivePickleKey(masterKey),
    );
    final party = _Party._(
      id: id,
      database: database,
      store: store,
      directory: {},
      directoryRef: directory,
    );
    party.service = VodozemacCryptoService(
      database: database,
      store: store,
      preKeyBundles: _DirectoryBundleProvider(party.directory),
      onPeerIdentityRotated: (peerId) async =>
          party.rotationNotices.add(peerId),
    );
    return party;
  }

  final String id;
  final SecureChatDatabase database;
  final VodozemacProtocolStore store;

  /// Bu tarafin bundle cekebilecegi diger taraflar.
  final Map<String, _Party> directory;
  final Directory directoryRef;
  final rotationNotices = <String>[];
  late final VodozemacCryptoService service;

  /// Bu tarafin yayinlayacagi bundle: kimlik + taze tek kullanimlik anahtar.
  Future<OlmPreKeyBundle> publishBundle() => store.withAccount((account) async {
    final keys = account.identityKeys();
    final oneTime = account.generateOneTimeKeys(1);
    account.markKeysAsPublished();
    return OlmPreKeyBundle(
      identityKey: keys['curve25519']!,
      signingKey: keys['ed25519']!,
      oneTimeKey: oneTime.values.single,
    );
  });

  /// Cihaz degisimini taklit eder: hesap silinir, yeni kimlik dogar.
  Future<void> replaceIdentity() async {
    await database.vodozemacAccount.delete();
    await store.withAccount((account) async => account.identityKeys());
  }

  Future<void> dispose() async {
    await database.close();
    await directoryRef.delete(recursive: true);
  }
}

/// Testte sunucu yerine gecen bundle saglayicisi.
class _DirectoryBundleProvider implements OlmPreKeyBundleProvider {
  _DirectoryBundleProvider(this._directory);

  final Map<String, _Party> _directory;

  @override
  Future<OlmPreKeyBundle?> fetch(String recipientId) async =>
      _directory[recipientId]?.publishBundle();
}

String? _resolveHostLibrary() {
  for (final candidate in const [
    'native/securechat_crypto/target/release/libsecurechat_crypto.so',
    'native/securechat_crypto/target/release/libsecurechat_crypto.dylib',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.so',
    'native/securechat_crypto/target/debug/libsecurechat_crypto.dylib',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
