import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/securechat_crypto_ffi.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_crypto_service.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/vodozemac_protocol_store.dart';
import 'package:flutter_securechat/src/media/call_media_key.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grup aramasinin medya anahtari kabloda nasil gorunur.
///
/// `CallManager._prepareMediaEncryption` anahtari `CallMediaKey.encode()` ile
/// serilize eder ve her katilimciya `crypto.encryptDirect(...)` ile gider:
/// sunucu yalniz ordinary bir `encrypted_message` (Olm zarfi) gorur. Bu test
/// GERCEK iki-taraf Olm oturumuyla o zarfin ic yuzunu dogrular: 32 byte AES-GCM
/// medya anahtari ne ham, ne base64, ne de `CALLKEY:v1` on eki olarak kabloya
/// cikmaz; yalniz karsi taraf cozunce ayni anahtara ulasir. "Iki cihazla paket
/// dogrulamasi" kalemi icin anahtar-dagitim yolunun kablo-uzeri kanitidir.
void main() {
  final libraryPath = _resolveHostLibrary();
  if (libraryPath == null) {
    test('cagri medya anahtari wire (atlandi: native kutuphane yok)', () {
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
    alice.directory['bob'] = bob;
    bob.directory['alice'] = alice;
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });
  });

  group('cagri medya anahtari — kablo gizliligi', () {
    test('medya anahtari zarfta plaintext olarak gorunmez', () async {
      const callId = 'group:room-9:instance-3';
      final mediaKey = CallMediaKey.generate(callId: callId);

      // CallManager'in kabloya koydugu tam govde budur.
      final payload = mediaKey.encode();
      final envelope = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: payload,
      );

      // Zarf bir Olm ciphertext'tir, ham payload degil.
      expect(envelope, startsWith(VodozemacCryptoService.directPrefix));

      // Anahtar materyali hicbir temsiliyle zarfta bulunmamali.
      final rawKeyB64 = base64Encode(mediaKey.key);
      expect(
        envelope.contains(rawKeyB64),
        isFalse,
        reason: 'anahtarin base64u kabloda gorundu',
      );
      expect(
        envelope.contains(CallMediaKey.prefix),
        isFalse,
        reason: 'CALLKEY on eki kabloda gorundu',
      );
      expect(
        envelope.contains(callId),
        isFalse,
        reason: 'callId kabloda gorundu',
      );

      // Byte duzeyi: ciphertext'in ham baytlarinda anahtar bir dizi olarak yok.
      final cipherBytes = _decodeCipher(envelope);
      expect(
        _containsSubsequence(cipherBytes, mediaKey.key),
        isFalse,
        reason: 'ham anahtar baytlari ciphertext icinde bulundu',
      );
      expect(
        _containsSubsequence(cipherBytes, utf8.encode(CallMediaKey.prefix)),
        isFalse,
        reason: 'CALLKEY on eki ciphertext baytlarinda bulundu',
      );
    });

    test('yalniz hedef alici cozunce ayni anahtara ulasir', () async {
      const callId = 'group:room-1:x';
      final mediaKey = CallMediaKey.generate(callId: callId, epoch: 5);

      final envelope = await alice.service.encryptDirect(
        recipientId: 'bob',
        plaintext: mediaKey.encode(),
      );
      final decoded = await bob.service.decryptDirect(
        senderId: 'alice',
        envelope: envelope,
      );

      final received = CallMediaKey.tryParse(decoded, expectedCallId: callId);
      expect(received, isNotNull);
      expect(received, mediaKey);
      expect(received!.epoch, 5);
      expect(received.keyIndex, 5);
    });

    test(
      'rotasyon anahtari da kabloda gizli kalir ve yeni kusak tasir',
      () async {
        const callId = 'group:room-2:y';
        final first = CallMediaKey.generate(callId: callId);
        final rotated = first.rotate();

        // Ilk kusak once teslim edilip oturum onaylanmali ki rotasyon normal
        // Olm mesaji olarak tasinsin.
        final firstEnvelope = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: first.encode(),
        );
        await bob.service.decryptDirect(
          senderId: 'alice',
          envelope: firstEnvelope,
        );
        final ack = await bob.service.encryptDirect(
          recipientId: 'alice',
          plaintext: 'ack',
        );
        await alice.service.decryptDirect(senderId: 'bob', envelope: ack);

        final rotatedEnvelope = await alice.service.encryptDirect(
          recipientId: 'bob',
          plaintext: rotated.encode(),
        );

        // Donen anahtar da kabloda gorunmemeli.
        expect(rotatedEnvelope.contains(base64Encode(rotated.key)), isFalse);
        final cipherBytes = _decodeCipher(rotatedEnvelope);
        expect(_containsSubsequence(cipherBytes, rotated.key), isFalse);

        final received = CallMediaKey.tryParse(
          await bob.service.decryptDirect(
            senderId: 'alice',
            envelope: rotatedEnvelope,
          ),
          expectedCallId: callId,
        );
        expect(received, rotated);
        expect(received!.epoch, first.epoch + 1);
      },
    );
  });
}

/// Olm zarfinin (`OLM:v1:<type>:<base64>`) ciphertext baytlarini cozer.
Uint8List _decodeCipher(String envelope) {
  final body = envelope.split(':').last;
  return base64Decode(body);
}

bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

class _Party {
  _Party._({
    required this.id,
    required this.database,
    required this.store,
    required this.directory,
    required this.directoryRef,
  });

  static Future<_Party> create(String id, SecureChatCrypto crypto) async {
    final directory = await Directory.systemTemp.createTemp('callkey-$id');
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
      onPeerIdentityRotated: (peerId) async {},
    );
    return party;
  }

  final String id;
  final SecureChatDatabase database;
  final VodozemacProtocolStore store;
  final Map<String, _Party> directory;
  final Directory directoryRef;
  late final VodozemacCryptoService service;

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

  Future<void> dispose() async {
    await database.close();
    await directoryRef.delete(recursive: true);
  }
}

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
