import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/network/socket_diagnostics.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/storage_at_rest.dart';

void main() {
  test('bulk frames are paced without delaying interactive signals', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final events = <SignalMessage>[];
    final allReceived = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      addTearDown(socket.close);
      socket.listen((event) {
        events.add(SignalMessage.decode(event as String));
        if (events.length == 7 && !allReceived.isCompleted) {
          allReceived.complete();
        }
      });
    });
    final signaling = WebSocketSignalingService();
    addTearDown(signaling.dispose);
    await signaling.connect(
      userId: 'me',
      url: 'ws://${server.address.address}:${server.port}',
      accessToken: 'token',
    );
    FileTransferSignal chunk(int index, {String data = 'opaque'}) =>
        FileTransferSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: DateTime.now(),
          fileName: 'attachment.bin',
          mimeType: 'application/octet-stream',
          fileSize: 6,
          data: data,
          transferId: 'transfer',
          chunkIndex: index,
          totalChunks: 6,
        );
    final clock = Stopwatch()..start();
    final pending = List.generate(6, (index) => signaling.send(chunk(index)));
    expect(
      await signaling.send(
        TypingIndicatorSignal(
          senderId: 'me',
          recipientId: 'peer',
          timestamp: DateTime.now(),
          isTyping: true,
        ),
      ),
      isTrue,
    );
    expect(await Future.wait(pending), everyElement(isTrue));
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(240));
    await allReceived.future.timeout(const Duration(seconds: 5));
    expect(
      events.indexWhere((event) => event is TypingIndicatorSignal),
      lessThan(5),
    );
    expect(
      events.whereType<FileTransferSignal>().map((event) => event.chunkIndex),
      [0, 1, 2, 3, 4, 5],
    );
    expect(
      await signaling.send(chunk(0, data: 'x' * SignalMessage.maxEncodedBytes)),
      isFalse,
    );
    final stale = signaling.send(chunk(0));
    await signaling.disconnect();
    expect(await stale, isFalse);
    expect(events, hasLength(7));
  });

  test(
    'offline queue persists encrypted signals and flushes in order',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      final signaling = InMemorySignalingService();
      final queue = OfflineMessageQueue(
        database: fixture.database,
        signaling: signaling,
      )..start();
      addTearDown(queue.close);

      final signal = EncryptedSignalMessage(
        senderId: 'me',
        recipientId: 'alice',
        timestamp: DateTime.fromMillisecondsSinceEpoch(100),
        envelope: 'ciphertext-only',
      );
      expect(await queue.sendOrQueue(signal), isFalse);
      expect(await queue.getPendingCount(), 1);
      expect(
        await storageAtRest(fixture.file),
        isNot(contains('ciphertext-only')),
      );

      await signaling.connect(
        userId: 'me',
        url: 'ws://local',
        accessToken: 'token',
      );
      final result = await queue.flushQueue();
      expect(result.remaining, 0);
      expect(signaling.sentMessages.single.toJson(), signal.toJson());
    },
  );

  test('offline queue refuses non-encrypted transient signals', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final queue = OfflineMessageQueue(
      database: fixture.database,
      signaling: InMemorySignalingService(),
    );

    expect(
      () => queue.sendOrQueue(
        TypingIndicatorSignal(
          senderId: 'me',
          recipientId: 'alice',
          timestamp: DateTime.now(),
          isTyping: true,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('reliable outbox survives socket send until an E2EE receipt', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'ws://local',
      accessToken: 'token',
    );
    final queue = OfflineMessageQueue(
      database: fixture.database,
      signaling: signaling,
    );
    addTearDown(queue.close);
    final signal = EncryptedSignalMessage(
      senderId: 'me',
      recipientId: 'alice',
      timestamp: DateTime.fromMillisecondsSinceEpoch(100),
      envelope: 'ciphertext-only',
      deliveryId: List.filled(43, 'A').join(),
    );

    expect(await queue.sendReliably(signal, messageId: 'message-1'), isTrue);
    expect(await queue.getPendingCount(), 1);
    expect((await queue.flushQueue()).remaining, 1);

    await queue.acknowledgeReceipt('message-1', 'alice');
    expect(await queue.getPendingCount(), 0);
  });

  test(
    'expired reliable outbox is bounded and marks undelivered message failed',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.close);
      await fixture.database.messages.insert(
        const MessageEntity(
          id: 'expired-message',
          conversationId: 'alice',
          senderId: 'me',
          content: 'local plaintext',
          contentType: StorageMessageContentType.text,
          timestamp: 1,
          status: StorageMessageStatus.sent,
          isOutgoing: true,
        ),
      );
      await fixture.database.pendingSignals.put(
        PendingSignalEntity(
          id: List.filled(43, 'E').join(),
          encodedSignal: '{}',
          createdAt: DateTime.now()
              .subtract(const Duration(days: 31))
              .millisecondsSinceEpoch,
          messageId: 'expired-message',
          recipientId: 'alice',
          retainUntilReceipt: true,
        ),
      );
      final queue = OfflineMessageQueue(
        database: fixture.database,
        signaling: InMemorySignalingService(),
      );
      addTearDown(queue.close);

      final result = await queue.flushQueue();

      expect(result.remaining, 0);
      expect(
        (await fixture.database.messages.getById('expired-message'))?.status,
        StorageMessageStatus.failed,
      );
    },
  );

  test('stuck sending messages are marked failed after timeout', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.close);
    const nowMs = 100000;
    await fixture.database.messages.insert(
      const MessageEntity(
        id: 'old',
        conversationId: 'alice',
        senderId: 'me',
        content: 'old encrypted payload',
        contentType: StorageMessageContentType.text,
        timestamp: 1000,
        status: StorageMessageStatus.sending,
        isOutgoing: true,
      ),
    );
    await fixture.database.messages.insert(
      const MessageEntity(
        id: 'new',
        conversationId: 'alice',
        senderId: 'me',
        content: 'new encrypted payload',
        contentType: StorageMessageContentType.text,
        timestamp: 90000,
        status: StorageMessageStatus.sending,
        isOutgoing: true,
      ),
    );

    final recovered = await StuckMessageRecovery(fixture.database)
        .recoverStuckMessages(
          timeout: const Duration(seconds: 30),
          now: DateTime.fromMillisecondsSinceEpoch(nowMs),
        );
    expect(recovered, 1);
    expect(
      (await fixture.database.messages.getById('old'))?.status,
      StorageMessageStatus.failed,
    );
    expect(
      (await fixture.database.messages.getById('new'))?.status,
      StorageMessageStatus.sending,
    );
  });

  test('websocket signaling sends auth and exchanges typed messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requestSeen = Completer<HttpRequest>();
    final receivedByServer = Completer<String>();
    late WebSocket serverSocket;
    server.listen((request) async {
      if (!requestSeen.isCompleted) requestSeen.complete(request);
      serverSocket = await WebSocketTransformer.upgrade(request);
      serverSocket.listen((event) {
        if (event is String && !receivedByServer.isCompleted) {
          receivedByServer.complete(event);
        }
      });
      serverSocket.add(
        PresenceUpdateSignal(
          senderId: 'server',
          recipientId: 'me',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1),
          isOnline: true,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(1),
        ).encode(),
      );
    });

    final telemetry = WebSocketTelemetry();
    final signaling = WebSocketSignalingService(telemetry: telemetry);
    addTearDown(signaling.disconnect);
    final incoming = signaling.incoming.first;
    await signaling.connect(
      userId: 'me',
      url: 'ws://${server.address.address}:${server.port}',
      accessToken: 'access-1',
    );

    final request = await requestSeen.future;
    expect(request.uri.queryParameters['userId'], 'me');
    expect(
      request.headers.value(HttpHeaders.authorizationHeader),
      'Bearer access-1',
    );
    expect(
      request.headers.value(WebSocketSignalingService.callCapabilityHeader),
      'true',
    );
    expect(signaling.currentStatus.isConnected, isTrue);
    expect(telemetry.current.connects, 1);
    expect(await incoming, isA<PresenceUpdateSignal>());

    final outgoing = TypingIndicatorSignal(
      senderId: 'me',
      recipientId: 'alice',
      timestamp: DateTime.fromMillisecondsSinceEpoch(2),
      isTyping: true,
    );
    expect(await signaling.send(outgoing), isTrue);
    expect(
      SignalMessage.decode(await receivedByServer.future).toJson(),
      outgoing.toJson(),
    );
    await signaling.disconnect();
    expect(telemetry.current.disconnects, 1);
    expect(telemetry.current.lastWasNormalClose, isTrue);
    await serverSocket.close();
  });

  test(
    'headless message socket declares no call handler across reconnects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final headers = <String?>[];
      server.listen((request) async {
        headers.add(
          request.headers.value(WebSocketSignalingService.callCapabilityHeader),
        );
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((_) {});
      });
      final signaling = WebSocketSignalingService(callCapable: false);
      addTearDown(() async {
        await signaling.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      for (var i = 0; i < 2; i++) {
        await signaling.connect(
          userId: 'me',
          url: 'ws://${server.address.address}:${server.port}',
          accessToken: 'background-token',
        );
        expect(signaling.currentStatus.isConnected, isTrue);
        await signaling.disconnect();
      }
      expect(headers, ['false', 'false']);
    },
  );

  test(
    'signaling disposal cancels a pending reconnect without delay',
    () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final telemetry = WebSocketTelemetry();
      final telemetryDone = Completer<void>();
      telemetry.states.listen((_) {}, onDone: telemetryDone.complete);
      final signaling = WebSocketSignalingService(telemetry: telemetry);

      await signaling.connect(
        userId: 'me',
        url: 'ws://127.0.0.1:$port',
        accessToken: 'access',
      );
      expect(signaling.currentStatus.isConnected, isFalse);

      final stopwatch = Stopwatch()..start();
      await signaling.dispose().timeout(const Duration(seconds: 1));
      await signaling.dispose();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      await telemetryDone.future;
      expect(
        () => signaling.connect(
          userId: 'me',
          url: 'ws://127.0.0.1:$port',
          accessToken: 'access',
        ),
        throwsStateError,
      );
    },
  );
}

Future<_NetworkFixture> _openFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'securechat_network_test_',
  );
  final file = File('${directory.path}/storage.securejson');
  final database = await SecureChatDatabase.open(
    file: file,
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 11)),
    ),
  );
  return _NetworkFixture(directory, file, database);
}

class _NetworkFixture {
  const _NetworkFixture(this.directory, this.file, this.database);

  final Directory directory;
  final File file;
  final SecureChatDatabase database;

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
