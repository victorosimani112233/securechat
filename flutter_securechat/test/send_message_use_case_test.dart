import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct send encrypts once and marks persisted message sent', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final crypto = _RecordingCrypto();
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    final sender = _sender(fixture.database, crypto, signaling);

    final outcome = await sender(
      const SendMessageRequest(
        conversationId: 'alice',
        content: 'hello',
        replyToId: 'reply-1',
        isViewOnce: true,
      ),
    );

    expect(outcome, SendMessageOutcome.sent);
    expect(crypto.directCalls, 1);
    expect(crypto.lastPlaintext, startsWith('MSGID:'));
    expect(crypto.lastPlaintext, contains(':REPLY:reply-1:VIEWONCE:hello'));
    final signal = signaling.sentMessages.single as EncryptedSignalMessage;
    expect(signal.envelope, 'DIRECT-CIPHERTEXT');
    expect(signal.encode(), isNot(contains('hello')));
    final message = (await fixture.database.messages.getAllMessages()).single;
    expect(message.content, 'hello');
    expect(message.status, StorageMessageStatus.sent);
  });

  test('encryption failure never sends plaintext and marks failed', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    final sender = _sender(fixture.database, _ThrowingCrypto(), signaling);

    final outcome = await sender(
      const SendMessageRequest(conversationId: 'alice', content: 'top secret'),
    );

    expect(outcome, SendMessageOutcome.encryptionFailed);
    expect(signaling.sentMessages, isEmpty);
    final message = (await fixture.database.messages.getAllMessages()).single;
    expect(message.status, StorageMessageStatus.failed);
  });

  test(
    'group send fans one ciphertext out to members without group name',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      await fixture.database.conversations.insert(
        const ConversationEntity(
          id: 'group-1',
          peerId: 'group-1',
          peerName: 'Secret Group Name',
          peerPhone: '',
          isGroup: true,
          groupMembers: 'alice,bob',
        ),
      );
      final crypto = _RecordingCrypto();
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'ws://local',
        accessToken: 'token',
      );

      final outcome = await _sender(fixture.database, crypto, signaling)(
        const SendMessageRequest(
          conversationId: 'group-1',
          content: 'vote',
          contentType: StorageMessageContentType.poll,
          mentionedUserIds: ['alice', 'bob:bad'],
        ),
      );

      expect(outcome, SendMessageOutcome.sent);
      expect(
        signaling.sentMessages.whereType<EncryptedSignalMessage>(),
        hasLength(4),
      );
      expect(
        signaling.sentMessages.whereType<GroupMessageFanoutSignal>(),
        isEmpty,
      );
      for (final signal in signaling.sentMessages) {
        expect(signal.toJson(), isNot(containsPair('groupId', anything)));
        expect(signal.encode(), isNot(contains('Secret Group Name')));
      }
      expect(
        crypto.lastGroupPlaintext,
        contains('MENTION:alice,bobbad:POLL:vote'),
      );
    },
  );

  test('delivery exhaustion reuses ciphertext and marks failed', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final crypto = _RecordingCrypto();
    final signaling = InMemorySignalingService();
    final sender = SendMessageUseCase(
      database: fixture.database,
      signaling: signaling,
      session: SessionStore(userId: 'me', accessToken: 'token'),
      crypto: crypto,
      maxRetryCount: 2,
      retryDelay: Duration.zero,
    );

    final outcome = await sender(
      const SendMessageRequest(conversationId: 'alice', content: 'offline'),
    );

    expect(outcome, SendMessageOutcome.deliveryFailed);
    expect(crypto.directCalls, 1);
    expect(
      (await fixture.database.messages.getAllMessages()).single.status,
      StorageMessageStatus.failed,
    );
  });
}

SendMessageUseCase _sender(
  SecureChatDatabase database,
  CryptoService crypto,
  SignalingService signaling,
) => SendMessageUseCase(
  database: database,
  signaling: signaling,
  session: SessionStore(userId: 'me', accessToken: 'token'),
  crypto: crypto,
  maxRetryCount: 0,
  retryDelay: Duration.zero,
);

class _RecordingCrypto implements CryptoService {
  int directCalls = 0;
  String? lastPlaintext;
  String? lastGroupPlaintext;

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) async {
    directCalls++;
    lastPlaintext = plaintext;
    return 'DIRECT-CIPHERTEXT';
  }

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) async => envelope;

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) async {
    lastGroupPlaintext = plaintext;
    return 'GROUP-CIPHERTEXT';
  }

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) async => envelope;
}

class _ThrowingCrypto implements CryptoService {
  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) => throw StateError('no session');

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) => throw StateError('no session');

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) => throw StateError('no sender key');

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) => throw StateError('no sender key');
}

Future<_Fixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp('securechat_send_');
  final database = await SecureChatDatabase.open(
    file: File('${directory.path}/storage.securejson'),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
  );
  return _Fixture(directory, database);
}

class _Fixture {
  const _Fixture(this.directory, this.database);

  final Directory directory;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
