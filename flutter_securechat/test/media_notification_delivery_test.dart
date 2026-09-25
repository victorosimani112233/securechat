import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/l10n/service_strings.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

const _voice = VoiceNoteMetadata(
  duration: Duration(seconds: 3),
  waveform: [0.1, 0.8, 0.3],
);
final _bytes = Uint8List.fromList(List.generate(6590, (i) => i % 251));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final group in [false, true]) {
    final scope = group ? 'group' : 'direct';
    for (final mode in ['normal', 'muted', 'privacy', 'view-once']) {
      test('$scope voice notification after persistence ($mode)', () async {
        final f = await _Fixture.open(group: group, mode: mode);
        addTearDown(f.close);
        await f.sendVoice('voice-1', viewOnce: mode == 'view-once');
        f.deliverQueuedFrames();
        await f.drain();

        expect(f.failures, isEmpty);
        final stored = (await f.database.messages.getById('voice-1'))!;
        expect(stored.contentType, StorageMessageContentType.voiceNote);
        expect(stored.isViewOnce, mode == 'view-once');
        expect(stored.isMediaPreviewDeferred, isFalse);
        final local = LocalMessage.fromJson(stored.toJson());
        expect(local.fileName, 'original-note.m4a');
        expect(local.voiceNoteDuration, _voice.duration);
        expect(local.voiceNoteWaveform, _voice.waveform);
        expect(await File(local.filePath!).readAsBytes(), _bytes);
        expect(f.presenter.shown, hasLength(1));
        final notification = f.presenter.shown.single;
        expect(notification.count, 1);
        expect(notification.silent, mode == 'muted');
        expect(notification.hideOnLockScreen, mode == 'privacy');
        if (mode == 'privacy') {
          expect(notification.payload, isNull);
          expect(
            notification.id,
            MessageNotificationCoordinator.privacyNotificationId,
          );
          expect(notification.title, isNot(contains('Alice')));
          expect(notification.body, isNot(contains('Voice message')));
          expect(notification.body, isNot(contains('Private group')));
          expect(
            notification.conversationId,
            PluginLocalNotificationPresenter.groupKey,
          );
        } else {
          expect(notification.title, group ? 'Alice (Private group)' : 'Alice');
          expect(notification.payload, f.conversationId);
          expect(
            notification.body,
            mode == 'view-once' ? 'View once' : 'Voice message',
          );
        }
        expect(notification.body, isNot(contains('original-note')));

        final reopened = await SecureChatDatabase.open(
          file: f.file,
          crypto: f.storageCrypto,
        );
        try {
          final persisted = await reopened.messages.getById('voice-1');
          expect(persisted, isNotNull);
          expect(
            await File(
              LocalMessage.fromJson(persisted!.toJson()).filePath!,
            ).readAsBytes(),
            _bytes,
          );
        } finally {
          await reopened.close();
        }
      });
    }

    test(
      '$scope duplicate original media ID does not notify or count twice',
      () async {
        final f = await _Fixture.open(group: group);
        addTearDown(f.close);
        await f.sendVoice('same-voice');
        f.deliverQueuedFrames();
        await f.drain();
        final original = (await f.database.messages.getById(
          'same-voice',
        ))!.content;

        // Fresh ciphertext/transfer ID avoids testing only Signal replay rejection.
        await f.sendVoice('same-voice');
        f.deliverQueuedFrames();
        await f.drain();
        expect(f.failures, isEmpty);
        expect(f.presenter.shown, hasLength(1));
        expect(
          (await f.database.conversations.getById(
            f.conversationId,
          ))!.unreadCount,
          1,
        );
        expect(
          (await f.database.messages.getById('same-voice'))!.content,
          original,
        );
        expect(
          await File(
            LocalMessage.fromJson(
              (await f.database.messages.getById('same-voice'))!.toJson(),
            ).filePath!,
          ).readAsBytes(),
          _bytes,
        );
      },
    );
  }

  test(
    'simultaneous completed transfers with one original ID notify once',
    () async {
      final receipts = StreamController<ReceivedFile>.broadcast(sync: true);
      addTearDown(receipts.close);
      final f = await _Fixture.open(
        group: false,
        receivedFiles: receipts.stream,
      );
      addTearDown(f.close);
      final events = <IncomingMessageEvent>[];
      final subscription = f.media.acceptedMessages.listen(events.add);
      addTearDown(subscription.cancel);
      final first = await File(
        '${f.directory.path}/first.m4a',
      ).writeAsBytes(_bytes);
      final second = await File(
        '${f.directory.path}/second.m4a',
      ).writeAsBytes(_bytes);
      for (final entry in [
        ('transfer-first', first),
        ('transfer-second', second),
      ]) {
        receipts.add(
          ReceivedFile(
            transferId: entry.$1,
            file: entry.$2,
            fileName: 'original-note.m4a',
            mimeType: 'audio/mp4',
            senderId: 'alice',
            fileSize: _bytes.length,
            caption: _voice.encode(),
            originalMessageId: 'concurrent-voice',
          ),
        );
      }
      await f.drain();
      expect(f.failures, isEmpty);
      expect(events, hasLength(1));
      expect(f.presenter.shown, hasLength(1));
      expect((await f.database.conversations.getById('alice'))!.unreadCount, 1);
      final rows = await f.database.messages.getMessagesImmediate('alice');
      expect(rows, hasLength(1));
      expect(rows.single.id, 'concurrent-voice');
      expect(
        await File(
          LocalMessage.fromJson(rows.single.toJson()).filePath!,
        ).readAsBytes(),
        _bytes,
      );
    },
  );

  test(
    'queued group voices wait for SenderKey control before media decryption',
    () async {
      final f = await _Fixture.open(group: true);
      addTearDown(f.close);
      final gate = Completer<void>();
      f.receiverCrypto.senderKeyGate = gate;
      await f.sendVoice('first');
      await f.sendVoice('second');
      f.deliverQueuedFrames();
      await f.receiverCrypto.senderKeyStarted.future.timeout(
        const Duration(seconds: 5),
      );
      var drained = false;
      final drain = f.drain().then((_) => drained = true);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(drained, isFalse);
        expect(f.presenter.shown, isEmpty);
        expect(await f.database.messages.getById('first'), isNull);
      } finally {
        gate.complete();
      }
      await drain.timeout(const Duration(seconds: 10));
      expect(f.failures, isEmpty);
      expect(f.presenter.shown, hasLength(2));
      for (final id in ['first', 'second']) {
        final row = (await f.database.messages.getById(id))!;
        expect(row.contentType, StorageMessageContentType.voiceNote);
        expect(
          await File(
            LocalMessage.fromJson(row.toJson()).filePath!,
          ).readAsBytes(),
          _bytes,
        );
      }
      expect(
        (await f.database.conversations.getById(f.conversationId))!.unreadCount,
        2,
      );
    },
  );
}

class _Fixture {
  _Fixture(
    this.directory,
    this.file,
    this.database,
    this.senderDatabase,
    this.storageCrypto,
    this.receiverCrypto,
    this.wire,
    this.socket,
    this.incoming,
    this.outgoing,
    this.transfer,
    this.media,
    this.notifications,
    this.presenter,
    this.failures,
    this.group,
  );

  final Directory directory;
  final File file;
  final SecureChatDatabase database;
  final SecureChatDatabase senderDatabase;
  final LocalAeadCryptoService storageCrypto;
  final _ReceiverCrypto receiverCrypto;
  final InMemorySignalingService wire;
  final InMemorySignalingService socket;
  final IncomingMessageHandler incoming;
  final FileTransferManager outgoing;
  final FileTransferManager transfer;
  final MediaMessageService media;
  final MessageNotificationCoordinator notifications;
  final _Presenter presenter;
  final List<Object> failures;
  final bool group;
  int _deliveredFrames = 0;
  String get conversationId => group ? 'private-group' : 'alice';

  static Future<_Fixture> open({
    required bool group,
    String mode = 'normal',
    Stream<ReceivedFile>? receivedFiles,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'media_notification_',
    );
    final storageCrypto = LocalAeadCryptoService(
      SecretKey(List.filled(32, 23)),
    );
    final file = File('${directory.path}/receiver.db');
    final database = await SecureChatDatabase.open(
      file: file,
      crypto: storageCrypto,
    );
    final senderDatabase = await SecureChatDatabase.open(
      file: File('${directory.path}/sender.db'),
      crypto: storageCrypto,
    );
    final senderStore = DatabaseCryptoProtocolStore(senderDatabase);
    final receiverStore = DatabaseCryptoProtocolStore(database);
    final bundles = _Bundles({
      'alice': _bundle(
        await PreKeyManager(
          senderStore,
          batchSize: 4,
        ).generateAndSerializeInitialBundle(),
      ),
      'bob': _bundle(
        await PreKeyManager(
          receiverStore,
          batchSize: 4,
        ).generateAndSerializeInitialBundle(),
      ),
    });
    final senderCrypto = SignalProtocolCryptoService(
      store: PersistentSignalProtocolStore(senderStore),
      preKeyBundles: bundles,
    );
    final receiverCrypto = _ReceiverCrypto(
      store: PersistentSignalProtocolStore(receiverStore),
      preKeyBundles: bundles,
    );
    final wire = InMemorySignalingService()..setConnected(true);
    final socket = InMemorySignalingService()..setConnected(true);
    final failures = <Object>[];
    void report(String operation, Object error, StackTrace stack) =>
        failures.add(error);
    final session = SessionStore(
      userId: 'bob',
      languagePreference: 'en',
      showNotificationContent: mode != 'privacy',
    );
    final conversationId = group ? 'private-group' : 'alice';
    await database.conversations.insert(
      ConversationEntity(
        id: conversationId,
        peerId: conversationId,
        peerName: group ? 'Private group' : 'Alice',
        peerPhone: '',
        isGroup: group,
        groupMembers: group ? 'alice,bob' : null,
        groupAdmins: group ? 'alice' : null,
        isMuted: mode == 'muted',
      ),
    );
    await database.contacts.insert(
      const ContactEntity(
        id: 'alice',
        phoneNumber: '+15550001',
        phoneHash: 'test-hash',
        displayName: 'Alice',
        isRegistered: true,
      ),
    );
    final incoming = IncomingMessageHandler(
      signaling: socket,
      crypto: receiverCrypto,
      database: database,
      session: session,
      onAsyncFailure: report,
    )..start();
    final outgoing = FileTransferManager(
      signaling: wire,
      crypto: senderCrypto,
      filesDirectory: Directory('${directory.path}/out'),
      metadataCrypto: storageCrypto,
      onAsyncFailure: report,
    );
    final transfer = FileTransferManager(
      signaling: socket,
      crypto: receiverCrypto,
      filesDirectory: Directory('${directory.path}/media'),
      metadataCrypto: storageCrypto,
      beforeReceive: incoming.waitForIdle,
      onAsyncFailure: report,
    );
    final media = MediaMessageService(
      database: database,
      transfers: receivedFiles == null
          ? transfer
          : _ReceiptSource(receivedFiles),
      session: session,
      localMediaDirectory: Directory('${directory.path}/media'),
      strings: ServiceStrings.fixed('en'),
      onAsyncFailure: report,
    )..start();
    final presenter = _Presenter(() async {
      final messages = await database.messages.getMessagesImmediate(
        conversationId,
      );
      expect(
        messages.where(
          (m) => m.contentType == StorageMessageContentType.voiceNote,
        ),
        isNotEmpty,
      );
      for (final row in messages) {
        expect(
          await File(LocalMessage.fromJson(row.toJson()).filePath!).exists(),
          isTrue,
        );
      }
      expect(
        (await database.conversations.getById(conversationId))!.unreadCount,
        greaterThan(0),
      );
    });
    final notifications = MessageNotificationCoordinator(
      incomingMessages: incoming.acceptedMessages,
      mediaMessages: media.acceptedMessages,
      session: session,
      presenter: presenter,
      strings: ServiceStrings.fixed('en'),
      unreadCounts: database.conversations.unreadCounts,
      onAsyncFailure: report,
    );
    await notifications.start();
    notifications.setAppForeground(false);
    return _Fixture(
      directory,
      file,
      database,
      senderDatabase,
      storageCrypto,
      receiverCrypto,
      wire,
      socket,
      incoming,
      outgoing,
      transfer,
      media,
      notifications,
      presenter,
      failures,
      group,
    );
  }

  Future<void> sendVoice(String id, {bool viewOnce = false}) async {
    final result = await outgoing.sendStream(
      localUserId: 'alice',
      recipientId: group ? conversationId : 'bob',
      stream: Stream.value(_bytes),
      fileSize: _bytes.length,
      fileName: 'original-note.m4a',
      mimeType: 'audio/mp4',
      isGroup: group,
      groupMembers: group ? ['alice', 'bob'] : [],
      caption: _voice.encode(),
      originalMessageId: id,
      isViewOnce: viewOnce,
    );
    expect(result, isA<FileTransferSuccess>());
  }

  void deliverQueuedFrames() {
    for (final frame in wire.sentMessages.skip(_deliveredFrames)) {
      socket.addIncoming(SignalMessage.decode(frame.encode()));
    }
    _deliveredFrames = wire.sentMessages.length;
  }

  Future<void> drain() async {
    await transfer.waitForIdle();
    await media.waitForIdle();
    await notifications.waitForIdle();
  }

  Future<void> close() async {
    final gate = receiverCrypto.senderKeyGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await drain();
    await transfer.dispose();
    await media.close();
    await notifications.close();
    await incoming.close();
    await outgoing.dispose();
    await socket.dispose();
    await wire.dispose();
    await database.close();
    await senderDatabase.close();
    await directory.delete(recursive: true);
  }
}

class _ReceiptSource implements FileTransferManager {
  _ReceiptSource(this.receivedFiles);
  @override
  final Stream<ReceivedFile> receivedFiles;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Presenter implements LocalNotificationPresenter {
  _Presenter(this.beforeShow);
  final Future<void> Function() beforeShow;
  final shown = <LocalMessageNotification>[];
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show(LocalMessageNotification notification) async {
    await beforeShow();
    shown.add(notification);
  }

  @override
  Future<void> reconcileDismissals() async {}
  @override
  Future<void> cancelAll() async {}
}

class _ReceiverCrypto extends SignalProtocolCryptoService {
  _ReceiverCrypto({required super.store, required super.preKeyBundles});
  Completer<void>? senderKeyGate;
  final senderKeyStarted = Completer<void>();
  @override
  Future<void> processSenderKeyDistribution({
    required String senderId,
    required String plaintext,
  }) async {
    if (!senderKeyStarted.isCompleted) senderKeyStarted.complete();
    await senderKeyGate?.future;
    await super.processSenderKeyDistribution(
      senderId: senderId,
      plaintext: plaintext,
    );
  }
}

class _Bundles implements PreKeyBundleProvider {
  _Bundles(this.values);
  final Map<String, signal.PreKeyBundle> values;
  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async =>
      values[recipientId];
}

signal.PreKeyBundle _bundle(SerializedPreKeyBundle value) {
  final key = value.oneTimePreKeys.first;
  return signal.PreKeyBundle(
    value.registrationId,
    1,
    key.keyId,
    signal.Curve.decodePoint(Uint8List.fromList(key.publicKey), 0),
    value.signedPreKeyId,
    signal.Curve.decodePoint(Uint8List.fromList(value.signedPreKey), 0),
    Uint8List.fromList(value.signedPreKeySignature),
    signal.IdentityKey.fromBytes(
      Uint8List.fromList(value.identityPublicKey),
      0,
    ),
  );
}
