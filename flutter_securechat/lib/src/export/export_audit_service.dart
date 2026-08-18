import 'dart:convert';

import '../core/signal_message.dart';
import '../groups/private_group_control.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

class ExportNotAllowed implements Exception {
  const ExportNotAllowed(this.message);
  final String message;
  @override
  String toString() => message;
}

class ConversationExport {
  const ConversationExport({required this.fileName, required this.text});
  final String fileName;
  final String text;
}

class ExportAuditService {
  ExportAuditService({
    required SecureChatDatabase database,
    required SessionStore session,
    required CryptoService crypto,
    required SignalingService signaling,
  }) : _database = database,
       _session = session,
       _crypto = crypto,
       _signaling = signaling,
       _groupControls = PrivateGroupControlSender(
         crypto: crypto,
         signaling: signaling,
       );

  final SecureChatDatabase _database;
  final SessionStore _session;
  final CryptoService _crypto;
  final SignalingService _signaling;
  final PrivateGroupControlSender _groupControls;

  Stream<List<ExportLogEntity>> watchHistory(String groupId) =>
      _database.exportLogs.observeForGroup(groupId);

  Future<bool> isLocalAdmin(String groupId) async {
    final group = await _database.conversations.getById(groupId);
    final userId = _session.userId;
    return group != null &&
        userId != null &&
        _split(group.groupAdmins).contains(userId);
  }

  Future<ConversationExport> exportConversation(String conversationId) async {
    final conversation = await _database.conversations.getById(conversationId);
    if (conversation == null) {
      throw const ExportNotAllowed('Sohbet bulunamadı.');
    }
    if (conversation.isGroup && !conversation.isExportEnabled) {
      throw const ExportNotAllowed(
        'Grup yöneticisi dışa aktarmaya izin vermiyor.',
      );
    }
    final messages = await _database.messages.getMessagesPaginated(
      conversationId,
      1 << 30,
      0,
    );
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final memberNames = <String, String>{
      for (final contact in await _database.contacts.getAllOnce())
        contact.id: contact.displayName,
    };
    final buffer = StringBuffer()
      ..writeln('elçim — Sohbet Dışa Aktarımı')
      ..writeln('Sohbet: ${conversation.peerName}')
      ..writeln('Tarih: ${_format(DateTime.now().millisecondsSinceEpoch)}')
      ..writeln('Mesaj sayısı: ${messages.length}')
      ..writeln('────────────────────────────────────────')
      ..writeln();
    for (final message in messages) {
      final sender = message.isOutgoing
          ? 'Ben'
          : memberNames[message.senderId] ??
                (message.senderId.isEmpty
                    ? conversation.peerName
                    : message.senderId);
      buffer.writeln(
        '[${_format(message.timestamp)}] $sender: ${_content(message)}',
      );
    }
    if (conversation.isGroup) {
      await _recordEvent(conversation, messages);
    }
    return ConversationExport(
      fileName:
          'elcim_${_safeName(conversation.peerName)}_'
          '${DateTime.now().millisecondsSinceEpoch}.txt',
      text: buffer.toString(),
    );
  }

  Future<void> toggleGroupExport(String groupId, bool enabled) async {
    final userId = _session.userId;
    if (userId == null) {
      throw const ExportNotAllowed('Kullanıcı giriş yapmamış.');
    }
    final group = await _database.conversations.getById(groupId);
    if (group == null || !group.isGroup) {
      throw const ExportNotAllowed('Grup bulunamadı.');
    }
    final admins = _split(group.groupAdmins);
    final members = _split(group.groupMembers);
    final effectiveAdmins = admins.isEmpty && members.isNotEmpty
        ? <String>[members.first]
        : admins;
    if (!effectiveAdmins.contains(userId)) {
      throw const ExportNotAllowed(
        'Sadece grup yöneticisi bu ayarı değiştirebilir.',
      );
    }
    await _database.conversations.updateExportEnabled(groupId, enabled);
    await _groupControls.send(
      senderId: userId,
      groupId: groupId,
      groupName: group.peerName,
      memberIds: members,
      recipients: members,
      action: 'UPDATE_EXPORT_POLICY',
      targetMemberId: enabled.toString(),
    );
  }

  Future<void> _recordEvent(
    ConversationEntity group,
    List<MessageEntity> messages,
  ) async {
    final userId = _session.userId;
    if (userId == null) return;
    final now = DateTime.now();
    final groupToken = await groupRoutingToken(group.id);
    for (final adminId in _split(group.groupAdmins)) {
      if (adminId == userId) continue;
      try {
        final routeNonce = newOpaqueRoutingNonce();
        final payload = jsonEncode(<String, Object?>{
          'groupId': group.id,
          'groupToken': groupToken,
          'routeNonce': routeNonce,
          'actorUserId': userId,
          'actorDisplayName': _session.displayName ?? userId,
          'eventType': 'EXPORT',
          'timestamp': now.millisecondsSinceEpoch,
          'messageCount': messages.length,
          if (messages.isNotEmpty) 'firstMsgTs': messages.first.timestamp,
          if (messages.isNotEmpty) 'lastMsgTs': messages.last.timestamp,
        });
        final envelope = await _crypto.encryptDirect(
          recipientId: adminId,
          plaintext: payload,
        );
        await _signaling.send(
          AdminEncryptedLogSignal(
            senderId: userId,
            timestamp: now,
            groupId: routeNonce,
            eventType: 'PRIVATE_EVENT',
            adminPayloads: {adminId: envelope},
          ),
        );
      } catch (_) {
        // Per-admin failure must not expose plaintext or abort the export.
      }
    }
  }

  static String _content(MessageEntity message) {
    if (message.contentType == StorageMessageContentType.deleted) {
      return '[Silinen mesaj]';
    }
    if (message.contentType == StorageMessageContentType.system) {
      return '[${message.content}]';
    }
    return switch (message.contentType) {
      StorageMessageContentType.file =>
        '[Dosya: ${message.caption?.isNotEmpty == true ? message.caption : 'dosya'}]',
      StorageMessageContentType.voiceNote => '[Sesli mesaj]',
      StorageMessageContentType.poll => '[Anket]',
      _ => message.content,
    };
  }

  static List<String> _split(String? value) =>
      value?.split(',').where((item) => item.isNotEmpty).toList() ?? const [];
  static String _safeName(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  static String _format(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${_two(date.day)}.${_two(date.month)}.${date.year} '
        '${_two(date.hour)}:${_two(date.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
