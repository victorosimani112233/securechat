import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/signal_message.dart';
import '../crypto/group_sender_key_distribution.dart';
import '../groups/private_group_route.dart';
import '../services/crypto_service.dart';
import '../services/async_operation_tracker.dart';
import '../services/signaling_service.dart';

sealed class FileTransferResult {
  const FileTransferResult();
}

class FileTransferSuccess extends FileTransferResult {
  const FileTransferSuccess({
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });
  final String transferId;
  final String fileName;
  final String mimeType;
  final int fileSize;
}

class FileTransferFailure extends FileTransferResult {
  const FileTransferFailure(this.message);
  final String message;
}

class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.chunksTransferred,
    required this.totalChunks,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.incoming,
  });
  final String transferId;
  final int chunksTransferred;
  final int totalChunks;
  final int bytesTransferred;
  final int totalBytes;
  final bool incoming;

  int get percent => totalBytes == 0
      ? 100
      : ((bytesTransferred * 100) ~/ totalBytes).clamp(0, 100);
}

class ReceivedFile {
  const ReceivedFile({
    required this.transferId,
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.senderId,
    required this.fileSize,
    this.caption,
    this.isViewOnce = false,
    this.originalMessageId,
    this.absoluteExpiresAt,
    this.groupId,
  });
  final String transferId;
  final File file;
  final String fileName;
  final String mimeType;
  final String senderId;
  final int fileSize;
  final String? caption;
  final bool isViewOnce;
  final String? originalMessageId;
  final DateTime? absoluteExpiresAt;
  final String? groupId;
}

typedef GroupRoutingResolver = Future<String?> Function(String routingToken);

class FileTransferManager {
  FileTransferManager({
    required SignalingService signaling,
    required CryptoService crypto,
    required Directory filesDirectory,
    this.chunkSize = 128 * 1024,
    this.maximumFileSize = 100 * 1024 * 1024,
    this.staleTransferAge = const Duration(minutes: 10),
    GroupRoutingResolver? groupRoutingResolver,
    LocalAeadCryptoService? metadataCrypto,
    Future<void> Function()? beforeReceive,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _signaling = signaling,
       _crypto = crypto,
       _filesDirectory = filesDirectory,
       _groupRoutingResolver = groupRoutingResolver,
       _beforeReceive = beforeReceive,
       _onAsyncFailure = onAsyncFailure,
       _metadataCrypto = _requireMetadataCrypto(crypto, metadataCrypto),
       _operations = AsyncOperationTracker(onFailure: onAsyncFailure) {
    _subscription = signaling.incoming
        .where((event) => event is FileTransferSignal)
        .cast<FileTransferSignal>()
        .listen(_receiveFromSocket);
  }

  final SignalingService _signaling;
  final CryptoService _crypto;
  final Directory _filesDirectory;
  final GroupRoutingResolver? _groupRoutingResolver;
  final Future<void> Function()? _beforeReceive;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  final LocalAeadCryptoService _metadataCrypto;
  final int chunkSize;

  final int maximumFileSize;
  final Duration staleTransferAge;
  final AsyncOperationTracker _operations;
  final _progress = StreamController<TransferProgress?>.broadcast();
  final _activity = StreamController<bool>.broadcast(sync: true);
  final Map<String, Timer> _receivingActivity = {};
  int _sendingCount = 0;
  bool _lastActivity = false;
  // A completed receive is published synchronously so downstream owners can
  // register persistence work before receiveChunk completes. The persistence
  // itself remains async and is drained by MediaMessageService.waitForIdle.
  final _receivedFiles = StreamController<ReceivedFile>.broadcast(sync: true);
  final Map<String, Future<void>> _receiveTails = {};
  final _random = Random.secure();
  late final StreamSubscription<FileTransferSignal> _subscription;
  Future<void>? _disposeTask;
  bool _disposed = false;

  /// v4 oncesinde sifreli zarf, JSON `data`/`caption` alanina konmadan once
  /// gereksiz yere bir kez daha base64'leniyordu. Zarf zaten saf ASCII
  /// (`E2EE:v1:...`), yani bu katman hicbir sey kazandirmiyordu ama parca
  /// basina 1,333x sisme ekliyordu. Uc katman birlesince 128 KiB'lik ham
  /// parca telde 311 KB oluyor ve hem istemcinin 256 KiB decode limitini
  /// hem de sunucunun maxFrameSize'ini asiyordu; yani dolu parcalar hic
  /// teslim edilemiyordu.
  ///
  /// v4 zarfi oldugu gibi tasir. Eski gonderenlerle uyum icin v2/v3
  /// cozumu korunur.
  static const directWireVersion = 'flutter-file-v4-direct';
  // Recipient-specific group routing adds two more encoding layers. Reserve
  // room for the last chunk's encrypted manifest, including a full caption.
  static const maximumGroupChunkSize = 48 * 1024;
  static const groupWireVersion = 'flutter-file-v5-group';

  static bool _isRawEnvelopeWire(String? encryption) =>
      encryption != null &&
      (encryption.startsWith('flutter-file-v4-') ||
          encryption == groupWireVersion);

  /// Tel alanindan sifreli zarfi cikarir. v4/v5 ham, oncesi base64.
  static String _decodeEnvelopeField(String value, String? encryption) =>
      _isRawEnvelopeWire(encryption) ? value : utf8.decode(base64Decode(value));

  Stream<TransferProgress?> get progress => _progress.stream;
  Stream<bool> get activity => _activity.stream;
  bool get hasActiveTransfers =>
      _sendingCount > 0 || _receivingActivity.isNotEmpty;
  Stream<ReceivedFile> get receivedFiles => _receivedFiles.stream;

  void _publishActivity() {
    final active = !_disposed && hasActiveTransfers;
    if (_activity.isClosed || active == _lastActivity) return;
    _lastActivity = active;
    _activity.add(active);
  }

  void _touchReceivingActivity(String transferId) {
    if (_disposed) return;
    _receivingActivity.remove(transferId)?.cancel();
    // A lost final chunk must not hold the background socket indefinitely.
    _receivingActivity[transferId] = Timer(staleTransferAge, () {
      _endReceivingActivity(transferId);
    });
    _publishActivity();
  }

  void _endReceivingActivity(String transferId) {
    _receivingActivity.remove(transferId)?.cancel();
    _publishActivity();
  }

  void _receiveFromSocket(FileTransferSignal signal) {
    if (signal.chunkIndex % 32 == 0 ||
        signal.chunkIndex == signal.totalChunks - 1) {
      _trace('rx-frame index=${signal.chunkIndex} total=${signal.totalChunks}');
    }
    if (_disposed) return;
    _operations.run('file-transfer.receive-chunk', receiveChunk(signal));
  }

  Future<FileTransferResult?> pickAndSend({
    required String localUserId,
    required String recipientId,
    bool isGroup = false,
    List<String> groupMembers = const [],
    String? caption,
    bool isViewOnce = false,
    String? originalMessageId,
    DateTime? absoluteExpiresAt,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final stream =
        picked.readStream ??
        (picked.path == null ? null : File(picked.path!).openRead());
    if (stream == null) {
      return const FileTransferFailure('Secilen dosya okunamadi');
    }
    return sendStream(
      localUserId: localUserId,
      recipientId: recipientId,
      stream: stream,
      fileSize: picked.size,
      fileName: picked.name,
      mimeType: _mimeFromName(picked.name),
      isGroup: isGroup,
      groupMembers: groupMembers,
      caption: caption,
      isViewOnce: isViewOnce,
      originalMessageId: originalMessageId,
      absoluteExpiresAt: absoluteExpiresAt,
    );
  }

  Future<FileTransferResult> sendFile({
    required String localUserId,
    required String recipientId,
    required File file,
    required String mimeType,
    String? fileName,
    bool isGroup = false,
    List<String> groupMembers = const [],
    String? caption,
    bool isViewOnce = false,
    String? originalMessageId,
    DateTime? absoluteExpiresAt,
  }) async {
    final size = await file.length();
    return sendStream(
      localUserId: localUserId,
      recipientId: recipientId,
      stream: file.openRead(),
      fileSize: size,
      fileName: fileName ?? file.uri.pathSegments.last,
      mimeType: mimeType,
      isGroup: isGroup,
      groupMembers: groupMembers,
      caption: caption,
      isViewOnce: isViewOnce,
      originalMessageId: originalMessageId,
      absoluteExpiresAt: absoluteExpiresAt,
    );
  }

  Future<FileTransferResult> sendStream({
    required String localUserId,
    required String recipientId,
    required Stream<List<int>> stream,
    required int fileSize,
    required String fileName,
    required String mimeType,
    bool isGroup = false,
    List<String> groupMembers = const [],
    String? caption,
    bool isViewOnce = false,
    String? originalMessageId,
    DateTime? absoluteExpiresAt,
  }) async {
    if (_disposed) return const FileTransferFailure('Dosya aktarimi kapatildi');
    if (fileSize < 0 || fileSize > maximumFileSize) {
      return FileTransferFailure(
        'Dosya boyutu izin verilen siniri asiyor '
        '(${maximumFileSize ~/ (1024 * 1024)} MB)',
      );
    }
    if (!await _signaling.ensureConnected(
      timeout: const Duration(seconds: 8),
    )) {
      return const FileTransferFailure('Signaling baglantisi kurulamadi');
    }
    final transferId = _newId();
    final transferChunkSize = isGroup
        ? min(chunkSize, maximumGroupChunkSize)
        : chunkSize;
    final totalChunks = max(
      1,
      (fileSize + transferChunkSize - 1) ~/ transferChunkSize,
    );
    final reader = _ChunkReader(stream, transferChunkSize);
    final safeFileName = sanitizeFileName(fileName);
    final safeMimeType = _normalizeMimeType(mimeType);
    final privateManifest = jsonEncode(
      _PrivateFileManifest(
        fileName: safeFileName,
        mimeType: safeMimeType,
        fileSize: fileSize,
        caption: caption,
        isViewOnce: isViewOnce,
        originalMessageId: originalMessageId,
        absoluteExpiresAt: absoluteExpiresAt,
      ).toJson(),
    );
    var bytesSent = 0;
    _sendingCount++;
    _publishActivity();
    try {
      if (isGroup) {
        if (!groupMembers.contains(localUserId) ||
            groupMembers.toSet().length < 2) {
          return const FileTransferFailure('Group membership is required');
        }
        await distributeGroupSenderKey(
          crypto: _crypto,
          senderId: localUserId,
          groupId: recipientId,
          members: groupMembers,
          timestamp: DateTime.now(),
          send: _signaling.send,
        );
      }
      for (var index = 0; index < totalChunks; index++) {
        final bytes = await reader.nextChunk();
        if (index < totalChunks - 1 && bytes.length != transferChunkSize) {
          return const FileTransferFailure('Dosya beklenenden erken sonlandi');
        }
        bytesSent += bytes.length;
        final plaintext = base64Encode(bytes);
        final encrypted = isGroup
            ? await _crypto.encryptGroup(
                senderId: localUserId,
                groupId: recipientId,
                plaintext: plaintext,
              )
            : await _crypto.encryptDirect(
                recipientId: recipientId,
                plaintext: plaintext,
              );
        final isLast = index == totalChunks - 1;
        final encryptedManifest = !isLast
            ? null
            : isGroup
            ? await _crypto.encryptGroup(
                senderId: localUserId,
                groupId: recipientId,
                plaintext: privateManifest,
              )
            : await _crypto.encryptDirect(
                recipientId: recipientId,
                plaintext: privateManifest,
              );
        final recipients = isGroup && groupMembers.isNotEmpty
            ? groupMembers.where((id) => id != localUserId).toSet()
            : {recipientId};
        if (recipients.isEmpty) {
          return const FileTransferFailure('Dosya icin alici bulunamadi');
        }
        var allSent = true;
        for (final target in recipients) {
          final routedEnvelope = isGroup
              ? await _crypto.encryptDirect(
                  recipientId: target,
                  plaintext: encodePrivateGroupRoute(
                    groupId: recipientId,
                    groupEnvelope: encrypted,
                  ),
                )
              : encrypted;
          final routedManifest = encryptedManifest == null
              ? null
              : isGroup
              ? await _crypto.encryptDirect(
                  recipientId: target,
                  plaintext: encodePrivateGroupRoute(
                    groupId: recipientId,
                    groupEnvelope: encryptedManifest,
                  ),
                )
              : encryptedManifest;
          final signal = FileTransferSignal(
            senderId: localUserId,
            recipientId: target,
            timestamp: DateTime.now(),
            fileName: 'attachment.bin',
            mimeType: 'application/octet-stream',
            // Exact size is authenticated inside the encrypted v2 manifest.
            // The wire exposes only a chunk-aligned upper bound.
            fileSize: totalChunks * transferChunkSize,
            // v4: zarf ham tasiniyor. Zaten ASCII oldugu icin ek base64
            // katmani yalnizca sisme uretiyordu (bkz directWireVersion).
            data: routedEnvelope,
            transferId: transferId,
            chunkIndex: index,
            totalChunks: totalChunks,
            caption: routedManifest,
            encryption: isGroup ? groupWireVersion : directWireVersion,
          );
          if (!await _sendWithRetry(signal)) allSent = false;
        }
        if (!allSent) {
          return FileTransferFailure(
            'Dosya gonderilemedi (parca ${index + 1}/$totalChunks)',
          );
        }
        _progress.add(
          TransferProgress(
            transferId: transferId,
            chunksTransferred: index + 1,
            totalChunks: totalChunks,
            bytesTransferred: bytesSent,
            totalBytes: fileSize,
            incoming: false,
          ),
        );
        if (index % 32 == 0 || isLast) {
          _trace(
            'tx-progress group=$isGroup parts=${index + 1} total=$totalChunks',
          );
        }
      }
      if (bytesSent != fileSize) {
        return const FileTransferFailure(
          'Dosya boyutu aktarim sirasinda degisti',
        );
      }
      return FileTransferSuccess(
        transferId: transferId,
        fileName: safeFileName,
        mimeType: safeMimeType,
        fileSize: bytesSent,
      );
    } catch (error, stackTrace) {
      await _reportFailure('file-transfer.send', error, stackTrace);
      return FileTransferFailure('Sifreli dosya aktarimi basarisiz: $error');
    } finally {
      try {
        await reader.close();
        if (!_progress.isClosed) _progress.add(null);
      } finally {
        _sendingCount--;
        _publishActivity();
      }
    }
  }

  Future<ReceivedFile?> receiveChunk(FileTransferSignal signal) async {
    if (_disposed) return null;
    final transferId = signal.transferId ?? _legacyTransferId(signal);
    final previous = _receiveTails[transferId] ?? Future<void>.value();
    final result = previous
        .catchError((_) {
          // The core receive path contains failures. This guard prevents one
          // unexpected failure from permanently poisoning the keyed queue.
        })
        .then((_) async {
          // Earlier encrypted controls install SenderKeys in another socket
          // subscriber; preserve their wire order before decrypting media.
          await _beforeReceive?.call();
          return _receiveChunkSerial(signal, transferId);
        });
    late final Future<void> tail;
    tail = result.then<void>((_) {}, onError: (_, _) {}).whenComplete(() {
      if (identical(_receiveTails[transferId], tail)) {
        _receiveTails.remove(transferId);
      }
    });
    _receiveTails[transferId] = tail;
    return result;
  }

  Future<ReceivedFile?> _receiveChunkSerial(
    FileTransferSignal signal,
    String transferId,
  ) async {
    final privateWire =
        signal.encryption?.startsWith('flutter-file-v2-') == true ||
        signal.encryption?.startsWith('flutter-file-v3-') == true ||
        signal.encryption?.startsWith('flutter-file-v4-') == true ||
        signal.encryption == groupWireVersion;
    final transferChunkSize = signal.encryption == groupWireVersion
        ? min(chunkSize, maximumGroupChunkSize)
        : chunkSize;
    final maximumWireSize = privateWire
        ? maximumFileSize + chunkSize - 1
        : maximumFileSize;
    if (signal.fileSize < 0 || signal.fileSize > maximumWireSize) {
      _trace('rx-reject size');
      return null;
    }
    if (signal.totalChunks < 1 ||
        signal.chunkIndex < 0 ||
        signal.chunkIndex >= signal.totalChunks) {
      _trace('rx-reject index');
      return null;
    }
    if (privateWire &&
        signal.fileSize != signal.totalChunks * transferChunkSize) {
      _trace('rx-reject chunk-size');
      return null;
    }
    final partDirectory = Directory(
      '${_filesDirectory.path}/incoming_parts/$transferId',
    );
    final metadata = File('${partDirectory.path}/metadata.secure');
    _touchReceivingActivity(transferId);
    try {
      await partDirectory.create(recursive: true);
      final expected = _TransferMetadata.fromSignal(signal);
      late _TransferMetadata stored;
      if (await metadata.exists()) {
        final plaintext = await _metadataCrypto.decryptStorageJson(
          await metadata.readAsString(),
        );
        stored = _TransferMetadata.fromJson(
          jsonDecode(plaintext) as Map<String, Object?>,
        );
        if (!stored.matches(expected)) {
          await partDirectory.delete(recursive: true);
          return null;
        }
        stored = stored.mergeSignal(signal);
        await metadata.writeAsString(
          await _metadataCrypto.encryptStorageJson(jsonEncode(stored.toJson())),
          flush: true,
        );
      } else {
        stored = expected;
        await metadata.writeAsString(
          await _metadataCrypto.encryptStorageJson(
            jsonEncode(expected.toJson()),
          ),
          flush: true,
        );
      }
      final envelope = _decodeEnvelopeField(signal.data, stored.encryption);
      final privateGroupV2 = stored.encryption == 'flutter-file-v2-group';
      // v3 ve v4 ayni ozel-grup yonlendirme semantigini paylasir; yalniz
      // zarfin tasinma bicimi farklidir.
      final privateGroupV3 =
          stored.encryption == 'flutter-file-v3-group' ||
          stored.encryption == 'flutter-file-v4-group' ||
          stored.encryption == groupWireVersion;
      var resolvedGroupId = signal.groupId;
      var groupEnvelope = envelope;
      if (privateGroupV3) {
        final routePlaintext = await _crypto.decryptDirect(
          senderId: directDecryptionPeer(
            envelope: envelope,
            authenticatedSenderId: signal.senderId,
            localRecipientId: signal.recipientId,
          ),
          envelope: envelope,
        );
        final route = await decodePrivateGroupRoute(routePlaintext);
        resolvedGroupId = route.groupId;
        groupEnvelope = route.groupEnvelope;
      } else if (privateGroupV2) {
        final routingToken = groupRoutingTokenFromEnvelope(envelope);
        final resolver = _groupRoutingResolver;
        resolvedGroupId = routingToken == null || resolver == null
            ? null
            : await resolver(routingToken);
        if (resolvedGroupId == null) {
          await partDirectory.delete(recursive: true);
          return null;
        }
      }
      final plaintext = resolvedGroupId == null
          ? await _crypto.decryptDirect(
              senderId: signal.senderId,
              envelope: envelope,
            )
          : await _crypto.decryptGroup(
              senderId: signal.senderId,
              groupId: resolvedGroupId,
              envelope: groupEnvelope,
            );
      final bytes = base64Decode(plaintext);
      if (bytes.length > transferChunkSize ||
          (signal.chunkIndex < signal.totalChunks - 1 &&
              bytes.length != transferChunkSize)) {
        await partDirectory.delete(recursive: true);
        return null;
      }
      final part = File('${partDirectory.path}/${signal.chunkIndex}.part');
      await part.writeAsBytes(bytes, flush: true);
      final completed = <File>[];
      var receivedBytes = 0;
      for (var index = 0; index < signal.totalChunks; index++) {
        final value = File('${partDirectory.path}/$index.part');
        if (await value.exists()) {
          completed.add(value);
          receivedBytes += await value.length();
        }
      }
      if (_disposed) return null;
      if (signal.chunkIndex == signal.totalChunks - 1 &&
          completed.length != signal.totalChunks &&
          const bool.fromEnvironment('SECURECHAT_LOCAL_DIAGNOSTICS')) {
        final present = completed
            .map((file) => file.uri.pathSegments.last)
            .toSet();
        final missing = <int>[];
        for (var index = 0; index < signal.totalChunks; index++) {
          if (!present.contains('$index.part')) missing.add(index);
        }
        _trace(
          'rx-incomplete parts=${completed.length} total=${signal.totalChunks} '
          'missing=${missing.take(8).join(',')}',
        );
      }
      if (completed.length % 32 == 0 ||
          completed.length == 1 ||
          completed.length == signal.totalChunks) {
        _trace(
          'rx-progress parts=${completed.length} total=${signal.totalChunks}',
        );
      }
      _progress.add(
        TransferProgress(
          transferId: transferId,
          chunksTransferred: completed.length,
          totalChunks: signal.totalChunks,
          bytesTransferred: receivedBytes,
          totalBytes: signal.fileSize,
          incoming: true,
        ),
      );
      if (completed.length != signal.totalChunks) return null;
      if (!privateWire && receivedBytes != signal.fileSize) {
        await partDirectory.delete(recursive: true);
        return null;
      }
      if (privateWire && receivedBytes > signal.fileSize) {
        await partDirectory.delete(recursive: true);
        return null;
      }
      String actualFileName = stored.fileName;
      String actualMimeType = stored.mimeType;
      String? caption;
      var actualIsViewOnce = stored.isViewOnce;
      var actualFileSize = signal.fileSize;
      String? actualOriginalMessageId = stored.originalMessageId;
      DateTime? actualAbsoluteExpiresAt = stored.absoluteExpiresAt;
      if (privateWire) {
        if (stored.caption == null) {
          await partDirectory.delete(recursive: true);
          return null;
        }
        final manifestEnvelope = _decodeEnvelopeField(
          stored.caption!,
          stored.encryption,
        );
        final String manifestPlaintext;
        if (privateGroupV3) {
          final route = await decodePrivateGroupRoute(
            await _crypto.decryptDirect(
              senderId: directDecryptionPeer(
                envelope: manifestEnvelope,
                authenticatedSenderId: signal.senderId,
                localRecipientId: signal.recipientId,
              ),
              envelope: manifestEnvelope,
            ),
          );
          if (route.groupId != resolvedGroupId) {
            await partDirectory.delete(recursive: true);
            return null;
          }
          manifestPlaintext = await _crypto.decryptGroup(
            senderId: signal.senderId,
            groupId: route.groupId,
            envelope: route.groupEnvelope,
          );
        } else {
          manifestPlaintext = resolvedGroupId == null
              ? await _crypto.decryptDirect(
                  senderId: signal.senderId,
                  envelope: manifestEnvelope,
                )
              : await _crypto.decryptGroup(
                  senderId: signal.senderId,
                  groupId: resolvedGroupId,
                  envelope: manifestEnvelope,
                );
        }
        final manifest = _PrivateFileManifest.fromJson(
          (jsonDecode(manifestPlaintext) as Map).cast<String, Object?>(),
        );
        actualFileName = manifest.fileName;
        actualMimeType = manifest.mimeType;
        actualFileSize = manifest.fileSize;
        if (actualFileSize > maximumFileSize ||
            actualFileSize != receivedBytes) {
          await partDirectory.delete(recursive: true);
          return null;
        }
        caption = manifest.caption;
        actualIsViewOnce = manifest.isViewOnce;
        actualOriginalMessageId = manifest.originalMessageId;
        actualAbsoluteExpiresAt = manifest.absoluteExpiresAt;
      } else if (stored.caption != null) {
        final captionEnvelope = _decodeEnvelopeField(
          stored.caption!,
          stored.encryption,
        );
        caption = resolvedGroupId == null
            ? await _crypto.decryptDirect(
                senderId: signal.senderId,
                envelope: captionEnvelope,
              )
            : await _crypto.decryptGroup(
                senderId: signal.senderId,
                groupId: resolvedGroupId,
                envelope: captionEnvelope,
              );
      }
      final receivedDirectory = Directory(
        '${_filesDirectory.path}/received_files',
      );
      await receivedDirectory.create(recursive: true);
      final output = File(
        '${receivedDirectory.path}/'
        '${DateTime.now().millisecondsSinceEpoch}_$actualFileName',
      );
      final sink = output.openWrite(mode: FileMode.writeOnly);
      try {
        for (final part in completed) {
          await sink.addStream(part.openRead());
        }
      } finally {
        await sink.close();
      }
      await partDirectory.delete(recursive: true);
      final received = ReceivedFile(
        transferId: transferId,
        file: output,
        fileName: actualFileName,
        mimeType: actualMimeType,
        senderId: signal.senderId,
        fileSize: actualFileSize,
        caption: caption,
        isViewOnce: actualIsViewOnce,
        originalMessageId: actualOriginalMessageId,
        absoluteExpiresAt: actualAbsoluteExpiresAt,
        groupId: resolvedGroupId,
      );
      if (_disposed) return received;
      _trace(
        'rx-complete bytes=$actualFileSize group=${resolvedGroupId != null}',
      );
      _receivedFiles.add(received);
      _progress.add(null);
      return received;
    } catch (error, stackTrace) {
      _endReceivingActivity(transferId);
      await _reportFailure('file-transfer.receive', error, stackTrace);
      if (await partDirectory.exists())
        await partDirectory.delete(recursive: true);
      if (!_progress.isClosed) _progress.add(null);
      return null;
    } finally {
      // Completed, invalid or rejected transfers delete their part directory.
      // Partial transfers retain activity across the gaps between chunks.
      if (!await partDirectory.exists()) _endReceivingActivity(transferId);
    }
  }

  Future<void> _reportFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    _trace('failure operation=$operation type=${error.runtimeType}');
    try {
      // The injected reporter records type/context, not payloads or keys.
      await _onAsyncFailure?.call(operation, error, stackTrace);
    } catch (_) {
      // A diagnostics failure must not interrupt transfer cleanup.
    }
  }

  static void _trace(String event) {
    if (const bool.fromEnvironment('SECURECHAT_LOCAL_DIAGNOSTICS')) {
      // Local opt-in QA only: no filenames, peer IDs, keys or payloads.
      debugPrint('SC-FILE $event');
    }
  }

  Future<int> cleanupStaleTransfers({DateTime? now}) async {
    final root = Directory('${_filesDirectory.path}/incoming_parts');
    if (!await root.exists()) return 0;
    final threshold = (now ?? DateTime.now()).subtract(staleTransferAge);
    var removed = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(threshold)) {
        await entity.delete(recursive: true);
        removed++;
      }
    }
    return removed;
  }

  Future<bool> _sendWithRetry(FileTransferSignal signal) async {
    // A successful socket write is not a successful server decode. Never
    // emit a frame known to be rejected by both server and recipient.
    if (utf8.encode(signal.encode()).length > SignalMessage.maxEncodedBytes) {
      return false;
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await _signaling.ensureConnected(timeout: const Duration(seconds: 3));
      }
      if (await _signaling.send(signal)) return true;
    }
    return false;
  }

  static String sanitizeFileName(String value) {
    final base = value.split(RegExp(r'[/\\]')).last;
    final safe = base
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_')
        .replaceAll('..', '_');
    final shortened = safe.length > 100 ? safe.substring(0, 100) : safe;
    return shortened.isEmpty ? 'dosya' : shortened;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
      '${_random.nextInt(0x7fffffff).toRadixString(16)}';

  static String _legacyTransferId(FileTransferSignal signal) => base64Url
      .encode(
        utf8.encode(
          '${signal.senderId}:${signal.timestamp}:${signal.fileName}',
        ),
      )
      .replaceAll('=', '');

  static String _mimeFromName(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return const {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
          'heic': 'image/heic',
          'mp4': 'video/mp4',
          'mov': 'video/quicktime',
          'mp3': 'audio/mpeg',
          'm4a': 'audio/mp4',
          'pdf': 'application/pdf',
          'zip': 'application/zip',
          'txt': 'text/plain',
        }[extension] ??
        'application/octet-stream';
  }

  static String _normalizeMimeType(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.length <= 127 &&
            RegExp(
              r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
            ).hasMatch(normalized)
        ? normalized
        : 'application/octet-stream';
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _disposed = true;
    for (final timer in _receivingActivity.values) {
      timer.cancel();
    }
    _receivingActivity.clear();
    _publishActivity();
    final operation = _dispose();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _dispose() async {
    await _subscription.cancel();
    await _operations.close();
    while (_receiveTails.isNotEmpty) {
      await Future.wait(_receiveTails.values.toList(growable: false));
    }
    await _progress.close();
    await _receivedFiles.close();
    await _activity.close();
  }
}

LocalAeadCryptoService _requireMetadataCrypto(
  CryptoService wireCrypto,
  LocalAeadCryptoService? explicit,
) {
  if (explicit != null) return explicit;
  if (wireCrypto case final LocalAeadCryptoService local) return local;
  throw ArgumentError(
    'metadataCrypto is required when peer crypto is not local storage AEAD',
  );
}

class _ChunkReader {
  _ChunkReader(Stream<List<int>> source, this.chunkSize)
    : _source = StreamIterator(source);

  final int chunkSize;
  final StreamIterator<List<int>> _source;
  List<int> _current = const [];
  int _offset = 0;
  bool _done = false;

  Future<List<int>> nextChunk() async {
    final bytes = Uint8List(chunkSize);
    var written = 0;
    // StreamIterator pauses the source between reads, so a slow network
    // cannot turn a large file into an unbounded in-memory integer list.
    while (written < chunkSize) {
      if (_offset == _current.length) {
        _current = const [];
        _offset = 0;
        if (_done || !await _source.moveNext()) {
          _done = true;
          break;
        }
        _current = _source.current;
      }
      final count = min(chunkSize - written, _current.length - _offset);
      bytes.setRange(written, written + count, _current, _offset);
      written += count;
      _offset += count;
    }
    return written == bytes.length
        ? bytes
        : Uint8List.sublistView(bytes, 0, written);
  }

  Future<void> close() => _source.cancel();
}

class _TransferMetadata {
  const _TransferMetadata({
    required this.senderId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.totalChunks,
    required this.groupId,
    required this.caption,
    required this.isViewOnce,
    required this.originalMessageId,
    required this.absoluteExpiresAt,
    required this.encryption,
  });
  final String senderId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final int totalChunks;
  final String? groupId;
  final String? caption;
  final bool isViewOnce;
  final String? originalMessageId;
  final DateTime? absoluteExpiresAt;

  /// Transfer basinda sabitlenen tel formati surumu. Parcalar arasinda
  /// degisemez; caption zarfi ilk parcanin surumuyle cozulur.
  final String? encryption;

  factory _TransferMetadata.fromSignal(FileTransferSignal signal) =>
      _TransferMetadata(
        senderId: signal.senderId,
        fileName: FileTransferManager.sanitizeFileName(signal.fileName),
        mimeType: signal.mimeType,
        fileSize: signal.fileSize,
        totalChunks: signal.totalChunks,
        groupId: signal.groupId,
        caption: signal.caption,
        isViewOnce: signal.isViewOnce,
        originalMessageId: signal.originalMessageId,
        absoluteExpiresAt: signal.absoluteExpiresAt,
        encryption: signal.encryption,
      );

  factory _TransferMetadata.fromJson(Map<String, Object?> json) =>
      _TransferMetadata(
        senderId: json['senderId'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? '',
        fileSize: (json['fileSize'] as num?)?.toInt() ?? -1,
        totalChunks: (json['totalChunks'] as num?)?.toInt() ?? -1,
        groupId: json['groupId'] as String?,
        caption: json['caption'] as String?,
        isViewOnce: json['isViewOnce'] as bool? ?? false,
        originalMessageId: json['originalMessageId'] as String?,
        absoluteExpiresAt: json['absoluteExpiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['absoluteExpiresAt'] as num).toInt(),
              ),
        encryption: json['encryption'] as String?,
      );

  _TransferMetadata mergeSignal(FileTransferSignal signal) => _TransferMetadata(
    senderId: senderId,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: fileSize,
    totalChunks: totalChunks,
    groupId: groupId,
    caption: signal.caption ?? caption,
    isViewOnce: isViewOnce || signal.isViewOnce,
    originalMessageId: signal.originalMessageId ?? originalMessageId,
    absoluteExpiresAt: signal.absoluteExpiresAt ?? absoluteExpiresAt,
    encryption: encryption,
  );

  bool matches(_TransferMetadata other) =>
      senderId == other.senderId &&
      fileName == other.fileName &&
      mimeType == other.mimeType &&
      fileSize == other.fileSize &&
      totalChunks == other.totalChunks &&
      groupId == other.groupId &&
      encryption == other.encryption;

  Map<String, Object?> toJson() => {
    'senderId': senderId,
    'fileName': fileName,
    'mimeType': mimeType,
    'fileSize': fileSize,
    'totalChunks': totalChunks,
    'groupId': groupId,
    'caption': caption,
    'isViewOnce': isViewOnce,
    'originalMessageId': originalMessageId,
    'absoluteExpiresAt': absoluteExpiresAt?.millisecondsSinceEpoch,
    'encryption': encryption,
  };
}

class _PrivateFileManifest {
  const _PrivateFileManifest({
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.caption,
    required this.isViewOnce,
    required this.originalMessageId,
    required this.absoluteExpiresAt,
  });

  static const version = 2;
  static const maximumCaptionLength = 4096;
  static const maximumMessageIdLength = 256;

  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? caption;
  final bool isViewOnce;
  final String? originalMessageId;
  final DateTime? absoluteExpiresAt;

  factory _PrivateFileManifest.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != version) {
      throw const FormatException('Unsupported private file manifest');
    }
    final rawName = json['name'];
    final rawMime = json['mime'];
    final rawSize = json['size'];
    final rawCaption = json['caption'];
    final rawMessageId = json['messageId'];
    if (rawName is! String ||
        rawMime is! String ||
        rawSize is! num ||
        rawSize.toInt() < 0) {
      throw const FormatException('Private file metadata is incomplete');
    }
    if (rawCaption != null &&
        (rawCaption is! String || rawCaption.length > maximumCaptionLength)) {
      throw const FormatException('Invalid private file caption');
    }
    if (rawMessageId != null &&
        (rawMessageId is! String ||
            rawMessageId.isEmpty ||
            rawMessageId.length > maximumMessageIdLength)) {
      throw const FormatException('Invalid private message reference');
    }
    final expiresAt = json['expiresAt'];
    if (expiresAt != null && expiresAt is! num) {
      throw const FormatException('Invalid private expiry timestamp');
    }
    final expiresAtMillis = expiresAt is num ? expiresAt.toInt() : null;
    return _PrivateFileManifest(
      fileName: FileTransferManager.sanitizeFileName(rawName),
      mimeType: FileTransferManager._normalizeMimeType(rawMime),
      fileSize: rawSize.toInt(),
      caption: rawCaption as String?,
      isViewOnce: json['viewOnce'] as bool? ?? false,
      originalMessageId: rawMessageId as String?,
      absoluteExpiresAt: expiresAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
    );
  }

  Map<String, Object?> toJson() {
    if (caption != null && caption!.length > maximumCaptionLength) {
      throw ArgumentError.value(caption, 'caption', 'Caption is too long');
    }
    if (originalMessageId != null &&
        (originalMessageId!.isEmpty ||
            originalMessageId!.length > maximumMessageIdLength)) {
      throw ArgumentError.value(
        originalMessageId,
        'originalMessageId',
        'Message reference is invalid',
      );
    }
    return {
      'v': version,
      'name': fileName,
      'mime': mimeType,
      'size': fileSize,
      if (caption != null) 'caption': caption,
      'viewOnce': isViewOnce,
      if (originalMessageId != null) 'messageId': originalMessageId,
      if (absoluteExpiresAt != null)
        'expiresAt': absoluteExpiresAt!.millisecondsSinceEpoch,
    };
  }
}
