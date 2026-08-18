import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';

import '../core/signal_message.dart';
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
    this.maximumFileSize = 1024 * 1024 * 1024,
    this.staleTransferAge = const Duration(minutes: 10),
    GroupRoutingResolver? groupRoutingResolver,
    LocalAeadCryptoService? metadataCrypto,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : _signaling = signaling,
       _crypto = crypto,
       _filesDirectory = filesDirectory,
       _groupRoutingResolver = groupRoutingResolver,
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
  final LocalAeadCryptoService _metadataCrypto;
  final int chunkSize;
  final int maximumFileSize;
  final Duration staleTransferAge;
  final AsyncOperationTracker _operations;
  final _progress = StreamController<TransferProgress?>.broadcast();
  // A completed receive is published synchronously so downstream owners can
  // register persistence work before receiveChunk completes. The persistence
  // itself remains async and is drained by MediaMessageService.waitForIdle.
  final _receivedFiles = StreamController<ReceivedFile>.broadcast(sync: true);
  final Map<String, Future<void>> _receiveTails = {};
  final _random = Random.secure();
  late final StreamSubscription<FileTransferSignal> _subscription;
  Future<void>? _disposeTask;
  bool _disposed = false;

  Stream<TransferProgress?> get progress => _progress.stream;
  Stream<ReceivedFile> get receivedFiles => _receivedFiles.stream;

  void _receiveFromSocket(FileTransferSignal signal) {
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
      fileName: file.uri.pathSegments.last,
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
    final totalChunks = max(1, (fileSize + chunkSize - 1) ~/ chunkSize);
    final reader = _ChunkReader(stream, chunkSize);
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
    try {
      for (var index = 0; index < totalChunks; index++) {
        final bytes = await reader.nextChunk();
        if (index < totalChunks - 1 && bytes.length != chunkSize) {
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
            fileSize: totalChunks * chunkSize,
            data: base64Encode(utf8.encode(routedEnvelope)),
            transferId: transferId,
            chunkIndex: index,
            totalChunks: totalChunks,
            caption: routedManifest == null
                ? null
                : base64Encode(utf8.encode(routedManifest)),
            encryption: isGroup
                ? 'flutter-file-v3-group'
                : 'flutter-file-v2-direct',
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
    } catch (error) {
      return FileTransferFailure('Sifreli dosya aktarimi basarisiz: $error');
    } finally {
      await reader.close();
      _progress.add(null);
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
        .then((_) => _receiveChunkSerial(signal, transferId));
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
        signal.encryption?.startsWith('flutter-file-v3-') == true;
    final maximumWireSize = privateWire
        ? maximumFileSize + chunkSize - 1
        : maximumFileSize;
    if (signal.fileSize < 0 || signal.fileSize > maximumWireSize) return null;
    if (signal.totalChunks < 1 ||
        signal.chunkIndex < 0 ||
        signal.chunkIndex >= signal.totalChunks) {
      return null;
    }
    if (privateWire && signal.fileSize != signal.totalChunks * chunkSize) {
      return null;
    }
    final partDirectory = Directory(
      '${_filesDirectory.path}/incoming_parts/$transferId',
    );
    final metadata = File('${partDirectory.path}/metadata.secure');
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
      final envelope = utf8.decode(base64Decode(signal.data));
      final privateGroupV2 = signal.encryption == 'flutter-file-v2-group';
      final privateGroupV3 = signal.encryption == 'flutter-file-v3-group';
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
      if (bytes.length > chunkSize ||
          (signal.chunkIndex < signal.totalChunks - 1 &&
              bytes.length != chunkSize)) {
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
        final manifestEnvelope = utf8.decode(base64Decode(stored.caption!));
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
        final captionEnvelope = utf8.decode(base64Decode(stored.caption!));
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
      _receivedFiles.add(received);
      _progress.add(null);
      return received;
    } catch (_) {
      if (await partDirectory.exists())
        await partDirectory.delete(recursive: true);
      if (!_progress.isClosed) _progress.add(null);
      return null;
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
  _ChunkReader(Stream<List<int>> source, this.chunkSize) {
    _subscription = source.listen(
      (data) {
        _pending.addAll(data);
        _drain();
      },
      onError: (Object error, StackTrace stack) {
        _error = AsyncError(error, stack);
        _done = true;
        _drain();
      },
      onDone: () {
        _done = true;
        _drain();
      },
    );
  }

  final int chunkSize;
  final List<int> _pending = [];
  final List<Completer<List<int>>> _waiters = [];
  late final StreamSubscription<List<int>> _subscription;
  AsyncError? _error;
  bool _done = false;

  Future<List<int>> nextChunk() {
    final completer = Completer<List<int>>();
    _waiters.add(completer);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_waiters.isNotEmpty && (_pending.length >= chunkSize || _done)) {
      final waiter = _waiters.removeAt(0);
      final error = _error;
      if (error != null) {
        waiter.completeError(error.error, error.stackTrace);
        continue;
      }
      final take = min(chunkSize, _pending.length);
      waiter.complete(_pending.sublist(0, take));
      _pending.removeRange(0, take);
    }
  }

  Future<void> close() => _subscription.cancel();
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
  );

  bool matches(_TransferMetadata other) =>
      senderId == other.senderId &&
      fileName == other.fileName &&
      mimeType == other.mimeType &&
      fileSize == other.fileSize &&
      totalChunks == other.totalChunks &&
      groupId == other.groupId;

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
