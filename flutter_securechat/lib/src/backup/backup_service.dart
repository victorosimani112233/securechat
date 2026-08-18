import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../services/session_store.dart';
import '../storage/secure_chat_database.dart';
import 'backup_crypto.dart';

sealed class BackupRestoreResult {
  const BackupRestoreResult();
}

class BackupRestoreSuccess extends BackupRestoreResult {
  const BackupRestoreSuccess();
}

class BackupWrongPassword extends BackupRestoreResult {
  const BackupWrongPassword(this.remainingAttempts);
  final int remainingAttempts;
}

class BackupAttemptsExhausted extends BackupRestoreResult {
  const BackupAttemptsExhausted({required this.deleted});
  final bool deleted;
}

class BackupRestoreFailure extends BackupRestoreResult {
  const BackupRestoreFailure(this.message);
  final String message;
}

class BackupService {
  BackupService({
    required SecureChatDatabase database,
    required SessionStore session,
    required Directory backupDirectory,
    BackupCrypto? crypto,
  }) : _database = database,
       _session = session,
       _backupDirectory = backupDirectory,
       _crypto = crypto ?? BackupCrypto();

  static const currentVersion = 2;
  static const maximumAttempts = 5;
  static const extension = 'elbk';

  final SecureChatDatabase _database;
  final SessionStore _session;
  final Directory _backupDirectory;
  final BackupCrypto _crypto;

  Future<File> createBackup(String password) async {
    _validatePassword(password);
    final root = <String, Object?>{
      'version': currentVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'profile': <String, Object?>{
        'userId': _session.userId ?? '',
        'displayName': _session.displayName ?? '',
        'phoneNumber': _session.phoneNumber ?? '',
        'profilePhotoUri': _session.profilePhotoUri ?? '',
      },
      // Tokens are deliberately excluded. A restored device must obtain a new
      // access/refresh pair from the authentication service.
      'database': jsonDecode(await _database.exportPortableJson()),
    };
    final compressed = gzip.encode(utf8.encode(jsonEncode(root)));
    final encrypted = await _crypto.encrypt(compressed, password);
    await _backupDirectory.create(recursive: true);
    final now = DateTime.now();
    final name =
        'elcim_backup_${_four(now.year)}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.$extension';
    final file = File('${_backupDirectory.path}/$name');
    await file.writeAsBytes(encrypted, flush: true);
    return file;
  }

  Future<List<File>> localBackups() async {
    if (!await _backupDirectory.exists()) return const [];
    final files = await _backupDirectory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.$extension'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<BackupRestoreResult> restoreBackup(File file, String password) async {
    Uint8List encrypted;
    try {
      encrypted = await file.readAsBytes();
    } on FileSystemException catch (error) {
      return BackupRestoreFailure('Dosya okunamadı: ${error.message}');
    }
    final fingerprint = await _fingerprint(encrypted);
    final attemptKey = 'backup_attempt:$fingerprint';
    final attempts =
        int.tryParse(await _database.cryptoState.get(attemptKey) ?? '0') ?? 0;
    if (attempts >= maximumAttempts) {
      return BackupAttemptsExhausted(deleted: await _delete(file));
    }

    final clear = await _crypto.decrypt(encrypted, password);
    if (clear == null) {
      final next = attempts + 1;
      await _database.cryptoState.put(attemptKey, '$next');
      if (next >= maximumAttempts) {
        await _database.cryptoState.delete(attemptKey);
        return BackupAttemptsExhausted(deleted: await _delete(file));
      }
      return BackupWrongPassword(maximumAttempts - next);
    }

    try {
      final decompressed = gzip.decode(clear);
      final decoded = jsonDecode(utf8.decode(decompressed));
      if (decoded is! Map) throw const FormatException('Invalid backup root');
      final root = decoded.cast<String, Object?>();
      final version = (root['version'] as num?)?.toInt() ?? 1;
      if (version < 1 || version > currentVersion) {
        throw FormatException('Desteklenmeyen yedek sürümü: $version');
      }
      final profile = (root['profile'] as Map?)?.cast<String, Object?>();
      if (profile == null) throw const FormatException('Profile is missing');
      final backupPhone = profile['phoneNumber'] as String? ?? '';
      final currentPhone = _session.phoneNumber;
      if (currentPhone != null &&
          currentPhone.isNotEmpty &&
          currentPhone != backupPhone) {
        return const BackupRestoreFailure(
          'Yedek farklı bir hesaba ait (telefon numarası eşleşmiyor)',
        );
      }

      final databaseJson = version == 1
          ? _upgradeKotlinV1(root)
          : root['database'];
      if (databaseJson is! Map) {
        throw const FormatException('Database snapshot is missing');
      }
      // Both database and profile are parsed/validated before the database is
      // atomically replaced. No row-by-row partial restore is possible.
      await _database.replaceFromPortableJson(jsonEncode(databaseJson));
      await _session.restoreProfileAndPersist(
        userId: profile['userId'] as String? ?? '',
        displayName: profile['displayName'] as String? ?? '',
        phoneNumber: backupPhone,
        profilePhotoUri: _nonEmpty(profile['profilePhotoUri'] as String?),
      );
      await _database.cryptoState.delete(attemptKey);
      return const BackupRestoreSuccess();
    } on FormatException catch (error) {
      return BackupRestoreFailure('Yedek dosyası bozuk: ${error.message}');
    } on FileSystemException catch (error) {
      return BackupRestoreFailure('Yedek uygulanamadı: ${error.message}');
    } catch (error) {
      return BackupRestoreFailure('Yedek uygulanamadı: $error');
    }
  }

  Future<int> remainingAttempts(File file) async {
    final fingerprint = await _fingerprint(await file.readAsBytes());
    final attempts =
        int.tryParse(
          await _database.cryptoState.get('backup_attempt:$fingerprint') ?? '0',
        ) ??
        0;
    return (maximumAttempts - attempts).clamp(0, maximumAttempts);
  }

  static Map<String, Object?> _upgradeKotlinV1(Map<String, Object?> root) =>
      <String, Object?>{
        'schema': 1,
        'conversations': root['conversations'] ?? const [],
        'messages': root['messages'] ?? const [],
        'contacts': root['contacts'] ?? const [],
        'callLogs': const [],
        'scheduledMessages': const [],
        'exportLogs': const [],
        'pendingTimerUpdates': const [],
        'identities': const [],
        'preKeys': const [],
        'signedPreKeys': const [],
        'sessions': const [],
        'senderKeys': const [],
        'cryptoState': const <String, String>{},
        'pendingSignals': const [],
      };

  static void _validatePassword(String password) {
    if (password.length < 8) {
      throw const FormatException('Yedek parolası en az 8 karakter olmalı');
    }
  }

  static Future<String> _fingerprint(List<int> bytes) async =>
      base64UrlEncode((await Sha256().hash(bytes)).bytes);

  static Future<bool> _delete(File file) async {
    try {
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _four(int value) => value.toString().padLeft(4, '0');
}
