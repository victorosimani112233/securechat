import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/media/attachment_transport.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_vault.dart';
import 'package:flutter_securechat/src/media/peer_capabilities.dart';
import 'package:flutter_securechat/src/network/network_resilience.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';

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
    List<(EncryptedSignalMessage, String)>? outbox,
    ReliableSignalSender? reliableSender,
  }) async {
    final files = Directory('${root.path}/$directory')..createSync();
    final created = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: files,
      vault: vault,
      attachments: transport,
      canReceiveBlobs: (_) async => capable,
      reliableSender:
          reliableSender ??
          (signal, {required messageId}) async {
            outbox?.add((signal, messageId));
            return true;
          },
      blobDownloadDelays: const [Duration.zero, Duration.zero],
    );
    addTearDown(created.dispose);
    return created;
  }

  // Test sifrelemesinde anahtar hedef etiketinden turetilir.
  Future<String> pointerOf(EncryptedSignalMessage wire) async {
    final plaintext = await crypto.decryptDirect(
      senderId: wire.recipientId,
      envelope: wire.envelope,
    );
    expect(plaintext, startsWith(blobPointerPrefix));
    return plaintext.substring(blobPointerPrefix.length);
  }

  Iterable<File> pendingIn(String directory) {
    final staging = Directory('${root.path}/$directory/incoming_blobs');
    if (!staging.existsSync()) return const [];
    return staging.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.pending'),
    );
  }

  test('a file is uploaded once and the pointer goes to the outbox', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final outbox = <(EncryptedSignalMessage, String)>[];
    final sender = await manager(
      signaling,
      'sender',
      transport: server,
      outbox: outbox,
    );
    final data = payload(300 * 1024);

    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(data),
      mimeType: 'application/pdf',
      fileName: 'rapor.pdf',
      caption: 'gizli not',
      originalMessageId: 'media-1',
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
    // Isaretci dosya cercevesiyle degil, teslim onayli mesajla gider.
    expect(signaling.sentMessages.whereType<FileTransferSignal>(), isEmpty);
    final (wire, messageId) = outbox.single;
    expect(messageId, 'media-1');
    expect(wire.recipientId, 'peer');
    expect(wire.deliveryId, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(wire.toJson().toString(), isNot(contains('rapor')));

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
    final delivered = receiver.receivedFiles.first;
    expect(
      await receiver.acceptBlobPointer(
        senderId: 'peer',
        groupId: null,
        payload: await pointerOf(wire),
      ),
      'media-1',
    );
    final received = await delivered;
    expect(received.fileName, 'rapor.pdf');
    expect(received.caption, 'gizli not');
    expect(received.fileSize, data.length);
    expect(received.originalMessageId, 'media-1');
    // Alinan kopya yerel anahtarla muhurlu; acinca ayni icerik.
    expect(await MediaVault.isSealed(received.file), isTrue);
    final opened = await vault.openForUse(received.file);
    expect(opened.readAsBytesSync(), data);
    await receiver.waitForIdle();
    expect(pendingIn('receiver'), isEmpty);
  });

  test('the pointer stays in the outbox until the receipt arrives', () async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/outbox-db'),
      crypto: crypto,
    );
    addTearDown(database.close);
    final signaling = await socket('me');
    final queue = OfflineMessageQueue(database: database, signaling: signaling);
    addTearDown(queue.close);
    final server = _MemoryTransport();
    final sender = await manager(
      signaling,
      'sender',
      transport: server,
      reliableSender: queue.sendReliably,
    );
    final file = await picked(payload(4000));
    // Soket gonderimi basarili olsa da kayit makbuza kadar kalir: alici
    // cevrimdisiysa kuyruk yeniden gonderir.
    expect(
      await sender.sendFile(
        localUserId: 'me',
        recipientId: 'peer',
        file: file,
        mimeType: 'image/png',
        originalMessageId: 'media-2',
      ),
      isA<FileTransferSuccess>(),
    );
    final pending = await database.pendingSignals.getAll();
    expect(pending.single.messageId, 'media-2');
    expect(pending.single.recipientId, 'peer');
    expect(pending.single.retainUntilReceipt, isTrue);
    expect(pending.single.encodedSignal, isNot(contains(blobPointerPrefix)));

    await queue.acknowledgeReceipt('media-2', 'peer');
    expect(await database.pendingSignals.getAll(), isEmpty);
  });

  test('without a message id the chunked transfer is used', () async {
    final server = _MemoryTransport();
    final signaling = await socket('me');
    final outbox = <(EncryptedSignalMessage, String)>[];
    final sender = await manager(
      signaling,
      'sender',
      transport: server,
      outbox: outbox,
    );
    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(payload(5000)),
      mimeType: 'application/pdf',
    );
    expect(result, isA<FileTransferSuccess>());
    expect(server.blobs, isEmpty);
    expect(outbox, isEmpty);
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
      originalMessageId: 'media-3',
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
      final outbox = <(EncryptedSignalMessage, String)>[];
      final sender = await manager(
        signaling,
        'sender',
        transport: server,
        outbox: outbox,
      );
      final result = await sender.sendFile(
        localUserId: 'me',
        recipientId: 'peer',
        file: await picked(payload(5000)),
        mimeType: 'application/pdf',
        originalMessageId: 'media-4',
      );
      expect(result, isA<FileTransferSuccess>());
      expect(outbox, isEmpty);
      expect(
        signaling.sentMessages.whereType<FileTransferSignal>(),
        isNotEmpty,
      );
    },
  );

  test('a failed download is kept and retried later', () async {
    final server = _MemoryTransport();
    final outbox = <(EncryptedSignalMessage, String)>[];
    final sender = await manager(
      await socket('me'),
      'sender',
      transport: server,
      outbox: outbox,
    );
    final data = payload(70 * 1024);
    await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(data),
      mimeType: 'image/png',
      fileName: 'foto.png',
      originalMessageId: 'media-5',
    );

    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: server,
    );
    final delivered = <ReceivedFile>[];
    receiver.receivedFiles.listen(delivered.add);
    server.failDownloads = true;
    // Indirme olmasa da isaretci kaydedilir; makbuz gonderilebilir.
    expect(
      await receiver.acceptBlobPointer(
        senderId: 'peer',
        groupId: null,
        payload: await pointerOf(outbox.single.$1),
      ),
      'media-5',
    );
    await receiver.waitForIdle();
    expect(delivered, isEmpty);
    final pending = pendingIn('receiver');
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
    final outbox = <(EncryptedSignalMessage, String)>[];
    final sender = await manager(
      await socket('me'),
      'sender',
      transport: server,
      outbox: outbox,
    );
    await sender.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: await picked(payload(10000)),
      mimeType: 'application/pdf',
      originalMessageId: 'media-6',
    );
    final id = server.blobs.keys.single;
    final bytes = server.blobs[id]!;
    bytes[bytes.length - 20] ^= 0x01;

    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: server,
    );
    final delivered = <ReceivedFile>[];
    receiver.receivedFiles.listen(delivered.add);
    await receiver.acceptBlobPointer(
      senderId: 'peer',
      groupId: null,
      payload: await pointerOf(outbox.single.$1),
    );
    await receiver.waitForIdle();
    expect(delivered, isEmpty);
    expect(pendingIn('receiver'), isEmpty);
    expect(
      Directory('${root.path}/receiver/received_files').existsSync()
          ? Directory('${root.path}/receiver/received_files').listSync()
          : const [],
      isEmpty,
    );
  });

  test('a malformed pointer is refused', () async {
    final receiver = await manager(
      await socket('me'),
      'receiver',
      transport: _MemoryTransport(),
    );
    for (final payload in ['{', '[]', '{"v":1}']) {
      await expectLater(
        receiver.acceptBlobPointer(
          senderId: 'peer',
          groupId: null,
          payload: payload,
        ),
        throwsFormatException,
      );
    }
    expect(pendingIn('receiver'), isEmpty);
  });

  test('a group file is uploaded once for every member', () async {
    final server = _MemoryTransport();
    final outbox = <(EncryptedSignalMessage, String)>[];
    final signaling = await socket('me');
    final sender = await manager(
      signaling,
      'sender',
      transport: server,
      outbox: outbox,
    );
    final result = await sender.sendFile(
      localUserId: 'me',
      recipientId: 'group-1',
      file: await picked(payload(200 * 1024)),
      mimeType: 'video/mp4',
      isGroup: true,
      groupMembers: const ['me', 'a', 'b', 'c'],
      originalMessageId: 'media-g',
    );
    expect(result, isA<FileTransferSuccess>());
    expect(server.blobs, hasLength(1));
    // Grup anahtari ve isaretci ayni mesaja bagli; ikisi de makbuza kadar
    // tutulur.
    expect(outbox.map((entry) => entry.$2).toSet(), {'media-g'});
    expect(outbox.map((entry) => entry.$1.recipientId).toSet(), {
      'a',
      'b',
      'c',
    });
    expect(signaling.sentMessages.whereType<FileTransferSignal>(), isEmpty);
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
    // Yalniz ilk HTTP surumunu bildiren isaretciyi mesajla alamaz.
    await capabilities.record('b', const [legacyBlobAttachmentCapability]);
    expect(
      await capabilities.allSupport({'a', 'b'}, blobAttachmentCapability),
      isFalse,
    );
    // Eski surume donen kisi yetenegi kaybeder.
    await capabilities.record('a', const []);
    expect(
      await capabilities.allSupport({'a'}, blobAttachmentCapability),
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

  group('incoming pointer', () {
    late SecureChatDatabase database;
    late InMemorySignalingService signaling;
    final failures = <Object>[];

    Future<IncomingMessageHandler> handler(BlobPointerReceiver? accept) async {
      database = await SecureChatDatabase.open(
        file: File('${root.path}/handler-db'),
        crypto: crypto,
      );
      addTearDown(database.close);
      signaling = await socket('me');
      final created = IncomingMessageHandler(
        signaling: signaling,
        crypto: crypto,
        database: database,
        session: SessionStore(userId: 'me', accessToken: 'token'),
        acceptBlobPointer: accept,
        onAsyncFailure: (operation, error, stackTrace) async {
          failures.add('$operation $error\n$stackTrace');
        },
      )..start();
      addTearDown(created.close);
      return created;
    }

    Future<EncryptedSignalMessage> incomingPointer(String messageId) async {
      final server = _MemoryTransport();
      final outbox = <(EncryptedSignalMessage, String)>[];
      final sender = await manager(
        await socket('peer'),
        'peer-$messageId',
        transport: server,
        outbox: outbox,
      );
      await sender.sendFile(
        localUserId: 'peer',
        recipientId: 'me',
        file: await picked(payload(3000)),
        mimeType: 'image/png',
        originalMessageId: messageId,
      );
      return EncryptedSignalMessage(
        senderId: 'peer',
        recipientId: 'me',
        timestamp: DateTime.now(),
        envelope: outbox.single.$1.envelope,
        deliveryToken: List.filled(43, 'P').join(),
      );
    }

    test('a stored pointer is acknowledged with a delivery receipt', () async {
      final accepted = <(String, String?)>[];
      final incoming = await handler(({
        required senderId,
        required groupId,
        required payload,
      }) async {
        accepted.add((senderId, groupId));
        expect((jsonDecode(payload) as Map)['id'], isA<String>());
        return 'media-7';
      });
      signaling.addIncoming(await incomingPointer('media-7'));
      await incoming.waitForIdle();

      expect(accepted, [('peer', null)]);
      // Pointer sohbete metin olarak yazilmaz.
      expect(await database.messages.getMessageCount('peer'), 0);
      expect(failures, isEmpty);
      final receipts = <DeliveryReceiptSignal>[];
      for (final wire
          in signaling.sentMessages.whereType<EncryptedSignalMessage>()) {
        receipts.add(
          await decryptTestPrivateChatControl(crypto: crypto, wire: wire)
              as DeliveryReceiptSignal,
        );
      }
      expect(receipts.single.messageId, 'media-7');
      expect(receipts.single.status, 'DELIVERED');
      expect(
        signaling.sentMessages.whereType<DeliveryTransportAckSignal>(),
        hasLength(1),
      );
    });

    test('a pointer that cannot be stored is not acknowledged', () async {
      final incoming = await handler(
        ({required senderId, required groupId, required payload}) async => null,
      );
      signaling.addIncoming(await incomingPointer('media-8'));
      await incoming.waitForIdle();
      // Sunucu tutar ve sonraki baglantida yeniden teslim eder.
      expect(signaling.sentMessages, isEmpty);
      expect(await database.messages.getMessageCount('peer'), 0);
    });
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
