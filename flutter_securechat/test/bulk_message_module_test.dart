import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/bulk/bulk_message_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bulk partial failure preserves successes and retries only failed recipients',
    () async {
      final root = await Directory.systemTemp.createTemp('bulk_partial_test_');
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (i) => i + 1)),
      );
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/db'),
        crypto: crypto,
      );
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final signaling = _ThrowingSignaling();
      addTearDown(signaling.dispose);
      await signaling.connect(userId: 'me', url: 'ws://test', accessToken: 'x');
      final service = BulkMessageService(
        database: database,
        sender: SendMessageUseCase(
          database: database,
          signaling: signaling,
          session: SessionStore(userId: 'me'),
          crypto: crypto,
          maxRetryCount: 0,
        ),
      );

      final result = await service.send('partial batch', [
        'alice',
        'bob',
        'carol',
      ]);
      expect(result.sent, 2);
      expect(result.failed, {'bob': SendMessageOutcome.deliveryFailed});
      expect(signaling.attemptedRecipients, ['alice', 'bob', 'carol']);

      signaling.failFor = null;
      final retry = await service.send('partial batch', result.failed.keys);
      expect(retry.sent, 1);
      expect(retry.failed, isEmpty);
      expect(signaling.attemptedRecipients, ['alice', 'bob', 'carol', 'bob']);
      expect(
        signaling.sentMessages.whereType<EncryptedSignalMessage>().map(
          (message) => message.recipientId,
        ),
        ['alice', 'carol', 'bob'],
      );
      expect(await database.messages.getMessageCount('alice'), 1);
      expect(await database.messages.getMessageCount('carol'), 1);
    },
  );

  test('bulk sender reports each encrypted recipient outcome', () async {
    final root = await Directory.systemTemp.createTemp('bulk_test_');
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (i) => i + 1)),
      ),
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final signaling = InMemorySignalingService();
    await signaling.connect(userId: 'me', url: 'ws://test', accessToken: 'x');
    final service = BulkMessageService(
      database: database,
      sender: SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: SessionStore(userId: 'me'),
        crypto: LocalAeadCryptoService(
          SecretKey(List<int>.generate(32, (i) => i + 1)),
        ),
        maxRetryCount: 0,
      ),
    );
    final result = await service.send(' ortak mesaj ', ['a', 'b', 'a']);
    expect(result.sent, 2);
    expect(result.failed, isEmpty);
    expect(await database.messages.getMessageCount('a'), 1);
    expect(await database.messages.getMessageCount('b'), 1);
  });
}

class _ThrowingSignaling extends InMemorySignalingService {
  String? failFor = 'bob';
  final attemptedRecipients = <String>[];

  @override
  Future<bool> send(SignalMessage message) async {
    if (message is EncryptedSignalMessage) {
      attemptedRecipients.add(message.recipientId);
      if (message.recipientId == failFor) {
        throw StateError('injected recipient send failure');
      }
    }
    return super.send(message);
  }
}
