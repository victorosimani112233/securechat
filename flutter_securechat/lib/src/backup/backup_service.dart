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

  static const currentVersion = 3;
  static const maximumAttempts = 5;
  static const minimumPasswordLength = 8;
  static const extension = 'elbk';

  final SecureChatDatabase _database;
  final SessionStore _session;
  final Directory _backupDirectory;
  final BackupCrypto _crypto;

  Future<File> createBackup(String password) async {
    _validatePassword(password);
    final profile = _BackupProfile.parse(<String, Object?>{
      'userId': _session.userId,
      'displayName': _session.displayName ?? '',
      'phoneNumber': _session.phoneNumber ?? '',
      'profilePhotoUri': _session.profilePhotoUri,
    });
    final database = await _database.exportPortableJson();
    if (_session.userId != profile.userId) {
      throw const FormatException('Account changed during backup');
    }
    final root = <String, Object?>{
      'version': currentVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'profile': <String, Object?>{
        'userId': profile.userId,
        'displayName': profile.displayName,
        'phoneNumber': profile.phoneNumber,
        'profilePhotoUri': profile.photoUri ?? '',
      },
      // Tokens are deliberately excluded. A restored device must obtain a new
      // access/refresh pair from the authentication service.
      'database': _historyOnly(
        (jsonDecode(database) as Map).cast<String, Object?>(),
      ),
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
      final version = root['version'] ?? 1;
      if (version is! int || version < 1 || version > currentVersion) {
        throw FormatException('Desteklenmeyen yedek sürümü: $version');
      }
      final profile = _BackupProfile.parse(root['profile']);
      _validateRestoreAccount(profile.userId);
      final initialUserId = _session.userId;
      final wasLoggedIn = _session.isLoggedIn;

      void validateAccount() {
        _validateRestoreAccount(profile.userId);
        if (_session.userId != initialUserId ||
            _session.isLoggedIn != wasLoggedIn) {
          throw const FormatException('Account changed during restore');
        }
      }

      final databaseJson = version == 1
          ? _upgradeKotlinV1(root)
          : root['database'];
      if (databaseJson is! Map) {
        throw const FormatException('Database snapshot is missing');
      }
      final sanitizedDatabase = _historyOnly(
        databaseJson.cast<String, Object?>(),
      );
      // The database preserves local protocol state at commit time, not from
      // an exported snapshot that could race a queued Signal write.
      await _database.replaceFromPortableJson(
        jsonEncode(sanitizedDatabase),
        preserveLocalSecurityState: true,
        validateBeforeCommit: validateAccount,
      );
      validateAccount();
      // Recovery credentials and the authenticated profile are authoritative.
      // Only an offline restore installs profile data from the backup.
      if (!wasLoggedIn) {
        await _session.restoreProfileAndPersist(
          userId: profile.userId,
          displayName: profile.displayName,
          phoneNumber: profile.phoneNumber,
          profilePhotoUri: _nonEmpty(profile.photoUri),
        );
      }
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

  void _validateRestoreAccount(String backupUserId) {
    final currentUserId = _session.userId;
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        currentUserId != backupUserId) {
      throw const FormatException('Backup account UUID does not match');
    }
    // A partial credential state must not be attached to an imported profile.
    if ((_session.accessToken?.isNotEmpty == true ||
            _session.refreshToken?.isNotEmpty == true) &&
        (!_session.isLoggedIn || currentUserId != backupUserId)) {
      throw const FormatException('Invalid local authentication state');
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

  // Explicit history allowlist: new local/secret collections must not become
  // portable by default. Never export/import the generic cryptoState map.
  static Map<String, Object?> _historyOnly(Map<String, Object?> source) {
    if (source['schema'] is! int || source['schema'] != 1) {
      throw const FormatException('Unsupported database schema');
    }
    final result = <String, Object?>{
      'schema': source['schema'],
      for (final key in const [
        'conversations',
        'messages',
        'contacts',
        'callLogs',
        'scheduledMessages',
        'scheduledMessageHistory',
        'exportLogs',
        'pendingTimerUpdates',
      ])
        key: source[key] ?? const <Object?>[],
    };
    for (final entry in result.entries) {
      if (entry.key == 'schema') continue;
      final rows = entry.value;
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('Invalid history collection: ${entry.key}');
      }
    }
    for (final key in const [
      'identities',
      'preKeys',
      'signedPreKeys',
      'sessions',
      'senderKeys',
      'pendingSignals',
    ]) {
      result[key] = const <Object?>[];
    }
    result['cryptoState'] = const <String, String>{};
    return result;
  }

  static void _validatePassword(String password) {
    if (password.length < minimumPasswordLength) {
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

class _BackupProfile {
  const _BackupProfile(
    this.userId,
    this.displayName,
    this.phoneNumber,
    this.photoUri,
  );

  final String userId;
  final String displayName;
  final String phoneNumber;
  final String? photoUri;

  static _BackupProfile parse(Object? value) {
    if (value is! Map) throw const FormatException('Profile is missing');
    final userId = value['userId'];
    if (userId is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(userId)) {
      throw const FormatException('Profile account UUID is invalid');
    }
    String field(String name) {
      final field = value[name];
      if (field == null) return '';
      if (field is! String) {
        throw FormatException('Profile $name is invalid');
      }
      return field;
    }

    return _BackupProfile(
      userId,
      field('displayName'),
      field('phoneNumber'),
      field('profilePhotoUri'),
    );
  }
}
