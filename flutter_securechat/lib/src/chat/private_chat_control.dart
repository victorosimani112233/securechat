import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/signaling_service.dart';

const _privateChatControlPrefix = 'CHATCTRL:v2:';
const _privateControlPacketBytes = 16 * 1024;
const _privateControlLengthBytes = 4;
const _privateControlTypes = <String>{
  'delivery_receipt',
  'message_delete',
  'message_edit',
  'message_reaction',
  'message_pin',
  'typing_indicator',
  'disappearing_timer',
};

bool isPrivateChatControl(String plaintext) =>
    plaintext.startsWith(_privateChatControlPrefix);

String encodePrivateChatControl(SignalMessage control) {
  if (!_privateControlTypes.contains(control.type)) {
    throw ArgumentError.value(control.type, 'control', 'Unsupported control');
  }
  if (control.senderId.isEmpty ||
      control.recipientId.isEmpty ||
      control.senderId == control.recipientId) {
    throw ArgumentError.value(
      '${control.senderId}->${control.recipientId}',
      'control',
      'Sender and recipient must be distinct, non-empty identities',
    );
  }
  final protected = Map<String, Object?>.from(control.toJson())
    ..remove('senderId')
    ..remove('recipientId');
  final encoded = utf8.encode(jsonEncode(protected));
  if (encoded.length >
      _privateControlPacketBytes - _privateControlLengthBytes) {
    throw ArgumentError.value(
      encoded.length,
      'control',
      'Control is too large',
    );
  }
  final packet = Uint8List(_privateControlPacketBytes);
  ByteData.sublistView(packet).setUint32(0, encoded.length, Endian.big);
  packet.setRange(
    _privateControlLengthBytes,
    _privateControlLengthBytes + encoded.length,
    encoded,
  );
  final random = Random.secure();
  for (
    var index = encoded.length + _privateControlLengthBytes;
    index < packet.length;
    index++
  ) {
    packet[index] = random.nextInt(256);
  }
  return '$_privateChatControlPrefix${base64UrlEncode(packet)}';
}

SignalMessage decodePrivateChatControl({
  required String plaintext,
  required String authenticatedSenderId,
  required String localRecipientId,
}) {
  if (!isPrivateChatControl(plaintext)) {
    throw const FormatException('Not a private chat control');
  }
  final encoded = plaintext.substring(_privateChatControlPrefix.length);
  if (encoded.isEmpty || encoded.length > _privateControlPacketBytes * 2) {
    throw const FormatException('Invalid private chat control size');
  }
  final packet = Uint8List.fromList(
    base64Url.decode(base64Url.normalize(encoded)),
  );
  if (packet.length != _privateControlPacketBytes) {
    throw const FormatException('Invalid private chat control packet size');
  }
  final payloadLength = ByteData.sublistView(packet).getUint32(0, Endian.big);
  if (payloadLength < 2 ||
      payloadLength > _privateControlPacketBytes - _privateControlLengthBytes) {
    throw const FormatException('Invalid private chat control payload size');
  }
  final decoded = jsonDecode(
    utf8.decode(
      packet.sublist(
        _privateControlLengthBytes,
        _privateControlLengthBytes + payloadLength,
      ),
    ),
  );
  if (decoded is! Map) throw const FormatException('Invalid control object');
  final json = decoded.cast<String, Object?>();
  final type = json['type'];
  if (type is! String || !_privateControlTypes.contains(type)) {
    throw const FormatException('Unsupported private control type');
  }
  json['senderId'] = authenticatedSenderId;
  json['recipientId'] = localRecipientId;
  final signal = SignalMessage.decode(jsonEncode(json));
  if (signal is UnknownSignalMessage || signal is EncryptedSignalMessage) {
    throw const FormatException('Invalid private control payload');
  }
  return signal;
}

Future<bool> sendPrivateChatControl({
  required CryptoService crypto,
  required SignalingService signaling,
  required SignalMessage control,
}) async {
  final plaintext = encodePrivateChatControl(control);
  final envelope = await crypto.encryptDirect(
    recipientId: control.recipientId,
    plaintext: plaintext,
  );
  return signaling.send(
    EncryptedSignalMessage(
      senderId: control.senderId,
      recipientId: control.recipientId,
      timestamp: control.timestamp,
      envelope: envelope,
    ),
  );
}
