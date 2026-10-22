import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/attachment_transport.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_vault.dart';
import 'package:flutter_securechat/src/media/peer_capabilities.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dosya bir kez muhurlenip HTTP ile yuklenir; alicilara yalniz sifreli
/// isaretci gider.
void main() {
  late Directory root;
  late LocalAeadCryptoService crypto;

  setUp(() async {
    root = Directory(
      await (await Directory.systemTemp.createTemp(
        'blob_attachment_',
      )).resolveSymbolicLinks(),
    );
    crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 3)),
    );
  });
  tearDown(() => root.delete(recursive: true));

  Uint8List payload(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 17 + 5) % 256));

  Future<InMemorySignalingService> socket(String user) async {
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: user,
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    return signaling;
  }

  Future<File> picked(Uint8List data) async =>
      File('${root.path}/picked.bin')..writeAsBytesSync(data);

  FileTransferSignal asReceived(FileTransferSignal signal) =>
      FileTransferSignal.fromJson({
        ...signal.toJson(),
        'senderId': 'peer',
        'recipientId': 'me',
      });

  Future<FileTransferManager> manager(
    SignalingService signaling,
    String directory, {
    AttachmentTransport? transport,
    bool capable = true,
    MediaVault? vault,
  }) async {
    final files = Directory('${root.path}/$directory')..createSync();
    final created = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: files,
      vault: vault,
      attachments: transport,
      canReceiveBlobs: (_) async => capable,
      blobDownloadDelays: const [Duration.zero, Duration.zero],
    );
    addTearDown(created.dispose);
    return created;
  }

  test('a file is uploaded once and only a pointer is sent', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final sender = await manager(signaling, 'sender', transport: server);
    final data = payload(300 * 1024);

    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(data),
      mimeType: 'application/pdf',
      fileName: 'rapor.pdf',
      caption: 'gizli not',
    );

    expect(result, isA<FileTransferSuccess>());
    expect(server.blobs, hasLength(1));
    final uploaded = server.blobs.values.single;
    // Sunucu muhurlu baytlari gorur; ne icerik ne ad ne not.
    expect(
      await MediaVault.isSealed(
        File('${root.path}/x')..writeAsBytesSync(uploaded),
      ),
      isTrue,
    );
    expect(String.fromCharCodes(uploaded), isNot(contains('rapor')));
    final frames = signaling.sentMessages.whereType<FileTransferSignal>();
    expect(frames, hasLength(1));
    expect(frames.single.encryption, FileTransferManager.blobWireVersion);
    expect(frames.single.fileSize, 0);
    expect(frames.single.toJson().toString(), isNot(contains('rapor')));

    final vault = MediaVault(
      keyBytes: List.filled(32, 9),
      mediaDirectory: Directory('${root.path}/receiver'),
    );
    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: server,
      vault: vault,
    );
    final received = await receiver.receiveChunk(asReceived(frames.single));
    expect(received, isNotNull);
    expect(received!.fileName, 'rapor.pdf');
    expect(received.caption, 'gizli not');
    expect(received.fileSize, data.length);
    // Alinan kopya yerel anahtarla muhurlu; acinca ayni icerik.
    expect(await MediaVault.isSealed(received.file), isTrue);
    final opened = await vault.openForUse(received.file);
    expect(opened.readAsBytesSync(), data);
  });

  test('peers without the capability get the chunked transfer', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final sender = await manager(
      signaling,
      'sender',
      transport: server,
      capable: false,
    );
    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(payload(5000)),
      mimeType: 'application/pdf',
    );
    expect(result, isA<FileTransferSuccess>());
    expect(server.blobs, isEmpty);
    expect(
      signaling.sentMessages.whereType<FileTransferSignal>().single.encryption,
      FileTransferManager.directWireVersion,
    );
  });

  test(
    'a server without attachments falls back before sending anything',
    () async {
      final server = _MemoryTransport()..rejectUpload = 404;
      final signaling = await socket('me');
      final sender = await manager(signaling, 'sender', transport: server);
      final result = await sender.sendFile(
        localUserId: 'me',
        recipientId: 'peer',
        file: await picked(payload(5000)),
        mimeType: 'application/pdf',
      );
      expect(result, isA<FileTransferSuccess>());
      final frames = signaling.sentMessages.whereType<FileTransferSignal>();
      expect(
        frames.every(
          (f) => f.encryption != FileTransferManager.blobWireVersion,
        ),
        isTrue,
      );
      expect(frames, isNotEmpty);
    },
  );

  test('a failed download is kept and retried later', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final sender = await manager(signaling, 'sender', transport: server);
    final data = payload(70 * 1024);
    await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(data),
      mimeType: 'image/png',
      fileName: 'foto.png',
    );
    final pointer = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .single;

    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: server,
    );
    final delivered = <ReceivedFile>[];
    receiver.receivedFiles.listen(delivered.add);
    server.failDownloads = true;
    expect(await receiver.receiveChunk(asReceived(pointer)), isNull);
    final pending = Directory(
      '${root.path}/receiver/incoming_blobs',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.pending'));
    expect(pending, hasLength(1));
    // Isaretci (anahtar dahil) diske duz yazilmaz.
    expect(pending.single.readAsStringSync(), isNot(contains('foto.png')));

    server.failDownloads = false;
    await receiver.retryPendingBlobs();
    expect(delivered.single.file.readAsBytesSync(), data);
    expect(
      Directory('${root.path}/receiver/incoming_blobs').listSync(),
      isEmpty,
    );
  });

  test('a tampered attachment is rejected and not retried', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final sender = await manager(signaling, 'sender', transport: server);
    await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(payload(10000)),
      mimeType: 'application/pdf',
    );
    final id = server.blobs.keys.single;
    final bytes = server.blobs[id]!;
    bytes[bytes.length - 20] ^= 0x01;

    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: server,
    );
    final received = await receiver.receiveChunk(
      asReceived(signaling.sentMessages.whereType<FileTransferSignal>().single),
    );
    expect(received, isNull);
    expect(
      Directory('${root.path}/receiver/incoming_blobs').listSync(),
      isEmpty,
    );
    expect(
      Directory('${root.path}/receiver/received_files').existsSync()
          ? Directory('${root.path}/receiver/received_files').listSync()
          : const [],
      isEmpty,
    );
  });

  test('a group file is uploaded once for every member', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final sender = await manager(signaling, 'sender', transport: server);
    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'group-1',
      file: await picked(payload(200 * 1024)),
      mimeType: 'video/mp4',
      isGroup: true,
      groupMembers: const ['me', 'a', 'b', 'c'],
    );
    expect(result, isA<FileTransferSuccess>());
    expect(server.blobs, hasLength(1));
    final pointers = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .where((f) => f.encryption == FileTransferManager.blobGroupWireVersion)
        .map((f) => f.recipientId)
        .toSet();
    expect(pointers, {'a', 'b', 'c'});
  });

  test('receipts announce and withdraw the capability', () async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/db'),
      crypto: crypto,
    );
    addTearDown(database.close);
    final capabilities = PeerCapabilities(database.cryptoState);
    await capabilities.record('a', localPeerCapabilities);
    await capabilities.record('b', localPeerCapabilities);
    expect(
      await capabilities.allSupport({'a', 'b'}, blobAttachmentCapability),
      isTrue,
    );
    // Eski surume donen kisi yetenegi kaybeder.
    await capabilities.record('b', const []);
    expect(
      await capabilities.allSupport({'a', 'b'}, blobAttachmentCapability),
      isFalse,
    );
    expect(
      await capabilities.allSupport(const {}, blobAttachmentCapability),
      isFalse,
    );

    final receipt = DeliveryReceiptSignal(
      senderId: 'a',
      recipientId: 'me',
      timestamp: DateTime(2026),
      messageId: 'm',
      status: 'DELIVERED',
      capabilities: localPeerCapabilities,
    );
    final decoded =
        SignalMessage.decode(receipt.encode()) as DeliveryReceiptSignal;
    expect(decoded.capabilities, localPeerCapabilities);
    final legacy = Map.of(receipt.toJson())..remove('capabilities');
    expect(DeliveryReceiptSignal.fromJson(legacy).capabilities, isEmpty);
  });
}

class _MemoryTransport implements AttachmentTransport {
  final blobs = <String, Uint8List>{};
  int? rejectUpload;
  bool failDownloads = false;
  var _next = 0;

  @override
  Future<String> upload(File sealed) async {
    final status = rejectUpload;
    if (status != null) {
      throw AttachmentTransportException('rejected', statusCode: status);
    }
    final id = (_next++).toString().padLeft(43, 'A');
    blobs[id] = sealed.readAsBytesSync();
    return id;
  }

  @override
  Future<void> download(String id, File target, {required int maxBytes}) async {
    if (failDownloads) throw const SocketException('offline');
    final bytes = blobs[id];
    if (bytes == null) {
      throw const AttachmentTransportException('gone', statusCode: 404);
    }
    if (bytes.length > maxBytes) {
      throw const AttachmentTransportException('too large');
    }
    target.writeAsBytesSync(bytes);
  }
}
