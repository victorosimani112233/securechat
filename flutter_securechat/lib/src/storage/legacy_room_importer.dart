import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'secure_chat_database.dart';

enum LegacyRoomImportResult { absent, alreadyCompleted, imported }

class LegacyRoomExport {
  const LegacyRoomExport({required this.json, required this.sourceSchema});

  final String json;
  final int sourceSchema;
}

abstract interface class LegacyRoomGateway {
  Future<LegacyRoomExport?> exportIfPresent();
  Future<void> archiveAfterImport();
}

class MethodChannelLegacyRoomGateway implements LegacyRoomGateway {
  const MethodChannelLegacyRoomGateway({MethodChannel? channel})
    : _injectedChannel = channel;

  static const _defaultChannel = MethodChannel('com.securechat/native');
  final MethodChannel? _injectedChannel;
  MethodChannel get _channel => _injectedChannel ?? _defaultChannel;

  @override
  Future<LegacyRoomExport?> exportIfPresent() async {
    if (!Platform.isAndroid) return null;
    final Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<Object?, Object?>(
        'exportLegacyRoomDatabase',
      );
    } on MissingPluginException {
      return null;
    }
    final status = result?['status']?.toString();
    if (status == 'absent' || status == 'completed') return null;
    if (status != 'ready') {
      throw StateError('Unexpected legacy Room export status: $status');
    }
    final path = result?['path']?.toString();
    final encodedKey = result?['transportKey']?.toString();
    final sourceSchema = (result?['sourceSchema'] as num?)?.toInt();
    if (path == null || encodedKey == null || sourceSchema == null) {
      throw const FormatException('Legacy Room export metadata is incomplete');
    }
    final envelope = await File(path).readAsBytes();
    final key = base64Decode(encodedKey);
    if (key.length != 32 || envelope.length < 29) {
      throw const FormatException('Legacy Room transport envelope is invalid');
    }
    final List<int> plaintext;
    try {
      plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(
          envelope.sublist(12, envelope.length - 16),
          nonce: envelope.sublist(0, 12),
          mac: Mac(envelope.sublist(envelope.length - 16)),
        ),
        secretKey: SecretKey(key),
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
    return LegacyRoomExport(
      json: utf8.decode(plaintext),
      sourceSchema: sourceSchema,
    );
  }

  @override
  Future<void> archiveAfterImport() async {
    if (!Platform.isAndroid) return;
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'archiveLegacyRoomDatabase',
    );
    final status = result?['status']?.toString();
    if (status != 'archived' && status != 'already_absent') {
      throw StateError('Legacy Room archive failed: $status');
    }
  }
}

class LegacyRoomImporter {
  const LegacyRoomImporter({required this.database, required this.gateway});

  final SecureChatDatabase database;
  final LegacyRoomGateway gateway;

  Future<LegacyRoomImportResult> run() async {
    if (await database.isLegacyRoomImportComplete()) {
      // A prior import may have committed just before the process died. The
      // native archive operation is repeatable, so finish cleanup now.
      await gateway.archiveAfterImport();
      return LegacyRoomImportResult.alreadyCompleted;
    }
    final export = await gateway.exportIfPresent();
    if (export == null) return LegacyRoomImportResult.absent;
    final portable = LegacyRoomSnapshotConverter.convert(
      export.json,
      expectedSchema: export.sourceSchema,
    );
    await database.importLegacyRoomPortableJson(portable);
    await gateway.archiveAfterImport();
    return LegacyRoomImportResult.imported;
  }
}

class LegacyRoomSnapshotConverter {
  const LegacyRoomSnapshotConverter._();

  static String convert(String rawJson, {required int expectedSchema}) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Legacy Room export is not an object');
    }
    final root = decoded.cast<String, Object?>();
    final schema = _integer(root, 'sourceSchema');
    if (schema != expectedSchema || schema < 1 || schema > 22) {
      throw FormatException('Unexpected legacy Room schema: $schema');
    }
    final tablesValue = root['tables'];
    if (tablesValue is! Map) {
      throw const FormatException('Legacy Room export has no tables object');
    }
    final tables = tablesValue.cast<String, Object?>();
    final snapshot = <String, Object?>{
      'schema': 1,
      'conversations': _rows(
        tables,
        'conversations',
      ).map(_conversation).toList(),
      'messages': _rows(tables, 'messages').map(_message).toList(),
      'contacts': _rows(tables, 'contacts').map(_contact).toList(),
      'callLogs': _rows(tables, 'call_log').map(_callLog).toList(),
      'scheduledMessages': _rows(
        tables,
        'scheduled_messages',
      ).map(_scheduledMessage).toList(),
      'exportLogs': _rows(tables, 'export_log').map(_exportLog).toList(),
      'pendingTimerUpdates': _rows(
        tables,
        'pending_timer_updates',
      ).map(_pendingTimer).toList(),
      'identities': _rows(tables, 'identities').map(_identity).toList(),
      'preKeys': _rows(tables, 'prekeys').map(_preKey).toList(),
      'signedPreKeys': _rows(
        tables,
        'signed_prekeys',
      ).map(_signedPreKey).toList(),
      'sessions': _rows(tables, 'sessions').map(_session).toList(),
      'senderKeys': _rows(tables, 'sender_keys').map(_senderKey).toList(),
      'cryptoState': _cryptoState(root['cryptoState']),
      'pendingSignals': const <Object?>[],
    };
    _verifyCounts(root['rowCounts'], tables);
    _verifyReferences(snapshot);
    return jsonEncode(snapshot);
  }

  static Map<String, Object?> _conversation(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'peerId': _string(r, 'peer_id'),
    'peerName': _string(r, 'peer_name'),
    'peerPhone': _string(r, 'peer_phone'),
    'lastMessage': _nullableString(r, 'last_message'),
    'lastMessageTimestamp': _nullableInteger(r, 'last_message_timestamp'),
    'unreadCount': _integer(r, 'unread_count', fallback: 0),
    'isMuted': _boolean(r, 'is_muted'),
    'isPinned': _boolean(r, 'is_pinned'),
    'isGroup': _boolean(r, 'is_group'),
    'groupMembers': _nullableString(r, 'group_members'),
    'contactNote': _nullableString(r, 'contact_note'),
    'customNotificationUri': _nullableString(r, 'custom_notification_uri'),
    'isArchived': _boolean(r, 'is_archived'),
    'disappearingDuration': _integer(r, 'disappearing_duration', fallback: 0),
    'groupAdmins': _nullableString(r, 'group_admins'),
    'isFavorite': _boolean(r, 'is_favorite'),
    'isLocked': _boolean(r, 'is_locked'),
    'isExportEnabled': _boolean(r, 'is_export_enabled'),
    'manuallyUnread': _boolean(r, 'manually_unread'),
    'isReadOnly': _boolean(r, 'is_read_only'),
  };

  static Map<String, Object?> _message(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'conversationId': _string(r, 'conversation_id'),
    'senderId': _string(r, 'sender_id'),
    'content': _string(r, 'content'),
    'contentType': _string(r, 'content_type'),
    'timestamp': _integer(r, 'timestamp'),
    'status': _string(r, 'status'),
    'replyToId': _nullableString(r, 'reply_to_id'),
    'isOutgoing': _boolean(r, 'is_outgoing'),
    'isStarred': _boolean(r, 'is_starred'),
    'expiresAt': _nullableInteger(r, 'expires_at'),
    'editedAt': _nullableInteger(r, 'edited_at'),
    'editHistory': _nullableString(r, 'edit_history'),
    'reactions': _nullableString(r, 'reactions'),
    'caption': _nullableString(r, 'caption'),
    'isViewOnce': _boolean(r, 'is_view_once'),
    'isViewed': _boolean(r, 'is_viewed'),
    'isPinned': _boolean(r, 'is_pinned'),
    'pinnedAt': _nullableInteger(r, 'pinned_at'),
  };

  static Map<String, Object?> _contact(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'phoneNumber': _string(r, 'phone_number'),
    'phoneHash': _string(r, 'phone_hash'),
    'displayName': _string(r, 'display_name'),
    'isRegistered': _boolean(r, 'is_registered'),
    'avatarUri': _nullableString(r, 'avatar_uri'),
    'lastSeen': _nullableInteger(r, 'last_seen'),
  };

  static Map<String, Object?> _callLog(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'peerId': _string(r, 'peer_id'),
    'peerName': _string(r, 'peer_name'),
    'callType': _string(r, 'call_type'),
    'direction': _string(r, 'direction'),
    'status': _string(r, 'status'),
    'timestamp': _integer(r, 'timestamp'),
    'duration': _integer(r, 'duration', fallback: 0),
  };

  static Map<String, Object?> _scheduledMessage(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'messageContent': _string(r, 'message_content'),
    'repeatType': _string(r, 'repeat_type'),
    'repeatDays': _nullableString(r, 'repeat_days'),
    'hour': _integer(r, 'hour'),
    'minute': _integer(r, 'minute'),
    'recipientIds': _string(r, 'recipient_ids'),
    'recipientNames': _string(r, 'recipient_names'),
    'isEnabled': _boolean(r, 'is_enabled', fallback: true),
    'nextTriggerTime': _integer(r, 'next_trigger_time'),
    'createdAt': _integer(r, 'created_at', fallback: 0),
  };

  static Map<String, Object?> _exportLog(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'groupId': _string(r, 'group_id'),
    'actorUserId': _string(r, 'actor_user_id'),
    'actorDisplayName': _string(r, 'actor_display_name'),
    'eventType': _string(r, 'event_type'),
    'timestamp': _integer(r, 'timestamp'),
    'messageCount': _integer(r, 'message_count'),
    'firstMsgTs': _nullableInteger(r, 'first_msg_ts'),
    'lastMsgTs': _nullableInteger(r, 'last_msg_ts'),
  };

  static Map<String, Object?> _pendingTimer(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'conversationId': _string(r, 'conversation_id'),
    'targetUserId': _string(r, 'target_user_id'),
    'duration': _integer(r, 'duration'),
    'createdAt': _integer(r, 'created_at', fallback: 0),
  };

  static Map<String, Object?> _identity(Map<String, Object?> r) => {
    'addressName': _string(r, 'addressName', alternate: 'address_name'),
    'identityKey': _blob(r, 'identity_key'),
    'trustLevel': _string(r, 'trust_level'),
  };

  static Map<String, Object?> _preKey(Map<String, Object?> r) => {
    'id': _integer(r, 'id'),
    'record': _blob(r, 'record'),
  };

  static Map<String, Object?> _signedPreKey(Map<String, Object?> r) => {
    'id': _integer(r, 'id'),
    'record': _blob(r, 'record'),
    'createdAt': _integer(r, 'created_at'),
  };

  static Map<String, Object?> _session(Map<String, Object?> r) => {
    'id': _string(r, 'id'),
    'record': _blob(r, 'record'),
  };

  static Map<String, Object?> _senderKey(Map<String, Object?> r) => {
    'groupId': _string(r, 'group_id'),
    'senderId': _string(r, 'sender_id'),
    'deviceId': _integer(r, 'device_id'),
    'record': _blob(r, 'record'),
    'updatedAt': _integer(r, 'updated_at'),
  };

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> tables,
    String name,
  ) {
    final raw = tables[name];
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('Table $name is not an array');
    return raw
        .map((row) {
          if (row is! Map) throw FormatException('Invalid row in table $name');
          return row.cast<String, Object?>();
        })
        .toList(growable: false);
  }

  static Map<String, String> _cryptoState(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map) throw const FormatException('Invalid crypto state');
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  static String _string(
    Map<String, Object?> row,
    String key, {
    String? alternate,
  }) {
    final value = row[key] ?? (alternate == null ? null : row[alternate]);
    if (value is! String) {
      throw FormatException('Missing text column $key');
    }
    return value;
  }

  static String? _nullableString(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid text column $key');
    return value;
  }

  static int _integer(Map<String, Object?> row, String key, {int? fallback}) {
    final value = row[key];
    if (value == null && fallback != null) return fallback;
    if (value is! num) throw FormatException('Missing integer column $key');
    return value.toInt();
  }

  static int? _nullableInteger(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! num) throw FormatException('Invalid integer column $key');
    return value.toInt();
  }

  static bool _boolean(
    Map<String, Object?> row,
    String key, {
    bool fallback = false,
  }) {
    final value = row[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num && (value == 0 || value == 1)) return value == 1;
    throw FormatException('Invalid boolean column $key');
  }

  static String _blob(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! Map || value['base64'] is! String) {
      throw FormatException('Missing binary column $key');
    }
    final encoded = value['base64']! as String;
    base64Decode(encoded);
    return encoded;
  }

  static void _verifyCounts(Object? raw, Map<String, Object?> tables) {
    if (raw == null) return;
    if (raw is! Map) throw const FormatException('Invalid Room row counts');
    for (final entry in raw.entries) {
      final rows = tables[entry.key.toString()];
      if (entry.value is! num ||
          rows is! List ||
          rows.length != (entry.value as num).toInt()) {
        throw FormatException('Room export row count mismatch: ${entry.key}');
      }
    }
  }

  static void _verifyReferences(Map<String, Object?> snapshot) {
    final conversationIds = (snapshot['conversations']! as List)
        .cast<Map<String, Object?>>()
        .map((row) => row['id'])
        .toSet();
    for (final message
        in (snapshot['messages']! as List).cast<Map<String, Object?>>()) {
      if (!conversationIds.contains(message['conversationId'])) {
        throw FormatException(
          'Message ${message['id']} references a missing conversation',
        );
      }
    }
  }
}
