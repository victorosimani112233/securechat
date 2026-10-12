import '../core/models.dart';
import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'private_chat_control.dart';

/// Tek gosterimlik mesaj acilinca yazarina sifreli "acildi" bildirimi.
///
/// Onceden gonderen taraf mesaj gider gitmez "Acildi" gosteriyordu; alicinin
/// actigini ileten bir sinyal yoktu (QA 2026-10-12 Bulgu 13). Okundu bilgisi
/// kapaliysa gonderilmez (WhatsApp davranisi).
class ViewOnceReceipts {
  ViewOnceReceipts({
    required SessionStore session,
    required CryptoService crypto,
    required SignalingService signaling,
    DateTime Function()? now,
  }) : _session = session,
       _crypto = crypto,
       _signaling = signaling,
       _now = now ?? DateTime.now;

  final SessionStore _session;
  final CryptoService _crypto;
  final SignalingService _signaling;
  final DateTime Function() _now;

  Future<bool> notifyOpened(LocalMessage message) async {
    final userId = _session.userId;
    if (!message.isViewOnce ||
        message.isOutgoing ||
        !_session.shareReadReceipts ||
        userId == null ||
        message.senderId.isEmpty ||
        message.senderId == userId) {
      return false;
    }
    return sendPrivateChatControl(
      crypto: _crypto,
      signaling: _signaling,
      control: ViewOnceOpenedSignal(
        senderId: userId,
        recipientId: message.senderId,
        timestamp: _now(),
        messageId: message.id,
      ),
    );
  }
}
