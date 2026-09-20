import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';

/// Regresyon: karsi taraf uygulamayi silip yeniden kurdugunda sohbet
/// kendini toparlamali.
///
/// Onceki davranis: `ensureSession` kayit varsa hemen `true` donuyordu,
/// `deleteSession` hicbir yerden cagrilmiyordu ve `SessionResetRequestSignal`
/// hic uretilmiyordu. Sonuc: bir kisi telefon degistirince o sohbet KALICI
/// olarak oluyor, kullaniciya da hicbir uyari gitmiyordu. Cihaz turunde
/// dort kez 'No valid sessions [Bad Mac!]' olarak gozlendi ve prekey bundle
/// bir daha hic cekilmedi.
void main() {
  test('karsi taraf kimligini yenileyince eski TOFU pini korunur', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);

    // 1) Normal oturum kurulur ve iki yon de calisir.
    final hello = await fixture.alice.encryptDirect(
      recipientId: 'bob',
      plaintext: 'merhaba',
    );
    expect(hello, startsWith('E2EE:v1:PREKEY:'));
    expect(
      await fixture.bob.decryptDirect(senderId: 'alice', envelope: hello),
      'merhaba',
    );

    // 2) Bob uygulamayi silip yeniden kurar: yeni kimlik, yeni bundle.
    final bobReinstalled = await fixture.reinstallBob();

    // 3) Alice bayat oturumla gonderir; yeni Bob cozemez.
    final stale = await fixture.alice.encryptDirect(
      recipientId: 'bob',
      plaintext: 'bayat oturumdan',
    );
    await expectLater(
      bobReinstalled.decryptDirect(senderId: 'alice', envelope: stale),
      throwsA(isA<SignalSessionUnusableException>()),
      reason: 'bozuk oturum tipli hata ile bildirilmeli',
    );

    // 4) Reset yeni kimligi otomatik kabul etmemeli. Aksi halde prekey
    //    endpoint'ini kontrol eden sunucu tek bir reset ile MITM olabilir.
    await expectLater(
      fixture.alice.rebuildPeerSession('bob'),
      throwsA(isA<signal.UntrustedIdentityException>()),
    );
    expect(
      fixture.rotationsSeen,
      contains('bob'),
      reason: 'kimlik degisimi disari bildirilmeli',
    );
    await expectLater(
      fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'pin atlanamaz',
      ),
      throwsA(isA<signal.UntrustedIdentityException>()),
      reason: 'kullanici onayi olmadan yeni kimlik kullanilmamali',
    );
  });

  test(
    'ensureSession(force) bayat oturumu atip bundle yeniden ceker',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);

      await fixture.alice.encryptDirect(recipientId: 'bob', plaintext: 'ilk');
      expect(fixture.bundles.fetchCount['bob'], 1);

      // force olmadan: mevcut oturum kullanilir, bundle cekilmez.
      expect(await fixture.alice.ensureSession('bob'), isTrue);
      expect(fixture.bundles.fetchCount['bob'], 1);

      // force ile: oturum atilir ve bundle yeniden cekilir.
      expect(await fixture.alice.ensureSession('bob', force: true), isTrue);
      expect(
        fixture.bundles.fetchCount['bob'],
        2,
        reason: 'force taze bundle cekmeli',
      );
    },
  );

  test('tekrar teslim edilen mesaj oturumu sifirlamaz', () async {
    // DuplicateMessageException saglikli bir oturumda da olagandir; bunu
    // oturum bozuklugu saymak gereksiz X3DH turlari tetiklerdi.
    expect(
      SignalProtocolCryptoService.indicatesUnusableSession(
        signal.DuplicateMessageException('tekrar'),
      ),
      isFalse,
    );
    expect(
      SignalProtocolCryptoService.indicatesUnusableSession(
        signal.NoSessionException('oturum yok'),
      ),
      isTrue,
    );
  });
}

class _Fixture {
  _Fixture({
    required this.directory,
    required this.aliceDatabase,
    required this.bobDatabase,
    required this.alice,
    required this.bob,
    required this.bundles,
  });

  final Directory directory;
  final SecureChatDatabase aliceDatabase;
  final SecureChatDatabase bobDatabase;
  final SignalProtocolCryptoService alice;
  final SignalProtocolCryptoService bob;
  final _CountingBundleProvider bundles;
  final List<SecureChatDatabase> _extra = [];
  static final rotations = <String>[];
  List<String> get rotationsSeen => rotations;

  static Future<_Fixture> open() async {
    rotations.clear();
    final directory = await Directory.systemTemp.createTemp(
      'session_recovery_',
    );
    final aliceDatabase = await SecureChatDatabase.open(
      file: File('${directory.path}/alice.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 1))),
    );
    final bobDatabase = await SecureChatDatabase.open(
      file: File('${directory.path}/bob.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 2))),
    );
    final aliceRaw = DatabaseCryptoProtocolStore(aliceDatabase);
    final bobRaw = DatabaseCryptoProtocolStore(bobDatabase);
    final aliceBundle = await PreKeyManager(
      aliceRaw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    final bobBundle = await PreKeyManager(
      bobRaw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    final bundles = _CountingBundleProvider({
      'alice': aliceBundle,
      'bob': bobBundle,
    });
    return _Fixture(
      directory: directory,
      aliceDatabase: aliceDatabase,
      bobDatabase: bobDatabase,
      bundles: bundles,
      alice: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(aliceRaw),
        preKeyBundles: bundles,
        onPeerIdentityRotated: (peerId) async => rotations.add(peerId),
      ),
      bob: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(bobRaw),
        preKeyBundles: bundles,
      ),
    );
  }

  /// Bob'un uygulamayi silip yeniden kurmasini modeller: bos bir depo,
  /// yeni kimlik anahtari ve dizine yayinlanan yeni bundle.
  Future<SignalProtocolCryptoService> reinstallBob() async {
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/bob2.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 3))),
    );
    _extra.add(database);
    final raw = DatabaseCryptoProtocolStore(database);
    final bundle = await PreKeyManager(
      raw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    bundles.bundles['bob'] = bundle;
    return SignalProtocolCryptoService(
      store: PersistentSignalProtocolStore(raw),
      preKeyBundles: bundles,
    );
  }

  Future<void> close() async {
    for (final database in _extra) {
      await database.close();
    }
    await aliceDatabase.close();
    await bobDatabase.close();
    await directory.delete(recursive: true);
  }
}

/// Gercek sunucu gibi davranir: her cagrida serilestirilmis bundle'dan
/// TAZE bir nesne uretir. Ayni nesneyi tekrar kullanmak libsignal tarafinda
/// imza dogrulamasini bozuyor.
class _CountingBundleProvider implements PreKeyBundleProvider {
  _CountingBundleProvider(this.bundles);
  final Map<String, SerializedPreKeyBundle> bundles;
  final Map<String, int> fetchCount = {};

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async {
    fetchCount[recipientId] = (fetchCount[recipientId] ?? 0) + 1;
    final bundle = bundles[recipientId];
    return bundle == null ? null : _toSignalBundle(bundle);
  }
}

signal.PreKeyBundle _toSignalBundle(SerializedPreKeyBundle bundle) {
  final oneTime = bundle.oneTimePreKeys.first;
  return signal.PreKeyBundle(
    bundle.registrationId,
    1,
    oneTime.keyId,
    signal.Curve.decodePoint(Uint8List.fromList(oneTime.publicKey), 0),
    bundle.signedPreKeyId,
    signal.Curve.decodePoint(Uint8List.fromList(bundle.signedPreKey), 0),
    Uint8List.fromList(bundle.signedPreKeySignature),
    signal.IdentityKey.fromBytes(
      Uint8List.fromList(bundle.identityPublicKey),
      0,
    ),
  );
}
