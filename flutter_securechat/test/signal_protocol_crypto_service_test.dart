import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/groups/private_group_control.dart';
import 'package:flutter_securechat/src/groups/private_group_route.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  test(
    'persistent Signal service ratchets direct messages both ways',
    () async {
      final fixture = await _SignalFixture.open();
      addTearDown(fixture.close);

      final first = await fixture.alice.encryptDirect(
        recipientId: 'bob',
        plaintext: 'hello from alice',
      );
      expect(first, startsWith('E2EE:v1:PREKEY:'));
      expect(
        await fixture.bob.decryptDirect(senderId: 'alice', envelope: first),
        'hello from alice',
      );
      final reply = await fixture.bob.encryptDirect(
        recipientId: 'alice',
        plaintext: 'hello from bob',
      );
      expect(reply, startsWith('E2EE:v1:SIGNAL:'));
      expect(
        await fixture.alice.decryptDirect(senderId: 'bob', envelope: reply),
        'hello from bob',
      );
    },
  );

  test('SenderKey distribution enables authenticated group messages', () async {
    final fixture = await _SignalFixture.open();
    addTearDown(fixture.close);
    final skdm = await fixture.alice.createSenderKeyDistribution(
      groupId: 'group-1',
      senderId: 'alice',
    );
    final transport = await fixture.alice.encryptDirect(
      recipientId: 'bob',
      plaintext: skdm,
    );
    final received = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: transport,
    );
    await fixture.bob.processSenderKeyDistribution(
      senderId: 'alice',
      plaintext: received,
    );
    final group = await fixture.alice.encryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      plaintext: 'sender-key payload',
    );
    expect(group, startsWith('GROUPSK:v2:'));
    expect(group, isNot(contains('group-1')));
    expect(
      await fixture.bob.decryptGroup(
        senderId: 'alice',
        groupId: 'group-1',
        envelope: group,
      ),
      'sender-key payload',
    );

    // Legacy Kotlin envelopes remain receive-only during the coordinated
    // rollout; new sends must never reveal either value.
    final second = await fixture.alice.encryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      plaintext: 'legacy receive path',
    );
    final secondParts = second.split(':');
    final legacy = 'GROUPSK:v1:group-1:Legacy Group:${secondParts.last}';
    expect(
      await fixture.bob.decryptGroup(
        senderId: 'alice',
        groupId: 'group-1',
        envelope: legacy,
      ),
      'legacy receive path',
    );
  });

  test('group send distributes SKDM before the shared ciphertext', () async {
    final fixture = await _SignalFixture.open();
    addTearDown(fixture.close);
    await fixture.aliceDatabase.conversations.insert(
      const ConversationEntity(
        id: 'group-1',
        peerId: 'group-1',
        peerName: 'Compat group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'alice,bob',
      ),
    );
    final signaling = InMemorySignalingService()..setConnected(true);
    final sender = SendMessageUseCase(
      database: fixture.aliceDatabase,
      signaling: signaling,
      session: SessionStore(userId: 'alice', accessToken: 'token'),
      crypto: fixture.alice,
      retryDelay: Duration.zero,
    );

    expect(
      await sender(
        const SendMessageRequest(
          conversationId: 'group-1',
          content: 'group integration',
        ),
      ),
      SendMessageOutcome.sent,
    );
    expect(signaling.sentMessages, hasLength(3));
    final controlSignal = signaling.sentMessages[0] as EncryptedSignalMessage;
    final controlPlaintext = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: controlSignal.envelope,
    );
    final control = await decodePrivateGroupControl(
      plaintext: controlPlaintext,
      authenticatedSenderId: 'alice',
      localRecipientId: 'bob',
    );
    expect(control.action, 'CREATE');
    expect(control.groupId, 'group-1');

    final skdmSignal = signaling.sentMessages[1] as EncryptedSignalMessage;
    final distribution = await fixture.bob.decryptDirect(
      senderId: 'alice',
      envelope: skdmSignal.envelope,
    );
    await fixture.bob.processSenderKeyDistribution(
      senderId: 'alice',
      plaintext: distribution,
    );
    final routedSignal = signaling.sentMessages[2] as EncryptedSignalMessage;
    expect(routedSignal.recipientId, 'bob');
    expect(routedSignal.envelope, isNot(contains('group-1')));
    final route = await decodePrivateGroupRoute(
      await fixture.bob.decryptDirect(
        senderId: 'alice',
        envelope: routedSignal.envelope,
      ),
    );
    final recipientEnvelope = route.groupEnvelope;
    expect(route.groupId, 'group-1');
    expect(recipientEnvelope, startsWith('GROUPSK:v2:'));
    expect(recipientEnvelope, isNot(contains('group-1')));
    expect(recipientEnvelope, isNot(contains('Compat group')));
    final plaintext = await fixture.bob.decryptGroup(
      senderId: 'alice',
      groupId: 'group-1',
      envelope: recipientEnvelope,
    );
    expect(plaintext, contains('group integration'));
  });

  test(
    'missing PreKey bundle fails closed without a local AEAD fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'securechat_signal_missing_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
      final database = await SecureChatDatabase.open(
        file: File('${directory.path}/db.securejson'),
        crypto: storage,
      );
      addTearDown(database.close);
      final raw = DatabaseCryptoProtocolStore(database);
      await PreKeyManager(raw).generateAndSerializeInitialBundle();
      final service = SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(raw),
        preKeyBundles: const _MapBundleProvider({}),
      );
      await expectLater(
        service.encryptDirect(recipientId: 'missing', plaintext: 'secret'),
        throwsStateError,
      );
    },
  );
}

class _SignalFixture {
  _SignalFixture({
    required this.directory,
    required this.aliceDatabase,
    required this.bobDatabase,
    required this.alice,
    required this.bob,
  });

  final Directory directory;
  final SecureChatDatabase aliceDatabase;
  final SecureChatDatabase bobDatabase;
  final SignalProtocolCryptoService alice;
  final SignalProtocolCryptoService bob;

  static Future<_SignalFixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'securechat_signal_service_',
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
    final bundles = _MapBundleProvider({
      'alice': _toSignalBundle(aliceBundle),
      'bob': _toSignalBundle(bobBundle),
    });
    return _SignalFixture(
      directory: directory,
      aliceDatabase: aliceDatabase,
      bobDatabase: bobDatabase,
      alice: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(aliceRaw),
        preKeyBundles: bundles,
      ),
      bob: SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(bobRaw),
        preKeyBundles: bundles,
      ),
    );
  }

  Future<void> close() async {
    await aliceDatabase.close();
    await bobDatabase.close();
    await directory.delete(recursive: true);
  }
}

class _MapBundleProvider implements PreKeyBundleProvider {
  const _MapBundleProvider(this.bundles);
  final Map<String, signal.PreKeyBundle> bundles;

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async =>
      bundles[recipientId];
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
