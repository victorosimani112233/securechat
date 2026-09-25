import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send activity lasts until the source finishes', () async {
    final fixture = await _fixture();
    final states = <bool>[];
    final subscription = fixture.manager.activity.listen(states.add);
    addTearDown(subscription.cancel);
    final source = StreamController<List<int>>();
    final pending = fixture.manager.sendStream(
      localUserId: 'sender',
      recipientId: 'recipient',
      stream: source.stream,
      fileSize: 8,
      fileName: 'test.bin',
      mimeType: 'application/octet-stream',
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.manager.hasActiveTransfers, isTrue);
    source.add(List.filled(8, 7));
    await source.close();
    expect(await pending, isA<FileTransferSuccess>());
    expect(states, [true, false]);
  });

  test('partial receive retains activity between chunks', () async {
    final fixture = await _fixture();
    final chunks = await _chunks(fixture);
    final states = <bool>[];
    final subscription = fixture.manager.activity.listen(states.add);
    addTearDown(subscription.cancel);
    expect(await fixture.manager.receiveChunk(chunks.first), isNull);
    expect(fixture.manager.hasActiveTransfers, isTrue);
    expect(states, [true]);
    expect(await fixture.manager.receiveChunk(chunks.last), isNotNull);
    expect(fixture.manager.hasActiveTransfers, isFalse);
    expect(states, [true, false]);
  });

  test('finishing one transfer does not release another', () async {
    final fixture = await _fixture();
    final first = await _chunks(fixture);
    final second = await _chunks(fixture);
    await fixture.manager.receiveChunk(first.first);
    await fixture.manager.receiveChunk(second.first);
    await fixture.manager.receiveChunk(first.last);
    expect(fixture.manager.hasActiveTransfers, isTrue);
    await fixture.manager.receiveChunk(second.last);
    expect(fixture.manager.hasActiveTransfers, isFalse);
  });

  test('incomplete receive eventually releases activity', () async {
    final fixture = await _fixture(staleAge: const Duration(milliseconds: 200));
    final chunks = await _chunks(fixture);
    await fixture.manager.receiveChunk(chunks.first);
    expect(fixture.manager.hasActiveTransfers, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fixture.manager.hasActiveTransfers, isFalse);
  });

  test('failed receive and disposal release activity', () async {
    final fixture = await _fixture();
    final chunks = await _chunks(fixture);
    await fixture.manager.receiveChunk(chunks.first);
    final corrupt = FileTransferSignal.fromJson({
      ...chunks.last.toJson(),
      'data': 'invalid-ciphertext',
    });
    expect(await fixture.manager.receiveChunk(corrupt), isNull);
    expect(fixture.manager.hasActiveTransfers, isFalse);
    await fixture.manager.receiveChunk(chunks.first);
    expect(fixture.manager.hasActiveTransfers, isTrue);
    await fixture.manager.dispose();
    expect(fixture.manager.hasActiveTransfers, isFalse);
  });
}

typedef _Fixture = ({
  FileTransferManager manager,
  InMemorySignalingService signaling,
});

Future<_Fixture> _fixture({
  Duration staleAge = const Duration(minutes: 10),
}) async {
  final directory = await Directory.systemTemp.createTemp('transfer_activity_');
  final signaling = InMemorySignalingService();
  await signaling.connect(
    userId: 'sender',
    url: 'wss://test.invalid',
    accessToken: 'test-token',
  );
  final manager = FileTransferManager(
    signaling: signaling,
    crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 1))),
    filesDirectory: directory,
    chunkSize: 4,
    staleTransferAge: staleAge,
  );
  addTearDown(() async {
    await manager.dispose();
    await signaling.dispose();
    await directory.delete(recursive: true);
  });
  return (manager: manager, signaling: signaling);
}

Future<List<FileTransferSignal>> _chunks(_Fixture fixture) async {
  final start = fixture.signaling.sentMessages.length;
  final result = await fixture.manager.sendStream(
    localUserId: 'sender',
    recipientId: 'recipient',
    stream: Stream.value(List.filled(8, 7)),
    fileSize: 8,
    fileName: 'test.bin',
    mimeType: 'application/octet-stream',
  );
  expect(result, isA<FileTransferSuccess>());
  return fixture.signaling.sentMessages
      .skip(start)
      .whereType<FileTransferSignal>()
      .map(
        (chunk) => FileTransferSignal.fromJson({
          ...chunk.toJson(),
          'senderId': 'recipient',
          'recipientId': 'sender',
        }),
      )
      .toList();
}
