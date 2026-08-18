import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_securechat/src/crypto/call_crypto_manager.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/key_material_store.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform key material is created once and validated', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = PlatformKeyMaterialStore();
    final first = await store.readOrCreateMasterKey();
    final second = await store.readOrCreateMasterKey();

    expect(first, hasLength(32));
    expect(second, first);
  });

  test(
    'crypto protocol stores preserve TOFU, sessions and sender keys',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final store = fixture.store;

      expect(await store.storeIdentity('alice', [1, 2, 3]), isFalse);
      expect(await store.isTrustedIdentity('alice', [1, 2, 3]), isTrue);
      expect(await store.storeIdentity('alice', [1, 2, 3]), isFalse);
      expect(await store.storeIdentity('alice', [1, 2, 4]), isTrue);
      expect(await store.isTrustedIdentity('alice', [1, 2, 3]), isFalse);

      await store.storeSession('alice', 1, [9, 8]);
      await store.storeSession('alice', 2, [7, 6]);
      expect(await store.getSubDeviceSessions('alice'), [1, 2]);
      await store.deleteAllSessions('alice');
      expect(await store.containsSession('alice', 1), isFalse);

      await store.storeSenderKey('group', 'alice', 1, [5, 4]);
      expect(await store.loadSenderKey('group', 'alice', 1), [5, 4]);
      await store.deleteAllForGroup('group');
      expect(await store.containsSenderKey('group', 'alice', 1), isFalse);
    },
  );

  test(
    'pre-key manager creates, verifies, replenishes and rotates keys',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final manager = PreKeyManager(
        fixture.store,
        batchSize: 4,
        refreshThreshold: 2,
      );

      final initial = await manager.generateAndSerializeInitialBundle();
      expect(initial.oneTimePreKeys, hasLength(4));
      expect(await manager.verifySignedPreKey(initial), isTrue);
      expect(initial.registrationId, inInclusiveRange(1, 16380));

      final repeated = await manager.generateAndSerializeInitialBundle();
      expect(repeated.identityPublicKey, initial.identityPublicKey);
      expect(repeated.registrationId, initial.registrationId);

      await fixture.store.removePreKey(0);
      await fixture.store.removePreKey(1);
      await fixture.store.removePreKey(2);
      final replenished = await manager.buildSerializedReplenishBatch();
      expect(replenished, hasLength(4));
      expect(await manager.availablePreKeyCount(), 5);

      await manager.rotateSignedPreKey();
      final rotated = await manager.generateAndSerializeInitialBundle();
      expect(rotated.signedPreKeyId, 1);
      expect(await manager.verifySignedPreKey(rotated), isTrue);
    },
  );

  test('legacy preview key records migrate without deleting chats', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    await fixture.database.conversations.insert(
      const ConversationEntity(
        id: 'kept-chat',
        peerId: 'peer',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
    await fixture.store.storeIdentityKeyPair(
      '{"algorithm":"Ed25519","privateKey":"old"}'.codeUnits,
    );
    await fixture.store.storePreKey(42, [1, 2, 3]);
    await fixture.store.storeSession('peer', 1, [4, 5, 6]);

    final bundle = await PreKeyManager(
      fixture.store,
      batchSize: 2,
    ).generateAndSerializeInitialBundle();

    expect(bundle.oneTimePreKeys, hasLength(2));
    expect(
      await fixture.database.conversations.getById('kept-chat'),
      isNotNull,
    );
    expect(await fixture.store.containsPreKey(42), isFalse);
    expect(await fixture.store.containsSession('peer', 1), isFalse);
    expect(
      await PreKeyManager(fixture.store).verifySignedPreKey(bundle),
      isTrue,
    );
  });

  test('call crypto derives peer-bound keys and clears them', () async {
    final keys = await CallCryptoManager().deriveCallEncryptionKey('alice');
    expect(keys.masterKey, hasLength(32));
    expect(keys.masterSalt, hasLength(32));
    expect(keys.masterKey, isNot(everyElement(0)));

    keys.clear();
    expect(keys.masterKey, everyElement(0));
    expect(keys.masterSalt, everyElement(0));
  });
}

Future<_CryptoFixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'securechat_crypto_test_',
  );
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => 31 - index)),
  );
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/storage.securejson'),
    crypto: crypto,
  );
  return _CryptoFixture(
    directory,
    database,
    DatabaseCryptoProtocolStore(database),
  );
}

class _CryptoFixture {
  const _CryptoFixture(this.directory, this.database, this.store);

  final Directory directory;
  final SecureChatDatabase database;
  final DatabaseCryptoProtocolStore store;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
