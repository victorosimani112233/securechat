import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CrashMetadata {
  const CrashMetadata({
    required this.versionName,
    required this.versionCode,
    required this.operatingSystem,
    required this.osVersion,
    required this.deviceModel,
    required this.manufacturer,
  });

  final String versionName;
  final String versionCode;
  final String operatingSystem;
  final String osVersion;
  final String deviceModel;
  final String manufacturer;

  factory CrashMetadata.fromJson(Map<Object?, Object?> json) => CrashMetadata(
    versionName: json['versionName']?.toString() ?? 'unknown',
    versionCode: json['versionCode']?.toString() ?? 'unknown',
    operatingSystem:
        json['operatingSystem']?.toString() ?? Platform.operatingSystem,
    osVersion: json['osVersion']?.toString() ?? 'unknown',
    deviceModel: json['deviceModel']?.toString() ?? 'unknown',
    manufacturer: json['manufacturer']?.toString() ?? 'unknown',
  );

  Map<String, String> toJson() => {
    'versionName': versionName,
    'versionCode': versionCode,
    'operatingSystem': operatingSystem,
    'osVersion': osVersion,
    'deviceModel': deviceModel,
    'manufacturer': manufacturer,
  };
}

abstract interface class DiagnosticsPlatformGateway {
  Future<CrashMetadata> metadata();
  Future<bool> share(File file);
}

class MethodChannelDiagnosticsPlatformGateway
    implements DiagnosticsPlatformGateway {
  const MethodChannelDiagnosticsPlatformGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.securechat/native');

  final MethodChannel _channel;

  @override
  Future<CrashMetadata> metadata() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getDiagnosticsMetadata',
    );
    return CrashMetadata.fromJson(raw ?? const {});
  }

  @override
  Future<bool> share(File file) async {
    await _channel.invokeMethod<void>('shareLocalFile', {
      'path': file.absolute.path,
      'mimeType': 'application/json',
    });
    return true;
  }
}

abstract interface class CrashReporter {
  Future<File?> recordException(
    Object error,
    StackTrace stackTrace, {
    String? context,
    Map<String, Object?> metadata,
    bool fatal,
  });
  void log(String event, {Map<String, Object?> metadata});
  void setCustomKey(String key, Object value);
  void setUserId(String? userId);
}

class PrivacyCrashReporter implements CrashReporter {
  PrivacyCrashReporter._({
    required Directory directory,
    required DiagnosticsPlatformGateway platform,
    required CrashMetadata metadata,
    this.maximumFiles = 20,
  }) : _directory = directory,
       _platform = platform,
       _metadata = metadata;

  static const _allowedMetadataKeys = {
    'component',
    'operation',
    'state',
    'httpStatus',
    'retryCount',
    'platform',
  };

  final Directory _directory;
  final DiagnosticsPlatformGateway _platform;
  final CrashMetadata _metadata;
  final int maximumFiles;
  final Map<String, Object> _customKeys = {};
  String? _userHash;

  static Future<PrivacyCrashReporter> open({
    required Directory directory,
    DiagnosticsPlatformGateway? platform,
    int maximumFiles = 20,
  }) async {
    final gateway = platform ?? const MethodChannelDiagnosticsPlatformGateway();
    await directory.create(recursive: true);
    CrashMetadata metadata;
    try {
      metadata = await gateway.metadata();
    } catch (_) {
      metadata = CrashMetadata(
        versionName: 'unknown',
        versionCode: 'unknown',
        operatingSystem: Platform.operatingSystem,
        osVersion: 'unknown',
        deviceModel: 'unknown',
        manufacturer: 'unknown',
      );
    }
    return PrivacyCrashReporter._(
      directory: directory,
      platform: gateway,
      metadata: metadata,
      maximumFiles: maximumFiles,
    );
  }

  void installGlobalHandlers() {
    FlutterError.onError = (details) {
      unawaited(
        _recordGlobalException(
          details.exception,
          details.stack ?? StackTrace.current,
          context: 'flutter-framework',
        ),
      );
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        _recordGlobalException(
          error,
          stack,
          context: 'platform-dispatcher',
          fatal: true,
        ),
      );
      return false;
    };
  }

  Future<void> _recordGlobalException(
    Object error,
    StackTrace stackTrace, {
    required String context,
    bool fatal = false,
  }) async {
    try {
      await recordException(error, stackTrace, context: context, fatal: fatal);
    } catch (_) {
      // A crash reporter must never create a second uncaught async failure.
    }
  }

  @override
  Future<File?> recordException(
    Object error,
    StackTrace stackTrace, {
    String? context,
    Map<String, Object?> metadata = const {},
    bool fatal = false,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final payload = <String, Object?>{
        'format': 'elcim-crash-v1',
        'timestamp': now.toIso8601String(),
        'fatal': fatal,
        'errorType': error.runtimeType.toString(),
        'context': _safeValue(context),
        'app': _metadata.toJson(),
        'userHash': _userHash,
        'custom': Map<String, Object>.from(_customKeys),
        'metadata': _safeMetadata(metadata),
        'stack': _redactStack(stackTrace.toString()),
      };
      final stamp = now.microsecondsSinceEpoch;
      final target = File('${_directory.path}/crash_$stamp.json');
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(jsonEncode(payload), flush: true);
      await temporary.rename(target.path);
      await _trim();
      return target;
    } catch (_) {
      return null;
    }
  }

  @override
  void log(String event, {Map<String, Object?> metadata = const {}}) {
    if (kDebugMode) {
      debugPrint(
        'Diagnostics event=${_safeValue(event)} meta=${_safeMetadata(metadata)}',
      );
    }
  }

  @override
  void setCustomKey(String key, Object value) {
    if (!_allowedMetadataKeys.contains(key)) return;
    final safe = _safeObject(value);
    if (safe != null) _customKeys[key] = safe;
  }

  @override
  void setUserId(String? userId) {
    final clean = userId?.trim();
    _userHash = clean == null || clean.isEmpty
        ? null
        : sha256.convert(utf8.encode(clean)).toString();
  }

  Future<List<File>> listReports() async {
    if (!await _directory.exists()) return const [];
    final files = await _directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'/crash_\d+\.json$').hasMatch(entry.path),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<bool> shareLatest() async {
    final reports = await listReports();
    if (reports.isEmpty) return false;
    try {
      return await _platform.share(reports.first);
    } catch (_) {
      return false;
    }
  }

  Future<int> clearAll() async {
    final reports = await listReports();
    var removed = 0;
    for (final report in reports) {
      try {
        await report.delete();
        removed++;
      } on FileSystemException {}
    }
    return removed;
  }

  Future<void> _trim() async {
    final reports = await listReports();
    for (final stale in reports.skip(maximumFiles)) {
      try {
        await stale.delete();
      } on FileSystemException {}
    }
  }

  Map<String, Object> _safeMetadata(Map<String, Object?> values) {
    final output = <String, Object>{};
    for (final entry in values.entries) {
      if (!_allowedMetadataKeys.contains(entry.key)) continue;
      final safe = _safeObject(entry.value);
      if (safe != null) output[entry.key] = safe;
    }
    return output;
  }

  Object? _safeObject(Object? value) {
    if (value is bool || value is num) return value;
    if (value is String) return _safeValue(value);
    return null;
  }

  String? _safeValue(String? value) {
    if (value == null) return null;
    var safe = value.trim();
    if (safe.isEmpty) return null;
    safe = safe
        .replaceAll(RegExp(r'bearer\s+\S+', caseSensitive: false), '[REDACTED]')
        .replaceAll(RegExp(r'https?://\S+'), '[REDACTED_URL]')
        .replaceAll(
          RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'),
          '[REDACTED_EMAIL]',
        )
        .replaceAll(RegExp(r'\+?\d[\d ()-]{7,}\d'), '[REDACTED_PHONE]')
        .replaceAll(RegExp(r'[A-Za-z0-9+/=_-]{32,}'), '[REDACTED_SECRET]');
    return safe.length <= 96 ? safe : safe.substring(0, 96);
  }

  String _redactStack(String stack) => stack
      .split('\n')
      .where(
        (line) =>
            line.trimLeft().startsWith('#') ||
            line.contains('<asynchronous suspension>'),
      )
      .take(80)
      .map(
        (line) => line.replaceAll(
          RegExp(r'file:///[^\s)]+/([^/\s)]+\.dart)'),
          'file:///[REDACTED]/\$1',
        ),
      )
      .join('\n');
}
