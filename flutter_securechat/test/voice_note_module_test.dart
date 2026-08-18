import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice metadata is versioned, bounded and round trips', () {
    const metadata = VoiceNoteMetadata(
      duration: Duration(seconds: 12, milliseconds: 340),
      waveform: [0, 0.2, 0.75, 1],
    );
    final encoded = metadata.encode();
    final decoded = VoiceNoteMetadata.tryDecode(encoded);

    expect(encoded, startsWith('SCVN1:'));
    expect(decoded?.duration, metadata.duration);
    expect(decoded?.waveform, [0, 0.2, 0.75, 1]);
    expect(VoiceNoteMetadata.tryDecode('SCVN1:not-base64'), isNull);
    expect(VoiceNoteMetadata.tryDecode('plaintext'), isNull);
  });

  test(
    'recorder handles permission, amplitude, pause and file result',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'voice_recorder_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final backend = _FakeVoiceRecorderBackend();
      final recorder = VoiceNoteRecorder(
        backend: backend,
        recordingDirectory: directory,
      );
      addTearDown(recorder.dispose);

      await recorder.start();
      backend.amplitudeController.add(-30);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await recorder.pause();
      expect(recorder.isPaused, isTrue);
      await recorder.resume();
      final draft = await recorder.stop();

      expect(draft, isNotNull);
      expect(draft!.attachment.mimeType, 'audio/mp4');
      expect(draft.attachment.fileSize, greaterThan(0));
      expect(draft.metadata.waveform.single, closeTo(0.5, 0.01));
      expect(backend.pauses, 1);
      expect(backend.resumes, 1);
    },
  );

  test('recorder serializes cleanup and rejects reuse after dispose', () async {
    final directory = await Directory.systemTemp.createTemp(
      'voice_recorder_dispose_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final backend = _FakeVoiceRecorderBackend();
    final recorder = VoiceNoteRecorder(
      backend: backend,
      recordingDirectory: directory,
    );

    await recorder.start();
    final first = recorder.dispose();
    final second = recorder.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(backend.cancels, 1);
    expect(backend.disposals, 1);
    await expectLater(recorder.start(), throwsStateError);
  });

  test(
    'voice note uses encrypted transfer and persists as VOICE_NOTE',
    () async {
      final root = await Directory.systemTemp.createTemp('voice_message_');
      addTearDown(() => root.delete(recursive: true));
      final crypto = LocalAeadCryptoService(
        SecretKey(List<int>.generate(32, (index) => index + 1)),
      );
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/storage.securejson'),
        crypto: crypto,
      );
      addTearDown(database.close);
      await database.conversations.insert(
        const ConversationEntity(
          id: 'peer',
          peerId: 'peer',
          peerName: 'Peer',
          peerPhone: '',
        ),
      );
      final signaling = InMemorySignalingService();
      await signaling.connect(
        userId: 'me',
        url: 'wss://test.invalid',
        accessToken: 'token',
      );
      final transfers = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: Directory('${root.path}/media'),
        chunkSize: 4,
      );
      addTearDown(transfers.dispose);
      final media = MediaMessageService(
        database: database,
        transfers: transfers,
        session: SessionStore(userId: 'me', accessToken: 'token'),
        localMediaDirectory: Directory('${root.path}/media'),
      )..start();
      addTearDown(media.close);
      final source = File('${root.path}/voice.m4a');
      await source.writeAsBytes(List<int>.generate(15, (index) => index));
      final backend = _FakeVoiceRecorderBackend()..outputPath = source.path;
      final recorder = VoiceNoteRecorder(
        backend: backend,
        recordingDirectory: root,
      );
      addTearDown(recorder.dispose);
      await recorder.start();
      backend.amplitudeController.add(-15);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      backend.outputPath = source.path;
      final draft = await recorder.stop();

      final outcome = await media.sendVoiceNote(
        conversationId: 'peer',
        recipientId: 'peer',
        draft: draft!,
        isGroup: false,
        groupMembers: const [],
      );
      expect(outcome.result, isA<FileTransferSuccess>());
      final stored = (await database.messages.getAllMessages()).single;
      expect(stored.contentType, StorageMessageContentType.voiceNote);
      expect(stored.content.split('|'), hasLength(6));
      expect(stored.caption, isNull);
      expect(
        signaling.sentMessages.whereType<FileTransferSignal>().every(
          (signal) =>
              signal.caption == null || !signal.caption!.contains('SCVN1:'),
        ),
        isTrue,
      );
      final wireMessageId = stored.id;
      await media.close();
      final recipientDatabase = await SecureChatDatabase.open(
        file: File('${root.path}/recipient.securejson'),
        crypto: crypto,
      );
      addTearDown(recipientDatabase.close);
      final recipientMedia = MediaMessageService(
        database: recipientDatabase,
        transfers: transfers,
        session: SessionStore(userId: 'recipient', accessToken: 'token'),
        localMediaDirectory: Directory('${root.path}/recipient_media'),
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
      // FileTransferManager publishes completion synchronously; drain the
      // persistence owner instead of guessing scheduler timing.
      await recipientMedia.waitForIdle();
      final incoming = await recipientDatabase.messages.getById(wireMessageId);
      expect(incoming?.contentType, StorageMessageContentType.voiceNote);
      expect(incoming?.caption, isNull);
      expect(incoming?.content.split('|'), hasLength(6));
    },
  );
}

class _FakeVoiceRecorderBackend implements VoiceRecorderBackend {
  final amplitudeController = StreamController<double>.broadcast();
  String? startedPath;
  String? outputPath;
  int pauses = 0;
  int resumes = 0;
  int cancels = 0;
  int disposals = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async => startedPath = path;

  @override
  Stream<double> amplitudes() => amplitudeController.stream;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<String?> stop() async {
    final path = outputPath ?? startedPath!;
    final file = File(path);
    if (!await file.exists()) await file.writeAsBytes([1, 2, 3, 4]);
    return path;
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> dispose() async {
    disposals++;
    await amplitudeController.close();
  }
}
