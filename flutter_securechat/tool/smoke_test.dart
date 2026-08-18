import '../lib/src/core/models.dart';
import '../lib/src/core/signal_message.dart';

void main() {
  _localMessagePreview();
  _signalRoundTrip();
  _unknownSignalSurvives();
}

void _localMessagePreview() {
  final text = LocalMessage(
    id: '1',
    conversationId: 'c',
    senderId: 'me',
    peerId: 'p',
    content: 'gizli',
    contentType: MessageContentType.text,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1),
    status: MessageStatus.sent,
    isOutgoing: true,
    isViewOnce: true,
  );
  assert(text.previewText == 'Tek gösterimlik mesaj');

  final fileContent = LocalMessage.buildFileContent(
    fileName: 'rapor.pdf',
    mimeType: 'application/pdf',
    fileSize: 42,
  );
  final file = LocalMessage(
    id: '2',
    conversationId: 'c',
    senderId: 'me',
    peerId: 'p',
    content: fileContent,
    contentType: MessageContentType.file,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1),
    status: MessageStatus.sent,
    isOutgoing: true,
  );
  assert(file.fileName == 'rapor.pdf');
  assert(file.fileSize == 42);
  assert(file.previewText == 'rapor.pdf');
}

void _signalRoundTrip() {
  final signal = EncryptedSignalMessage(
    senderId: 'a',
    recipientId: 'b',
    timestamp: DateTime.fromMillisecondsSinceEpoch(123),
    envelope: 'E2EE:v1:SIGNAL:42:abc',
  );
  final decoded = SignalMessage.decode(signal.encode());
  assert(decoded is EncryptedSignalMessage);
  assert((decoded as EncryptedSignalMessage).envelope == signal.envelope);
  assert(decoded.timestamp.millisecondsSinceEpoch == 123);
}

void _unknownSignalSurvives() {
  final decoded = SignalMessage.decode(
    '{"type":"server_shutdown","senderId":"server","recipientId":"me","timestamp":7}',
  );
  assert(decoded is UnknownSignalMessage);
  assert(decoded.type == 'server_shutdown');
}
