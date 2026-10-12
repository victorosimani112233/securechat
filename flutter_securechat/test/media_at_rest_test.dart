import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_message_service.dart';
import 'package:flutter_securechat/src/media/media_vault.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 11: alinan (ve gonderilen) dosyalar cihazda duz
/// duruyordu; `run-as ... cat` ile orijinal sha256'si okunabiliyordu.
void main() {
  late Directory root;
  late Directory media;
  late LocalAeadCryptoService crypto;
  late MediaVault vault;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media_at_rest_');
    media = Directory('${root.path}/media')..createSync();
    crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    vault = MediaVault(
      keyBytes: await crypto.deriveMediaKeyBytes(),
      mediaDirectory: media,
    );
  });
  tearDown(() => root.delete(recursive: true));

  Uint8List payload(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) % 256));

  Future<InMemorySignalingService> socket(String user) async {
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: user,
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    return signaling;
  }

  test(
    'a received file and its partial chunks are never plain on disk',
    () async {
      final signaling = await socket('me');
      final manager = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: media,
        chunkSize: 64,
        vault: vault,
      );
      addTearDown(manager.dispose);
      final data = payload(300);
      expect(
        await manager.sendStream(
          localUserId: 'me',
          recipientId: 'peer',
          stream: Stream.value(data),
          fileSize: data.length,
          fileName: 'qa_ikili.bin',
          mimeType: 'application/octet-stream',
        ),
        isA<FileTransferSuccess>(),
      );
      final chunks = signaling.sentMessages.whereType<FileTransferSignal>();

      ReceivedFile? received;
      var checkedParts = false;
      for (final chunk in chunks.toList().reversed) {
        received =
            await manager.receiveChunk(
              FileTransferSignal.fromJson({
                ...chunk.toJson(),
                'senderId': 'peer',
                'recipientId': 'me',
              }),
            ) ??
            received;
        if (received == null && !checkedParts) {
          final parts = Directory(
            '${media.path}/incoming_parts/${chunk.transferId}',
          ).listSync().whereType<File>().where((f) => f.path.endsWith('.part'));
          expect(parts, isNotEmpty);
          for (final part in parts) {
            expect(await MediaVault.isSealed(part), isTrue);
          }
          checkedParts = true;
        }
      }

      expect(checkedParts, isTrue);
      final stored = received!.file;
      expect(await MediaVault.isSealed(stored), isTrue);
      expect(_contains(stored.readAsBytesSync(), data.sublist(0, 32)), isFalse);
      expect((await vault.openForUse(stored)).readAsBytesSync(), data);
    },
  );

  test(
    'a sent file keeps a sealed copy and the peer still gets plain bytes',
    () async {
      final database = await SecureChatDatabase.open(
        file: File('${root.path}/db'),
        crypto: crypto,
      );
      addTearDown(database.close);
      final signaling = await socket('me');
      final sender = FileTransferManager(
        signaling: signaling,
        crypto: crypto,
        filesDirectory: media,
        vault: vault,
      );
      addTearDown(sender.dispose);
      final service = MediaMessageService(
        database: database,
        transfers: sender,
        session: SessionStore(userId: 'me', accessToken: 'token'),
        localMediaDirectory: media,
        vault: vault,
      );
      addTearDown(service.close);
      final data = payload(5000);
      final picked = File('${root.path}/picked.pdf')..writeAsBytesSync(data);

      final outcomes = await service.send(
        conversationId: 'peer',
        recipientId: 'peer',
        attachments: [await MediaAttachment.fromPath(picked.path)],
        isGroup: false,
        groupMembers: const [],
      );
      expect(outcomes.single.result, isA<FileTransferSuccess>());

      final message = LocalMessage.fromJson(
        (await database.messages.getMessagesImmediate('peer')).single.toJson(),
      );
      final retained = File(message.filePath!);
      expect(retained.path, startsWith('${media.path}/sent/'));
      expect(await MediaVault.isSealed(retained), isTrue);
      final usable = await service.usableMediaPath(message.filePath!);
      expect(File(usable!).readAsBytesSync(), data);

      // Karsi taraf duz dosyayi alir (vault'suz alici).
      final receiverRoot = Directory('${root.path}/peer')..createSync();
      // LocalAead test kriptosu anahtari karsi taraf etiketinden turetir;
      // ayni etiketle (peer) cozulur.
      final receiver = FileTransferManager(
        signaling: await socket('me'),
        crypto: crypto,
        filesDirectory: receiverRoot,
      );
      addTearDown(receiver.dispose);
      ReceivedFile? received;
      for (final chunk
          in signaling.sentMessages.whereType<FileTransferSignal>()) {
        received =
            await receiver.receiveChunk(
              FileTransferSignal.fromJson({
                ...chunk.toJson(),
                'senderId': 'peer',
                'recipientId': 'me',
              }),
            ) ??
            received;
      }
      expect(received!.file.readAsBytesSync(), data);
    },
  );

  test('display paths are opened copies; deletion removes both', () async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    addTearDown(database.close);
    final stored = File('${media.path}/received_files/1_foto.jpg');
    await stored.parent.create(recursive: true);
    final data = payload(1000);
    await vault.sealFiles([
      File('${root.path}/p')..writeAsBytesSync(data),
    ], stored);
    await database.messages.insert(
      MessageEntity(
        id: 'm1',
        conversationId: 'peer',
        senderId: 'peer',
        content: LocalMessage.buildFileContent(
          fileName: 'foto.jpg',
          mimeType: 'image/jpeg',
          fileSize: data.length,
          filePath: stored.path,
        ),
        contentType: StorageMessageContentType.image,
        timestamp: 1,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    final storage = StorageManagementService(
      database,
      mediaDirectory: media,
      vault: vault,
    );

    final shown = await storage.resolveMediaPath(stored.path);
    expect(shown, startsWith(vault.openDirectory.path));
    expect(File(shown!).readAsBytesSync(), data);
    expect(await storage.resolveStoredMediaPath(stored.path), stored.path);
    final opening = await storage.fileForOpening('peer', 'm1');
    expect(opening!.localPath, shown);

    await storage.cleanSelectedFiles('peer', ['m1']);
    expect(stored.existsSync(), isFalse);
    expect(File(shown).existsSync(), isFalse);
  });

  test('a file sealed with another key is treated as unavailable', () async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    addTearDown(database.close);
    final stored = File('${media.path}/received_files/x.bin');
    await stored.parent.create(recursive: true);
    final foreign = MediaVault(
      keyBytes: List.filled(32, 99),
      mediaDirectory: media,
    );
    await foreign.sealFiles([
      File('${root.path}/p')..writeAsBytesSync([1, 2, 3]),
    ], stored);
    final storage = StorageManagementService(
      database,
      mediaDirectory: media,
      vault: vault,
    );
    expect(await storage.resolveMediaPath(stored.path), isNull);
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
