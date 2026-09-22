import 'dart:async';

import '../auth/phone_privacy.dart';
import '../chat/private_chat_control.dart';
import '../core/signal_message.dart';
import '../services/async_operation_tracker.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'contact_discovery_api.dart';

typedef EncryptedPhoneSender = Future<bool> Function(EncryptedSignalMessage);

/// Optional, recipient-only disclosure. No plaintext lookup or group sharing.
class PhoneNumberSharingService {
  PhoneNumberSharingService({
    required SessionStore session,
    required CryptoService crypto,
    required SignalingService signaling,
    required SecureChatDatabase database,
    required ContactDiscoveryApi discovery,
    AsyncOperationFailureHandler? onAsyncFailure,
    DateTime Function()? now,
  }) : _session = session,
       _crypto = crypto,
       _signaling = signaling,
       _database = database,
       _discovery = discovery,
       _onAsyncFailure = onAsyncFailure,
       _now = now ?? DateTime.now;

  final SessionStore _session;
  final CryptoService _crypto;
  final SignalingService _signaling;
  final SecureChatDatabase _database;
  final ContactDiscoveryApi _discovery;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  final DateTime Function() _now;
  final _verificationAttempts = <String, DateTime>{};
  static final _phonePattern = RegExp(r'^\+[1-9][0-9]{6,14}$');
  static const verificationTimeout = Duration(seconds: 5);
  static const _verificationWindow = Duration(minutes: 1);
  static const _maximumVerificationsPerWindow = 20;

  String? _localPhone() {
    final raw = _session.phoneNumber;
    if (raw == null || raw.length > 64) return null;
    final phone = '+${normalizePhoneDigits(raw)}';
    return _phonePattern.hasMatch(phone) ? phone : null;
  }

  /// Called only by explicit direct text/media sends, never on receipt.
  /// Repeated introductions use the existing fixed-size encrypted control
  /// format, so missed/expired introductions recover on the next message.
  Future<bool> shareWith(
    String recipientId, {
    EncryptedPhoneSender? send,
  }) async {
    final userId = _session.userId;
    final phone = _localPhone();
    if (!_session.sharePhoneNumber ||
        !_session.isLoggedIn ||
        userId == null ||
        recipientId.isEmpty ||
        recipientId == userId ||
        phone == null) {
      return false;
    }
    try {
      final conversation = await _database.conversations.getByPeerId(
        recipientId,
      );
      if (conversation?.isGroup == true) return false;
      final now = _now();
      final envelope = await _crypto.encryptDirect(
        recipientId: recipientId,
        plaintext: encodePrivateChatControl(
          SharedPhoneSignal(
            senderId: userId,
            recipientId: recipientId,
            timestamp: now,
            phoneNumber: phone,
          ),
        ),
      );
      // Consent/account may change while encryption awaits a prekey bundle.
      if (!_session.sharePhoneNumber ||
          !_session.isLoggedIn ||
          _session.userId != userId ||
          _localPhone() != phone) {
        return false;
      }
      final signal = EncryptedSignalMessage(
        senderId: userId,
        recipientId: recipientId,
        timestamp: now,
        envelope: envelope,
      );
      return await (send == null ? _signaling.send(signal) : send(signal));
    } catch (error) {
      await _reportFailure('phone-sharing.send', error);
      return false;
    }
  }

  /// The encrypted sender identity is authoritative; the claimed number is
  /// not. Validate its directory association before changing any local label.
  Future<bool> accept(SharedPhoneSignal signal) async {
    final phone = signal.phoneNumber;
    final peerId = signal.senderId;
    final localUserId = _session.userId;
    final accessToken = _session.accessToken;
    if (!_session.isLoggedIn ||
        signal.recipientId != localUserId ||
        peerId.isEmpty ||
        peerId == localUserId ||
        phone.length > 16 ||
        !_phonePattern.hasMatch(phone)) {
      return false;
    }
    try {
      final local = await _database.contacts.getById(peerId);
      var conversation = await _database.conversations.getByPeerId(peerId);
      if (conversation?.isGroup == true) return false;
      final knownPhone = local?.phoneNumber.isNotEmpty == true
          ? local!.phoneNumber
          : conversation?.peerPhone;
      if (knownPhone == null ||
          normalizePhoneDigits(knownPhone) != phone.substring(1)) {
        final now = _now();
        _verificationAttempts.removeWhere(
          (_, attemptedAt) =>
              now.difference(attemptedAt) >= _verificationWindow,
        );
        // Bound both per-peer guessing and total directory work from strangers.
        if (_verificationAttempts.containsKey(peerId) ||
            _verificationAttempts.length >= _maximumVerificationsPerWindow) {
          return false;
        }
        _verificationAttempts[peerId] = now;
        final hash = await hashPhoneNumber(phone);
        final matches = await _discovery
            .checkUsers([hash], accessToken!)
            .timeout(verificationTimeout);
        if (!matches.any((m) => m.userId == peerId && m.phoneHash == hash)) {
          return false;
        }
      }
      if (_session.userId != localUserId || !_session.isLoggedIn) return false;
      // Reload after network I/O so concurrent chat edits are not overwritten.
      conversation = await _database.conversations.getByPeerId(peerId);
      if (conversation?.isGroup == true) return false;
      final contact = await _database.contacts.getById(peerId);
      final name = contact?.displayName.isNotEmpty == true
          ? contact!.displayName
          : phone;
      final displayPhone = contact?.phoneNumber.isNotEmpty == true
          ? contact!.phoneNumber
          : phone;
      if (conversation == null) {
        await _database.conversations.insert(
          ConversationEntity(
            id: peerId,
            peerId: peerId,
            peerName: name,
            peerPhone: displayPhone,
          ),
        );
      } else if (conversation.peerName != name ||
          conversation.peerPhone != displayPhone) {
        await _database.conversations.updatePeerIdentity(
          conversation.id,
          name,
          displayPhone,
        );
      }
      return true;
    } catch (error) {
      await _reportFailure('phone-sharing.verify', error);
      return false;
    }
  }

  Future<void> _reportFailure(String operation, Object error) async {
    try {
      await _onAsyncFailure?.call(
        operation,
        StateError('Phone sharing failed (${error.runtimeType})'),
        StackTrace.current,
      );
    } catch (_) {
      // Optional identity disclosure must not prevent message delivery.
    }
  }
}
