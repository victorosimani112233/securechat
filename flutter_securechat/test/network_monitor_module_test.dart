import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/network/network_monitor.dart';
import 'package:flutter_securechat/src/services/app_lifecycle_coordinator.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'system monitor reports network kind and suppresses duplicate events',
    () async {
      final gateway = _FakeConnectivityGateway([NetworkTransport.wifi]);
      final monitor = SystemNetworkMonitor(gateway: gateway);
      addTearDown(monitor.stop);
      final emitted = <NetworkSnapshot>[];
      final subscription = monitor.changes.listen(emitted.add);
      addTearDown(subscription.cancel);

      final initial = await monitor.start();
      expect(initial.isAvailable, isTrue);
      expect(monitor.currentNetworkKind, NetworkKind.wifi);

      gateway.emit([NetworkTransport.wifi]);
      gateway.emit([NetworkTransport.cellular]);
      gateway.emit([NetworkTransport.none]);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(3));
      expect(emitted.first.kind, NetworkKind.wifi);
      expect(emitted[1].kind, NetworkKind.cellular);
      expect(emitted.last.isAvailable, isFalse);
    },
  );

  test(
    'network loss preserves socket identity and availability reconnects',
    () async {
      final gateway = _FakeConnectivityGateway([NetworkTransport.wifi]);
      final monitor = SystemNetworkMonitor(gateway: gateway);
      final signaling = InMemorySignalingService();
      final lifecycle = AppLifecycleCoordinator(
        session: SessionStore(userId: 'me', accessToken: 'access'),
        signaling: signaling,
        signalingUrl: 'wss://test.invalid',
        foregroundMaintenance: () async {},
        refreshPushRegistration: () async {},
        networkMonitor: monitor,
      );

      await lifecycle.enterForeground();
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(signaling.networkChanges, [true]);

      gateway.emit([NetworkTransport.none]);
      await _eventLoop();
      expect(signaling.currentStatus.isConnected, isFalse);
      expect(signaling.currentUserId, 'me');

      gateway.emit([NetworkTransport.cellular]);
      await _eventLoop();
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(signaling.networkChanges, [true, false, true]);

      await lifecycle.enterBackground();
      gateway.emit([NetworkTransport.wifi]);
      await _eventLoop();
      expect(signaling.networkChanges, [true, false, true]);
    },
  );

  test(
    'debug loopback transport stays available without Android network',
    () async {
      final gateway = _FakeConnectivityGateway([NetworkTransport.none]);
      final monitor = SystemNetworkMonitor(gateway: gateway);
      final signaling = InMemorySignalingService();
      final lifecycle = AppLifecycleCoordinator(
        session: SessionStore(userId: 'me', accessToken: 'access'),
        signaling: signaling,
        signalingUrl: 'wss://127.0.0.1:18443',
        foregroundMaintenance: () async {},
        refreshPushRegistration: () async {},
        networkMonitor: monitor,
        allowLoopbackWhenOffline: true,
      );

      await lifecycle.enterForeground();

      expect(signaling.networkChanges, [true]);
      expect(signaling.currentStatus.isConnected, isTrue);

      await lifecycle.dispose();
      await monitor.dispose();
      await signaling.dispose();
    },
  );

  test('lifecycle disposal stops monitoring and is idempotent', () async {
    final gateway = _FakeConnectivityGateway([NetworkTransport.wifi]);
    final monitor = SystemNetworkMonitor(gateway: gateway);
    final signaling = InMemorySignalingService();
    final lifecycle = AppLifecycleCoordinator(
      session: SessionStore(userId: 'me', accessToken: 'access'),
      signaling: signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async {},
      refreshPushRegistration: () async {},
      networkMonitor: monitor,
    );

    await lifecycle.enterForeground();
    final first = lifecycle.dispose();
    final second = lifecycle.dispose();
    expect(identical(first, second), isTrue);
    await first;

    expect(lifecycle.isForeground, isFalse);
    expect(signaling.currentStatus.isConnected, isFalse);
    gateway.emit([NetworkTransport.cellular]);
    await _eventLoop();
    expect(signaling.networkChanges, [true]);
    expect(lifecycle.enterForeground, throwsStateError);

    await monitor.dispose();
    await signaling.dispose();
  });

  test(
    'cellular auto-download denial deletes payload but keeps metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'network_media_policy_',
      );
      addTearDown(() => root.delete(recursive: true));
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      );
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/storage.securejson'),
        crypto: crypto,
      );
      addTearDown(database.close);
      final storage = StorageManagementService(database);
      await storage.savePolicy(
        const AutoDownloadPolicy(photosOnCellular: false),
      );
      final gateway = _FakeConnectivityGateway([NetworkTransport.cellular]);
      final monitor = SystemNetworkMonitor(gateway: gateway);
      await monitor.start();
      addTearDown(monitor.stop);
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'access',
      );
      final mediaDirectory = Directory('${root.path}/media');
      final transfers = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: mediaDirectory,
        chunkSize: 4,
      );
      addTearDown(transfers.dispose);
      final media = MediaMessageService(
        database: database,
        transfers: transfers,
        session: SessionStore(userId: 'me', accessToken: 'access'),
        localMediaDirectory: mediaDirectory,
        storageManagement: storage,
        networkKindProvider: monitor,
      )..start();
      addTearDown(media.close);
      final source = File('${root.path}/photo.jpg');
      await source.writeAsBytes(List<int>.generate(9, (index) => index));
      final attachment = await MediaAttachment.fromPath(source.path);

      await media.send(
        conversationId: 'peer',
        recipientId: 'peer',
        attachments: [attachment],
        isGroup: false,
        groupMembers: const [],
      );
      final wireMessageId =
          (await database.messages.getAllMessages()).single.id;
      await media.close();
      final recipientDatabase = await SecureChatDatabase.open(
        file: File('${root.path}/recipient.securejson'),
        crypto: crypto,
      );
      addTearDown(recipientDatabase.close);
      final recipientStorage = StorageManagementService(recipientDatabase);
      await recipientStorage.savePolicy(
        const AutoDownloadPolicy(photosOnCellular: false),
      );
      final recipientMedia = MediaMessageService(
        database: recipientDatabase,
        transfers: transfers,
        session: SessionStore(userId: 'recipient', accessToken: 'access'),
        localMediaDirectory: mediaDirectory,
        storageManagement: recipientStorage,
        networkKindProvider: monitor,
      )..start();
      addTearDown(recipientMedia.close);
      for (final chunk
          in signaling.sentMessages.whereType<FileTransferSignal>()) {
        await transfers.receiveChunk(
          FileTransferSignal.fromJson({
            ...chunk.toJson(),
            'senderId': 'peer',
            'recipientId': 'me',
          }),
        );
      }
      final incoming = await _waitForMessage(recipientDatabase, wireMessageId);

      expect(incoming.contentType, StorageMessageContentType.image);
      expect(incoming.content.split('|').last, isEmpty);
      expect(
        Directory(
          '${mediaDirectory.path}/received_files',
        ).listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    },
  );
}

class _FakeConnectivityGateway implements ConnectivityGateway {
  _FakeConnectivityGateway(this.current);

  List<NetworkTransport> current;
  final controller = StreamController<List<NetworkTransport>>.broadcast();

  @override
  Future<List<NetworkTransport>> checkConnectivity() async => current;

  @override
  Stream<List<NetworkTransport>> get connectivityChanges => controller.stream;

  void emit(List<NetworkTransport> next) {
    current = next;
    controller.add(next);
  }
}

Future<void> _eventLoop() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

Future<MessageEntity> _waitForMessage(
  SecureChatDatabase database,
  String id,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final message = await database.messages.getById(id);
    if (message != null) return message;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Message $id was not persisted');
}
