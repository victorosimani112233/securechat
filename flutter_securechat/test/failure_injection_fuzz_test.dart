import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deterministic AEAD corpus round trips and rejects every mutation',
    () async {
      final random = Random(0x5EC0A11);
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index * 7 % 256)),
      );

      for (var iteration = 0; iteration < 32; iteration++) {
        final peer = 'peer-${iteration % 5}';
        final plaintext = _randomText(random, 1 + random.nextInt(2048));
        final envelope = await crypto.encryptDirect(
          recipientId: peer,
          plaintext: plaintext,
        );
        expect(
          await crypto.decryptDirect(senderId: peer, envelope: envelope),
          plaintext,
          reason: 'seeded corpus iteration $iteration',
        );
        await expectLater(
          crypto.decryptDirect(senderId: '$peer-wrong', envelope: envelope),
          throwsA(anything),
        );

        for (final component in const [3, 4, 5]) {
          await expectLater(
            crypto.decryptDirect(
              senderId: peer,
              envelope: _flipEnvelopeByte(envelope, component, iteration),
            ),
            throwsA(anything),
            reason: 'component $component iteration $iteration',
          );
        }
      }
    },
  );

  test('wire codec bounds input and preserves randomized valid frames', () {
    final random = Random(0xC0DEC);
    for (var iteration = 0; iteration < 128; iteration++) {
      final message = EncryptedSignalMessage(
        senderId: _randomText(random, 1 + random.nextInt(24)),
        recipientId: _randomText(random, 1 + random.nextInt(24)),
        timestamp: DateTime.fromMillisecondsSinceEpoch(random.nextInt(1 << 30)),
        envelope: base64Encode(
          List<int>.generate(
            1 + random.nextInt(256),
            (_) => random.nextInt(256),
          ),
        ),
      );
      final decoded = SignalMessage.decode(message.encode());
      expect(decoded, isA<EncryptedSignalMessage>());
      expect(decoded.toJson(), message.toJson());
    }

    final futureFrame = <String, Object?>{
      'type': 'future_private_frame',
      'senderId': 'sender',
      'recipientId': 'recipient',
      'timestamp': 42,
      'opaque': {'nested': true},
    };
    expect(SignalMessage.decode(jsonEncode(futureFrame)).toJson(), futureFrame);

    for (final malformed in const ['null', '[]', '1', 'true', '"text"']) {
      expect(() => SignalMessage.decode(malformed), throwsFormatException);
    }
    final oversized = jsonEncode({
      'type': 'future_private_frame',
      'padding': List.filled(SignalMessage.maxEncodedBytes, 'x').join(),
    });
    expect(() => SignalMessage.decode(oversized), throwsFormatException);
  });

  test(
    'encrypted database rejects corruption without replacing user data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'securechat_storage_fuzz_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final key = List<int>.generate(32, (index) => 255 - index);
      final stableCrypto = LocalAeadCryptoService(SecretKey(key));
      final file = File('${directory.path}/storage.securejson');
      final database = await SecureChatDatabase.open(
        file: file,
        crypto: stableCrypto,
      );
      await database.conversations.insert(
        const ConversationEntity(
          id: 'kept',
          peerId: 'peer',
          peerName: 'Original',
          peerPhone: '',
        ),
      );
      for (var index = 0; index < 48; index++) {
        await database.messages.insert(
          MessageEntity(
            id: 'm-$index',
            conversationId: 'kept',
            senderId: index.isEven ? 'me' : 'peer',
            content: 'private-$index-${_randomText(Random(index), 32)}',
            contentType: StorageMessageContentType.text,
            timestamp: index,
            status: StorageMessageStatus.sent,
            isOutgoing: index.isEven,
          ),
        );
      }
      await database.close();
      final authenticated = await file.readAsString();
      expect(authenticated, isNot(contains('private-')));

      final reopened = await SecureChatDatabase.open(
        file: file,
        crypto: stableCrypto,
      );
      expect(await reopened.messages.getMessageCount('kept'), 48);
      await reopened.close();

      for (var mutation = 0; mutation < 16; mutation++) {
        final corrupt = File('${directory.path}/corrupt-$mutation.securejson');
        await corrupt.writeAsString(
          _flipEnvelopeByte(authenticated, 3 + mutation % 3, mutation),
          flush: true,
        );
        await expectLater(
          SecureChatDatabase.open(file: corrupt, crypto: stableCrypto),
          throwsA(anything),
        );
      }
      expect(await file.readAsString(), authenticated);
    },
  );

  test(
    'failed atomic persistence rolls memory and disk back together',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'securechat_storage_failure_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final key = List<int>.generate(32, (index) => index + 41);
      final crypto = _FailureInjectingCrypto(SecretKey(key));
      final file = File('${directory.path}/storage.securejson');
      final database = await SecureChatDatabase.open(
        file: file,
        crypto: crypto,
      );
      await database.conversations.insert(
        const ConversationEntity(
          id: 'kept',
          peerId: 'peer',
          peerName: 'Before',
          peerPhone: '',
        ),
      );
      final before = await file.readAsString();
      crypto.failNextStorageEncryption = true;

      await expectLater(
        database.conversations.updatePeerName('kept', 'Must not commit'),
        throwsStateError,
      );
      expect(
        (await database.conversations.getById('kept'))?.peerName,
        'Before',
      );
      expect(await file.readAsString(), before);
      await database.close();

      final reopened = await SecureChatDatabase.open(
        file: file,
        crypto: LocalAeadCryptoService(SecretKey(key)),
      );
      expect(
        (await reopened.conversations.getById('kept'))?.peerName,
        'Before',
      );
      await reopened.close();
    },
  );

  test(
    'transport exceptions retain encrypted queue entries until ACK',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'securechat_network_failure_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await SecureChatDatabase.open(
        file: File('${directory.path}/storage.securejson'),
        crypto: LocalAeadCryptoService(SecretKey(List<int>.filled(32, 9))),
      );
      addTearDown(database.close);
      final signaling = _FaultInjectingSignaling([
        StateError('write failed'),
        StateError('flush failed'),
        false,
        true,
      ]);
      final failures = <String>[];
      final queue = OfflineMessageQueue(
        database: database,
        signaling: signaling,
        onAsyncFailure: (operation, _, _) => failures.add(operation),
      );
      addTearDown(queue.close);
      final message = EncryptedSignalMessage(
        senderId: 'me',
        recipientId: 'peer',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        envelope: 'E2EE:v1:SIGNAL:1:opaque-ciphertext',
      );

      expect(await queue.sendOrQueue(message), isFalse);
      expect(await queue.getPendingCount(), 1);
      expect((await queue.flushQueue()).remaining, 1);
      expect((await database.pendingSignals.getAll()).single.attempts, 1);
      expect((await queue.flushQueue()).remaining, 1);
      expect((await database.pendingSignals.getAll()).single.attempts, 2);
      expect((await queue.flushQueue()).remaining, 0);
      expect(failures, ['offline-queue.send', 'offline-queue.flush-send']);
    },
  );
}

String _randomText(Random random, int length) {
  const alphabet = ['a', 'Z', '0', ':', '\n', '\u0000', 'ç', '🔒', 'ب'];
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

String _flipEnvelopeByte(String envelope, int component, int salt) {
  final parts = envelope.split(':');
  final bytes = base64Decode(parts[component]);
  final offset = salt % bytes.length;
  bytes[offset] ^= 1 << (salt % 8);
  parts[component] = base64Encode(bytes);
  return parts.join(':');
}

class _FailureInjectingCrypto extends LocalAeadCryptoService {
  _FailureInjectingCrypto(super.masterKey);

  bool failNextStorageEncryption = false;

  @override
  Future<String> encryptStorageJson(String plaintext) {
    if (failNextStorageEncryption) {
      failNextStorageEncryption = false;
      throw StateError('injected storage encryption failure');
    }
    return super.encryptStorageJson(plaintext);
  }
}

class _FaultInjectingSignaling extends InMemorySignalingService {
  _FaultInjectingSignaling(Iterable<Object> outcomes)
    : _outcomes = Queue<Object>.of(outcomes);

  final Queue<Object> _outcomes;

  @override
  Future<bool> send(SignalMessage message) async {
    final outcome = _outcomes.removeFirst();
    if (outcome is Error) throw outcome;
    if (outcome is Exception) throw outcome;
    return outcome as bool;
  }
}
