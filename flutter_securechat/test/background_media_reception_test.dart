import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/background/background_tasks.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background bootstrap wires media before notifications and connect', () {
    final source = File(
      'lib/src/background/background_tasks.dart',
    ).readAsStringSync();
    final receiver = source.indexOf(
      'final mediaReceiver = BackgroundMediaReceiver(',
    );
    final coordinator = source.indexOf(
      'final notifications = MessageNotificationCoordinator(',
    );
    expect(receiver, greaterThan(0));
    expect(coordinator, greaterThan(receiver));
    expect(
      source,
      contains('mediaMessages: mediaReceiver.messages.acceptedMessages'),
    );
    expect(source, contains('beforeReceive: incomingMessages.waitForIdle'));
    expect(source, contains('signaling.incoming,\n      transferActivity:'));
    expect(
      source.indexOf("'background-reception-drain'"),
      greaterThan(source.indexOf("'background-notifications'")),
    );
  });

  test(
    'active transfer holds idle window but never exceeds hard cap',
    () async {
      final signals = StreamController<Object?>.broadcast(sync: true);
      final activity = StreamController<bool>.broadcast(sync: true);
      final elapsed = Stopwatch()..start();
      await waitForBackgroundDrainIdle(
        signals.stream,
        transferActivity: activity.stream,
        hasActiveTransfers: () => true,
        idleFor: const Duration(milliseconds: 5),
        maxWait: const Duration(milliseconds: 100),
      ).timeout(const Duration(seconds: 5));
      expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(90));
      expect(signals.hasListener, isFalse);
      expect(activity.hasListener, isFalse);
      await signals.close();
      await activity.close();
    },
  );

  test('transfer completion starts a new quiet window', () async {
    final signals = StreamController<Object?>.broadcast(sync: true);
    final activity = StreamController<bool>.broadcast(sync: true);
    var active = true;
    var completed = false;
    final waiting = waitForBackgroundDrainIdle(
      signals.stream,
      transferActivity: activity.stream,
      hasActiveTransfers: () => active,
      idleFor: const Duration(milliseconds: 30),
      maxWait: const Duration(seconds: 5),
    ).then((_) => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(completed, isFalse);
    active = false;
    final elapsed = Stopwatch()..start();
    activity.add(false);
    expect(completed, isFalse);
    await waiting.timeout(const Duration(seconds: 5));
    expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(25));
    expect(completed, isTrue);
    await signals.close();
    await activity.close();
  });

  for (final group in [false, true]) {
    test(
      '${group ? 'group' : 'direct'} voice survives shutdown during decrypt',
      () async {
        final root = await Directory.systemTemp.createTemp('background-voice-');
        addTearDown(() => root.delete(recursive: true));
        final crypto = _GatedCrypto();
        final file = File('${root.path}/database');
        final database = await SecureChatDatabase.open(
          file: file,
          crypto: crypto,
        );
        addTearDown(database.close);
        final conversationId = group ? 'group-id' : 'sender';
        await database.conversations.insert(
          ConversationEntity(
            id: conversationId,
            peerId: conversationId,
            peerName: group ? 'Group' : 'Sender',
            peerPhone: '',
            isGroup: group,
            groupMembers: group ? 'sender,receiver' : null,
          ),
        );
        final signaling = InMemorySignalingService();
        addTearDown(signaling.dispose);
        await signaling.connect(
          userId: 'receiver',
          url: 'wss://test.invalid',
          accessToken: 'token',
        );
        final session = SessionStore(
          userId: 'receiver',
          accessToken: 'token',
          languagePreference: 'en',
        );
        final failures = <Object>[];
        final incoming = IncomingMessageHandler(
          signaling: signaling,
          crypto: crypto,
          database: database,
          session: session,
          onAsyncFailure: (_, error, _) => failures.add(error),
        )..start();
        addTearDown(incoming.close);
        final receiver = BackgroundMediaReceiver(
          database: database,
          signaling: signaling,
          crypto: crypto,
          metadataCrypto: crypto,
          session: session,
          mediaDirectory: Directory('${root.path}/media'),
          beforeReceive: incoming.waitForIdle,
          networkKindProvider: _Cellular(),
          onAsyncFailure: (_, error, _) => failures.add(error),
        );
        addTearDown(receiver.close);
        final presenter = _Presenter();
        final notifications = MessageNotificationCoordinator(
          incomingMessages: incoming.acceptedMessages,
          mediaMessages: receiver.messages.acceptedMessages,
          session: session,
          presenter: presenter,
          unreadCounts: database.conversations.unreadCounts,
          onAsyncFailure: (_, error, _) => failures.add(error),
        );
        await notifications.start();
        notifications.setAppForeground(false);
        addTearDown(notifications.close);
        final senderSocket = InMemorySignalingService();
        addTearDown(senderSocket.dispose);
        await senderSocket.connect(
          userId: 'sender',
          url: 'wss://test.invalid',
          accessToken: 'token',
        );
        final sender = FileTransferManager(
          signaling: senderSocket,
          crypto: crypto,
          filesDirectory: Directory('${root.path}/sender'),
        );
        addTearDown(sender.dispose);
        final bytes = List<int>.generate(150000, (index) => index % 251);
        expect(
          await sender.sendStream(
            localUserId: 'sender',
            recipientId: group ? conversationId : 'receiver',
            isGroup: group,
            groupMembers: group ? ['sender', 'receiver'] : [],
            stream: Stream.value(bytes),
            fileSize: bytes.length,
            fileName: 'voice.m4a',
            mimeType: 'audio/mp4',
            originalMessageId: 'voice-id',
            caption: const VoiceNoteMetadata(
              duration: Duration(seconds: 8),
              waveform: [0.2, 0.8],
            ).encode(),
          ),
          isA<FileTransferSuccess>(),
        );
        final chunks = senderSocket.sentMessages
            .whereType<FileTransferSignal>()
            .toList();
        expect(chunks.length, greaterThan(1));
        expect(
          chunks.first.encryption,
          group
              ? FileTransferManager.groupWireVersion
              : FileTransferManager.directWireVersion,
        );
        crypto.block = true;
        addTearDown(() {
          if (!crypto.release.isCompleted) crypto.release.complete();
        });
        for (final chunk in chunks) {
          signaling.addIncoming(chunk);
        }
        await crypto.entered.future.timeout(const Duration(seconds: 5));
        var closed = false;
        final closing = closeBackgroundReception(
          signaling: signaling,
          incomingMessages: incoming,
          mediaReceiver: receiver,
          notifications: notifications,
        ).then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(signaling.currentStatus.isConnected, isFalse);
        expect(closed, isFalse);
        expect(await database.messages.getById('voice-id'), isNull);
        crypto.release.complete();
        await closing.timeout(const Duration(seconds: 10));
        expect(failures, isEmpty);
        final stored = (await database.messages.getById('voice-id'))!;
        expect(stored.contentType, StorageMessageContentType.voiceNote);
        expect(stored.conversationId, conversationId);
        final local = LocalMessage.fromJson(stored.toJson());
        expect(await File(local.filePath!).readAsBytes(), bytes);
        expect(local.voiceNoteDuration, const Duration(seconds: 8));
        expect(
          (await database.conversations.getById(conversationId))!.unreadCount,
          1,
        );
        expect(presenter.shown, hasLength(1));
        expect(presenter.shown.single.payload, isNull);
        expect(presenter.shown.single.hideOnLockScreen, isTrue);
        expect(presenter.shown.single.silent, isFalse);
        expect(identical(receiver.close(), receiver.close()), isTrue);
        await notifications.close();
        await database.close();
        final reopened = await SecureChatDatabase.open(
          file: file,
          crypto: crypto,
        );
        addTearDown(reopened.close);
        expect(
          (await reopened.messages.getById('voice-id'))!.content,
          stored.content,
        );
        expect(await receiver.transfers.receiveChunk(chunks.first), isNull);
      },
    );
  }
}

class _GatedCrypto extends LocalAeadCryptoService {
  _GatedCrypto() : super(SecretKey(List.filled(32, 7)));
  bool block = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) => super.encryptDirect(recipientId: 'test-pair', plaintext: plaintext);

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) async {
    if (block) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return super.decryptDirect(senderId: 'test-pair', envelope: envelope);
  }
}

class _Cellular implements NetworkKindProvider {
  @override
  NetworkKind get currentNetworkKind => NetworkKind.cellular;
}

class _Presenter implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> reconcileDismissals() async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> show(LocalMessageNotification notification) async {
    shown.add(notification);
  }
}
