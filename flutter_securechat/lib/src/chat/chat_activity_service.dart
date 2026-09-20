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
    Future<bool> Function()? isMeteredConnection,
    this.reannounceCooldown = const Duration(seconds: 12),
  }) : _session = session,
       _signaling = signaling,
       _crypto = crypto,
       _isMeteredConnection = isMeteredConnection;

  static const idleTimeout = Duration(seconds: 3);

  /// Yaziyor-gostergesi durduktan sonra bu sure gecmeden yeniden duyurulmaz.
  ///
  /// Her kontrol paketi trafik analizi direnci icin sabit 16 KiB'a padlenir ve
  /// tel uzerinde ~29 KB'a cikar. Araliklarla yazan bir kullanici surekli
  /// yaziyor/durdu dongusu uretir; her dongu iki paket demektir. Cooldown bu
  /// churn'u keser, paket BOYUTUNU degistirmedigi icin gizlilik ozelligi
  /// bozulmaz.
  final Duration reannounceCooldown;

  final SessionStore _session;
  final SignalingService _signaling;
  final CryptoService _crypto;
  final Future<bool> Function()? _isMeteredConnection;
  Timer? _idleTimer;
  Conversation? _activeConversation;
  bool _announcedTyping = false;
  bool _disposed = false;
  DateTime? _lastStoppedAt;

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
    if (!_announcedTyping && !await _shouldSuppressAnnounce()) {
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
    if (shouldNotify) {
      _lastStoppedAt = DateTime.now();
      await _send(conversation, false);
    }
  }

  /// Yaziyor-gostergesi bu turda hic gonderilmeli mi.
  ///
  /// Sayacli baglantida tamamen kapatilir: gosterge kozmetiktir, sabit-boyutlu
  /// paket ise pahalidir. Ayrica kisa araliklarla yeniden duyurulmasi
  /// engellenir.
  Future<bool> _shouldSuppressAnnounce() async {
    final metered = _isMeteredConnection;
    if (metered != null && await metered()) return true;
    final last = _lastStoppedAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < reannounceCooldown;
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
