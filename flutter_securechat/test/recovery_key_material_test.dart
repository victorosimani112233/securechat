import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

void main() {
  late Directory directory;
  late SecureChatDatabase db;
  late DatabaseCryptoProtocolStore store;
  late PreKeyManager keys;
  final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 37)));

  Future<void> open() async {
    db = await SecureChatDatabase.open(
      file: File('${directory.path}/db'),
      crypto: crypto,
    );
    store = DatabaseCryptoProtocolStore(db);
    keys = PreKeyManager(store, batchSize: 3);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recovery_keys_');
    await open();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'staging never mutates active keys and persists across reopen',
    () async {
      await keys.generateAndSerializeInitialBundle();
      final old = await keys.localIdentityPublicKey();
      final staged = keys.createRecoveryKeyMaterial();
      final record = jsonEncode(staged.toJson());
      await keys.writePendingRecovery(record);
      expect(await keys.localIdentityPublicKey(), old);
      await db.close();
      await open();
      expect(await keys.readPendingRecovery(), record);
      final restored = RecoveryKeyMaterial.fromJson(
        jsonDecode(record) as Map<String, Object?>,
      );
      expect(restored.bundle.toJson(), staged.bundle.toJson());
      expect(await keys.localIdentityPublicKey(), old);
    },
  );

  test('install is atomic, retains peer pins and is idempotent', () async {
    await keys.generateAndSerializeInitialBundle();
    final old = await keys.localIdentityPublicKey();
    await store.storeIdentity('peer', [1, 2, 3]);
    await store.storeSession('peer', 1, [4]);
    await store.storeSenderKey('group', 'self', 1, [5]);
    final staged = keys.createRecoveryKeyMaterial();
    final record = jsonEncode(staged.toJson());
    await keys.writePendingRecovery(record);
    await expectLater(
      keys.installRecoveryKeyMaterial(staged, 'stale'),
      throwsStateError,
    );
    expect(await keys.localIdentityPublicKey(), old);
    expect(await store.loadSession('peer', 1), [4]);
    await keys.installRecoveryKeyMaterial(staged, record);
    expect(
      await keys.localIdentityPublicKey(),
      base64Encode(staged.bundle.identityPublicKey),
    );
    expect(await store.loadIdentity('peer'), [1, 2, 3]);
    expect(await store.loadSession('peer', 1), isNull);
    expect(await store.loadSenderKey('group', 'self', 1), isNull);
    expect(await keys.readPendingRecovery(), record);
    await store.removePreKey(staged.bundle.oneTimePreKeys.first.keyId);
    await keys.installRecoveryKeyMaterial(staged, record);
    expect(await store.getAvailablePreKeyCount(), 2);
    await db.close();
    await open();
    expect(
      await keys.localIdentityPublicKey(),
      base64Encode(staged.bundle.identityPublicKey),
    );
    expect(await store.loadIdentity('peer'), [1, 2, 3]);
  });

  test('recovery signatures verify only exact purpose-bound proof', () async {
    await expectLater(keys.signRecoveryProof('proof'), throwsStateError);
    await keys.generateAndSerializeInitialBundle();
    final public = signal.IdentityKey.fromBytes(
      base64Decode((await keys.localIdentityPublicKey())!),
      0,
    ).publicKey;
    const proof = 'securechat/recovery/enroll/v1\nchallenge\naccount';
    final signature = base64Decode(await keys.signRecoveryProof(proof));
    expect(
      signal.Curve.verifySignature(
        public,
        Uint8List.fromList(utf8.encode(proof)),
        signature,
      ),
      isTrue,
    );
    expect(
      signal.Curve.verifySignature(
        public,
        Uint8List.fromList(utf8.encode('$proof!')),
        signature,
      ),
      isFalse,
    );
  });

  test('logout crypto wipe removes pending recovery capability', () async {
    await keys.writePendingRecovery('{"capability":"secret"}');
    await keys.clearProtocolState();
    expect(await keys.readPendingRecovery(), isNull);
  });

  test(
    'peer approval compare-and-set preserves concurrent pin and sessions',
    () async {
      await keys.generateAndSerializeInitialBundle();
      final local = (await store.getIdentityKeyPair())!;
      await store.storeIdentity('peer', [1]);
      await store.storeSession('peer', 1, [4]);
      expect(
        await store.approvePeerIdentity(
          peerId: 'peer',
          expectedIdentity: [9],
          approvedIdentity: [2],
          expectedLocalIdentityRecord: local,
        ),
        isFalse,
      );
      expect(await store.loadIdentity('peer'), [1]);
      expect(await store.loadSession('peer', 1), [4]);
      expect(
        await store.approvePeerIdentity(
          peerId: 'peer',
          expectedIdentity: [1],
          approvedIdentity: [2],
          expectedLocalIdentityRecord: [9],
        ),
        isFalse,
      );
      expect(await store.loadSession('peer', 1), [4]);
      expect(
        await store.approvePeerIdentity(
          peerId: 'peer',
          expectedIdentity: [1],
          approvedIdentity: [2],
          expectedLocalIdentityRecord: local,
        ),
        isTrue,
      );
      expect(await store.loadSession('peer', 1), isNull);
      expect(
        (await db.identities.get('peer'))!.trustLevel,
        TrustLevel.trustedVerified,
      );
      await store.storeIdentity('peer', [2]);
      expect(
        (await db.identities.get('peer'))!.trustLevel,
        TrustLevel.trustedVerified,
      );
    },
  );

  test('malformed staged material is rejected before install', () async {
    final staged = keys.createRecoveryKeyMaterial().toJson();
    staged['registrationId'] = 0;
    expect(() => RecoveryKeyMaterial.fromJson(staged), throwsFormatException);
  });
}
