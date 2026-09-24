import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/groups/private_group_control.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slow sending does not read the entire source into memory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'file_backpressure_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final signaling = _BlockingSignaling()..setConnected(true);
    addTearDown(signaling.dispose);
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
      filesDirectory: directory,
    );
    addTearDown(manager.dispose);
    var reads = 0;
    Stream<List<int>> source() async* {
      for (var index = 0; index < 20; index++) {
        reads++;
        yield Uint8List(manager.chunkSize);
      }
    }

    final sending = manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: source(),
      fileSize: 20 * manager.chunkSize,
      fileName: 'document.bin',
      mimeType: 'application/octet-stream',
    );
    try {
      await signaling.entered.future.timeout(const Duration(seconds: 5));
      expect(reads, lessThanOrEqualTo(2));
    } finally {
      signaling.release.complete();
      expect(await sending, isA<FileTransferSuccess>());
    }
  });

  for (final group in [false, true]) {
    test(
      'streams 100 MiB within frame budget, group=$group',
      () async {
        final directory = await Directory.systemTemp.createTemp('file_limits_');
        addTearDown(() => directory.delete(recursive: true));
        final signaling = _CountingSignaling()..setConnected(true);
        addTearDown(signaling.dispose);
        final manager = FileTransferManager(
          signaling: signaling,
          crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
          filesDirectory: directory,
        );
        addTearDown(manager.dispose);
        const size = 100 * 1024 * 1024;
        final block = Uint8List(128 * 1024);
        final result = await manager.sendStream(
          localUserId: 'me',
          recipientId: group ? 'group' : 'peer',
          stream: Stream.fromIterable(Iterable.generate(800, (_) => block)),
          fileSize: size,
          fileName: 'document.bin',
          mimeType: 'application/octet-stream',
          isGroup: group,
          groupMembers: group ? ['me', 'peer'] : const [],
        );
        expect(result, isA<FileTransferSuccess>());
        expect(manager.maximumFileSize, size);
        final chunkSize = group
            ? FileTransferManager.maximumGroupChunkSize
            : manager.chunkSize;
        expect(signaling.frames, (size + chunkSize - 1) ~/ chunkSize);
        expect(signaling.manifests, 1);
        expect(
          signaling.maxFrameBytes,
          lessThanOrEqualTo(SignalMessage.maxEncodedBytes),
        );
        expect(signaling.sentMessages, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test('rejects over 100 MiB before reading any source bytes', () async {
    final directory = await Directory.systemTemp.createTemp('file_limits_');
    addTearDown(() => directory.delete(recursive: true));
    final signaling = _CountingSignaling()..setConnected(true);
    addTearDown(signaling.dispose);
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
      filesDirectory: directory,
    );
    addTearDown(manager.dispose);
    var sourceRead = false;
    Stream<List<int>> source() async* {
      sourceRead = true;
      yield [1];
    }

    final result = await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: source(),
      fileSize: manager.maximumFileSize + 1,
      fileName: 'too-large.bin',
      mimeType: 'application/octet-stream',
    );
    expect(result, isA<FileTransferFailure>());
    expect(sourceRead, isFalse);
    expect(signaling.frames, 0);
  });

  test(
    'group control reconnects after returning from an external picker',
    () async {
      final signaling = _ReconnectingSignaling();
      addTearDown(signaling.dispose);
      final controls = PrivateGroupControlSender(
        crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 7))),
        signaling: signaling,
      );
      await controls.send(
        senderId: 'me',
        groupId: 'group',
        groupName: 'Group',
        memberIds: ['me', 'peer'],
        recipients: ['peer'],
        action: 'CREATE',
      );
      expect(signaling.reconnects, 1);
      expect(signaling.sentMessages.single, isA<EncryptedSignalMessage>());
    },
  );
}

class _CountingSignaling extends InMemorySignalingService {
  int frames = 0;
  int manifests = 0;
  int maxFrameBytes = 0;

  @override
  Future<bool> send(SignalMessage message) async {
    if (message is FileTransferSignal) {
      expect(message.chunkIndex, frames);
      frames++;
      if (message.caption != null) manifests++;
      final bytes = utf8.encode(message.encode()).length;
      if (bytes > maxFrameBytes) maxFrameBytes = bytes;
      expect(SignalMessage.decode(message.encode()), isA<FileTransferSignal>());
    }
    return true;
  }
}

class _ReconnectingSignaling extends InMemorySignalingService {
  int reconnects = 0;

  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    reconnects++;
    setConnected(true);
    return true;
  }
}

class _BlockingSignaling extends _CountingSignaling {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> send(SignalMessage message) async {
    if (message is FileTransferSignal && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.send(message);
  }
}
