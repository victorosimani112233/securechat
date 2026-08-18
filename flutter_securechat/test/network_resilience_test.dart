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

void main() {
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
        await fixture.file.readAsString(),
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
