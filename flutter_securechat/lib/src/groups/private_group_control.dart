import 'dart:convert';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/signaling_service.dart';

const _privateGroupControlPrefix = 'GROUPCTRL:v2:';
const privateGroupCallPreparationAction = 'PREPARE_CALL';

/// Grup aciklamasinin en uzun hali (karakter).
const maxGroupDescriptionLength = 512;

/// Grup fotografinin ham boyut siniri. Fotograf her uyeye ayri sifrelenip
/// tek WebSocket cercevesinde (256 KB) gider; base64 ve sifreleme sarmali
/// boyutu yaklasik 1.8 katina cikarir.
const maxGroupPhotoBytes = 64 * 1024;

/// base64 haliyle fotograf siniri.
const _maxGroupPhotoBase64Length = (maxGroupPhotoBytes + 2) ~/ 3 * 4;

/// Fotograf yalniz JPEG ya da PNG ve [maxGroupPhotoBytes] icinde olabilir.
bool isAcceptedGroupPhoto(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > maxGroupPhotoBytes) return false;
  final jpeg =
      bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final png =
      bytes.length > pngSignature.length &&
      Iterable<int>.generate(
        pngSignature.length,
      ).every((index) => bytes[index] == pngSignature[index]);
  return jpeg || png;
}

/// Gelen base64 fotografi dogrular; gecersizse null.
String? acceptedGroupPhotoBase64(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return isAcceptedGroupPhoto(base64.decode(value)) ? value : null;
  } on FormatException {
    return null;
  }
}

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
    String? description,
    String? photo,
    DateTime? timestamp,
    Future<bool> Function(EncryptedSignalMessage signal)? sendSignal,
    void Function(String recipientId, Object error)? onRecipientUnavailable,
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
    if (targets.isNotEmpty &&
        sendSignal == null &&
        !await _signaling.ensureConnected(
          timeout: const Duration(seconds: 8),
        )) {
      throw StateError('Private group control connection is unavailable');
    }
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
      description: description,
      photo: photo,
      timestamp: sentAt,
    ).encode();
    for (final recipientId in targets) {
      final String envelope;
      try {
        envelope = await _crypto.encryptDirect(
          recipientId: recipientId,
          plaintext: payload,
        );
      } catch (error) {
        // Cagiran ulasilamayan uyeyi atlayabiliyorsa tek kisi butun islemi
        // dusurmez; atlayamiyorsa hata eskisi gibi yukari cikar.
        if (onRecipientUnavailable == null) rethrow;
        onRecipientUnavailable(recipientId, error);
        continue;
      }
      final signal = EncryptedSignalMessage(
        senderId: senderId,
        recipientId: recipientId,
        timestamp: sentAt,
        envelope: envelope,
      );
      final delivered =
          await (sendSignal?.call(signal) ?? _signaling.send(signal));
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
    description: payload.description,
    photo: payload.photo,
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
    this.description,
    this.photo,
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

  /// Bos dize aciklamanin kaldirildigini, null alanin yoklugunu belirtir.
  final String? description;

  /// base64 fotograf; bos dize fotografin kaldirildigini belirtir.
  final String? photo;
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
    final description = json['description'];
    if (description != null &&
        (description is! String ||
            description.length > maxGroupDescriptionLength)) {
      throw const FormatException('Invalid private group description');
    }
    final photo = json['photo'];
    if (photo != null &&
        (photo is! String || photo.length > _maxGroupPhotoBase64Length)) {
      throw const FormatException('Invalid private group photo');
    }
    return _PrivateGroupControlPayload(
      senderId: senderId,
      groupId: groupId,
      groupToken: groupToken,
      groupName: groupName,
      action: action,
      memberIds: members,
      targetMemberId: target as String?,
      description: description as String?,
      photo: photo as String?,
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
          if (description != null) 'description': description,
          if (photo != null) 'photo': photo,
          'timestamp': timestamp.millisecondsSinceEpoch,
        }),
      ),
    ).replaceAll('=', '');
    return '$_privateGroupControlPrefix$encoded';
  }
}
