import 'dart:async';

import '../core/models.dart';
import '../core/signal_message.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import 'private_chat_control.dart';

/// Sends ephemeral typing state only inside fixed-size encrypted controls.
///
/// There is deliberately no plaintext or server-visible group fallback.
class ChatActivityService {
  ChatActivityService({
    required SessionStore session,
    required SignalingService signaling,
    required CryptoService crypto,
  }) : _session = session,
       _signaling = signaling,
       _crypto = crypto;

  static const idleTimeout = Duration(seconds: 3);

  final SessionStore _session;
  final SignalingService _signaling;
  final CryptoService _crypto;
  Timer? _idleTimer;
  Conversation? _activeConversation;
  bool _announcedTyping = false;
  bool _disposed = false;

  Future<void> updateTyping(Conversation conversation, bool isTyping) async {
    if (_disposed) return;
    if (_activeConversation?.id != conversation.id) {
      await stopTyping();
      _activeConversation = conversation;
    }
    _idleTimer?.cancel();
    if (!isTyping) {
      await stopTyping();
      return;
    }
    if (!_announcedTyping) {
      _announcedTyping = await _send(conversation, true);
    }
    _idleTimer = Timer(idleTimeout, () {
      unawaited(stopTyping());
    });
  }

  Future<void> stopTyping() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final conversation = _activeConversation;
    final shouldNotify = _announcedTyping && conversation != null;
    _announcedTyping = false;
    _activeConversation = null;
    if (shouldNotify) await _send(conversation, false);
  }

  Future<bool> _send(Conversation conversation, bool isTyping) async {
    final userId = _session.userId;
    if (userId == null || userId.isEmpty) return false;
    final recipients = conversation.isGroup
        ? conversation.groupMembers.where((id) => id != userId)
        : <String>[conversation.peerId];
    if (recipients.isEmpty) return false;
    var allSent = true;
    for (final recipient in recipients) {
      try {
        final sent = await sendPrivateChatControl(
          crypto: _crypto,
          signaling: _signaling,
          control: TypingIndicatorSignal(
            senderId: userId,
            recipientId: recipient,
            timestamp: DateTime.now(),
            isTyping: isTyping,
          ),
        );
        allSent = allSent && sent;
      } catch (_) {
        allSent = false;
      }
    }
    return allSent;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stopTyping();
    _disposed = true;
  }
}
