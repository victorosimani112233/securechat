import 'dart:convert';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/signaling_service.dart';

const _privateGroupControlPrefix = 'GROUPCTRL:v2:';
const privateGroupCallPreparationAction = 'PREPARE_CALL';

String privateGroupCallRouteStateKey(String routingToken) =>
    'private-group-call-route:$routingToken';

bool isOpaqueGroupRoutingToken(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{43}=?$').hasMatch(value);

/// Sends group administration data only inside recipient-specific Signal
/// sessions. There is deliberately no server-side group directory: the server
/// observes only the sender/recipient pair needed while routing each opaque
/// envelope and cannot persist a reusable social graph.
class PrivateGroupControlSender {
  const PrivateGroupControlSender({
    required CryptoService crypto,
    required SignalingService signaling,
  }) : _crypto = crypto,
       _signaling = signaling;

  final CryptoService _crypto;
  final SignalingService _signaling;

  Future<void> send({
    required String senderId,
    required String groupId,
    required String groupName,
    required Iterable<String> memberIds,
    required Iterable<String> recipients,
    required String action,
    String? targetMemberId,
    DateTime? timestamp,
  }) async {
    final members = memberIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (members.length > 256) {
      throw StateError('Private group directory exceeds 256 members');
    }
    final targets = recipients
        .where((id) => id.isNotEmpty && id != senderId)
        .toSet()
        .toList(growable: false);
    final sentAt = timestamp ?? DateTime.now();
    final groupToken = await groupRoutingToken(groupId);
    final payload = _PrivateGroupControlPayload(
      senderId: senderId,
      groupId: groupId,
      groupToken: groupToken,
      groupName: groupName,
      action: action,
      memberIds: members,
      targetMemberId: targetMemberId,
      timestamp: sentAt,
    ).encode();
    for (final recipientId in targets) {
      final envelope = await _crypto.encryptDirect(
        recipientId: recipientId,
        plaintext: payload,
      );
      final delivered = await _signaling.send(
        EncryptedSignalMessage(
          senderId: senderId,
          recipientId: recipientId,
          timestamp: sentAt,
          envelope: envelope,
        ),
      );
      if (!delivered) {
        throw StateError('Private group control delivery failed');
      }
    }
  }
}

bool isPrivateGroupControl(String plaintext) =>
    plaintext.startsWith(_privateGroupControlPrefix);

Future<GroupNotificationSignal> decodePrivateGroupControl({
  required String plaintext,
  required String authenticatedSenderId,
  required String localRecipientId,
}) async {
  if (!isPrivateGroupControl(plaintext)) {
    throw const FormatException('Not a private group control payload');
  }
  final encoded = plaintext.substring(_privateGroupControlPrefix.length);
  final decoded = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
  );
  if (decoded is! Map) {
    throw const FormatException('Invalid private group control JSON');
  }
  final payload = _PrivateGroupControlPayload.fromJson(
    decoded.cast<String, Object?>(),
  );
  if (payload.senderId != authenticatedSenderId) {
    throw const FormatException('Private group control sender mismatch');
  }
  final expectedToken = await groupRoutingToken(payload.groupId);
  if (payload.groupToken != expectedToken) {
    throw const FormatException('Private group control token mismatch');
  }
  return GroupNotificationSignal(
    senderId: authenticatedSenderId,
    recipientId: localRecipientId,
    timestamp: payload.timestamp,
    groupId: payload.groupId,
    groupName: payload.groupName,
    action: payload.action,
    groupMembers: payload.memberIds,
    targetMemberId: payload.targetMemberId,
  );
}

class _PrivateGroupControlPayload {
  const _PrivateGroupControlPayload({
    required this.senderId,
    required this.groupId,
    required this.groupToken,
    required this.groupName,
    required this.action,
    required this.memberIds,
    required this.targetMemberId,
    required this.timestamp,
  });

  static const version = 2;
  final String senderId;
  final String groupId;
  final String groupToken;
  final String groupName;
  final String action;
  final List<String> memberIds;
  final String? targetMemberId;
  final DateTime timestamp;

  factory _PrivateGroupControlPayload.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != version) {
      throw const FormatException('Unsupported private group control version');
    }
    final senderId = json['senderId'];
    final groupId = json['groupId'];
    final groupToken = json['groupToken'];
    final groupName = json['groupName'];
    final action = json['action'];
    final rawMembers = json['memberIds'];
    final timestamp = json['timestamp'];
    if (senderId is! String ||
        senderId.isEmpty ||
        groupId is! String ||
        groupId.isEmpty ||
        groupToken is! String ||
        groupToken.isEmpty ||
        groupName is! String ||
        groupName.length > 256 ||
        action is! String ||
        action.isEmpty ||
        rawMembers is! List ||
        timestamp is! num) {
      throw const FormatException('Invalid private group control fields');
    }
    final members = rawMembers
        .whereType<String>()
        .where((id) => id.isNotEmpty && id.length <= 128)
        .toSet()
        .toList(growable: false);
    if (members.length != rawMembers.length || members.length > 256) {
      throw const FormatException('Invalid private group member list');
    }
    final target = json['targetMemberId'];
    if (target != null && (target is! String || target.length > 128)) {
      throw const FormatException('Invalid private group target');
    }
    return _PrivateGroupControlPayload(
      senderId: senderId,
      groupId: groupId,
      groupToken: groupToken,
      groupName: groupName,
      action: action,
      memberIds: members,
      targetMemberId: target as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
    );
  }

  String encode() {
    final encoded = base64UrlEncode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'v': version,
          'senderId': senderId,
          'groupId': groupId,
          'groupToken': groupToken,
          'groupName': groupName,
          'action': action,
          'memberIds': memberIds,
          if (targetMemberId != null) 'targetMemberId': targetMemberId,
          'timestamp': timestamp.millisecondsSinceEpoch,
        }),
      ),
    ).replaceAll('=', '');
    return '$_privateGroupControlPrefix$encoded';
  }
}
