import 'dart:convert';

import '../chat/private_chat_control.dart';
import '../core/peer_display_name.dart';
import '../core/signal_message.dart';
import '../services/async_operation_tracker.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

typedef EncryptedProfileNameSender =
    Future<bool> Function(EncryptedSignalMessage);

/// Kullanicinin kendi sectigi gorunen adi birebir yazdigi kisilere sifreli
/// paylasir; rehberinde olmayan biri ilk mesajda UUID yerine "~Ad" gorur
/// (QA 2026-10-12 Bulgu 3).
///
/// Numara degil, kullanicinin sectigi ad paylasilir; ayarlardan kapatilabilir.
/// Grup sohbetlerinde paylasilmaz. Alici tarafta rehber adi her zaman
/// onceliklidir: ad yalniz kisi kaydi olmayan karsi taraf icin kullanilir.
class ProfileNameSharingService {
  ProfileNameSharingService({
    required SessionStore session,
    required CryptoService crypto,
    required SignalingService signaling,
    required SecureChatDatabase database,
    AsyncOperationFailureHandler? onAsyncFailure,
    DateTime Function()? now,
  }) : _session = session,
       _crypto = crypto,
       _signaling = signaling,
       _database = database,
       _onAsyncFailure = onAsyncFailure,
       _now = now ?? DateTime.now;

  final SessionStore _session;
  final CryptoService _crypto;
  final SignalingService _signaling;
  final SecureChatDatabase _database;
  final AsyncOperationFailureHandler? _onAsyncFailure;
  final DateTime Function() _now;

  static const maxNameLength = 40;

  /// Ayni ad bu sureden once ayni kisiye yeniden gonderilmez. Kaybolan bir
  /// tanitim en gec bu sure sonra kendiliginden onarilir.
  static const resendAfter = Duration(days: 7);

  static const _sentPrefix = 'profile_name_sent:';
  static const _receivedPrefix = 'peer_profile_name:';

  /// Bidi/kontrol karakterleri ve fazla bosluk temizlenir; UUID bicimli ya da
  /// bos ad kabul edilmez.
  static String? sanitize(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), ' ')
        .replaceAll(
          RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]'),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = cleaned.runes.toList();
    final bounded = runes.length > maxNameLength
        ? String.fromCharCodes(runes.take(maxNameLength)).trim()
        : cleaned;
    final withoutMarker = bounded.replaceFirst(RegExp(r'^~+'), '').trim();
    if (withoutMarker.isEmpty || isOpaquePeerName(withoutMarker)) return null;
    return withoutMarker;
  }

  /// Yalniz acik birebir gonderimlerde cagrilir, alimda asla.
  Future<bool> shareWith(
    String recipientId, {
    EncryptedProfileNameSender? send,
  }) async {
    final userId = _session.userId;
    final name = sanitize(_session.displayName ?? '');
    if (!_session.shareProfileName ||
        !_session.isLoggedIn ||
        userId == null ||
        recipientId.isEmpty ||
        recipientId == userId ||
        name == null) {
      return false;
    }
    try {
      final conversation = await _database.conversations.getByPeerId(
        recipientId,
      );
      if (conversation?.isGroup == true) return false;
      final now = _now();
      final marker = await _database.cryptoState.get(
        '$_sentPrefix$recipientId',
      );
      if (_isFresh(marker, name, await _peerIdentity(recipientId), now)) {
        return false;
      }
      final envelope = await _crypto.encryptDirect(
        recipientId: recipientId,
        plaintext: encodePrivateChatControl(
          SharedProfileNameSignal(
            senderId: userId,
            recipientId: recipientId,
            timestamp: now,
            displayName: name,
          ),
        ),
      );
      // Izin/hesap sifreleme beklenirken degismis olabilir.
      if (!_session.shareProfileName ||
          !_session.isLoggedIn ||
          _session.userId != userId) {
        return false;
      }
      final signal = EncryptedSignalMessage(
        senderId: userId,
        recipientId: recipientId,
        timestamp: now,
        envelope: envelope,
      );
      final sent = await (send == null
          ? _signaling.send(signal)
          : send(signal));
      if (sent) {
        // Isaret karsi tarafin o anki kimligine baglanir: yeniden kurulan ya
        // da kurtarilan karsi taraf adi hemen yeniden alir (QA 2026-10-13
        // T12).
        await _database.cryptoState.put(
          '$_sentPrefix$recipientId',
          '${now.millisecondsSinceEpoch}|'
              '${await _peerIdentity(recipientId)}|$name',
        );
      }
      return sent;
    } catch (error) {
      await _reportFailure('profile-name.send', error);
      return false;
    }
  }

  bool _isFresh(String? marker, String name, String identity, DateTime now) {
    if (marker == null) return false;
    final parts = marker.split('|');
    if (parts.length < 3) return false;
    final sentAt = int.tryParse(parts[0]);
    if (sentAt == null ||
        parts[1] != identity ||
        parts.sublist(2).join('|') != name) {
      return false;
    }
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(sentAt));
    return !age.isNegative && age < resendAfter;
  }

  /// Karsi tarafin pinli kimligi; oturum yoksa bos.
  Future<String> _peerIdentity(String peerId) async {
    final identity = await _database.identities.get(peerId);
    return identity == null ? '' : base64UrlEncode(identity.identityKey);
  }

  /// Karsi taraf durumunu kaybettiginde (oturum sifirlama istegi) ad bir
  /// sonraki gonderimde yeniden paylasilir.
  Future<void> forgetSentTo(String peerId) =>
      _database.cryptoState.delete('$_sentPrefix$peerId');

  /// Gonderen kimligi sifreli kanaldan dogrulanmistir; ad yalniz etiket.
  Future<bool> accept(SharedProfileNameSignal signal) async {
    final peerId = signal.senderId;
    final localUserId = _session.userId;
    final name = sanitize(signal.displayName);
    if (!_session.isLoggedIn ||
        signal.recipientId != localUserId ||
        peerId.isEmpty ||
        peerId == localUserId ||
        name == null) {
      return false;
    }
    try {
      await _database.cryptoState.put('$_receivedPrefix$peerId', name);
      final conversation = await _database.conversations.getByPeerId(peerId);
      if (conversation == null || conversation.isGroup) return true;
      // Rehber (ya da elle adlandirilmis) kayit varsa onun adi gecerli kalir.
      // Yalniz numarayla acilan kayitta ad numaranin kendisidir; kullanici ad
      // yazmamistir ve paylasilan ad gosterilir (QA 2026-10-13 T2).
      final contact = await _database.contacts.getById(peerId);
      if (contact != null && !isUnnamedContact(contact)) return true;
      final current = conversation.peerName;
      final label = '~$name';
      final replaceable =
          isOpaquePeerName(current, peerId: peerId) ||
          current.startsWith('~') ||
          current == conversation.peerPhone;
      if (replaceable && current != label) {
        await _database.conversations.updatePeerIdentity(
          conversation.id,
          label,
          conversation.peerPhone,
        );
      }
      return true;
    } catch (error) {
      await _reportFailure('profile-name.accept', error);
      return false;
    }
  }

  /// Kullanicinin ad vermedigi, yalniz numarayla eklenmis kisi kaydi.
  static bool isUnnamedContact(ContactEntity contact) =>
      contact.addedManually &&
      (contact.displayName.trim().isEmpty ||
          contact.displayName.trim() == contact.phoneNumber.trim());

  /// Kisi kaydi olmayan karsi taraf icin "~Ad" etiketi; yoksa null.
  ///
  /// Statik: yeni sohbet olusturan her yol (on plan, arka plan medya alimi)
  /// servis ornegi olmadan da okuyabilsin. Tanitim mesaji sohbetten once
  /// gelir ve burada bekler.
  static Future<String?> storedLabel(
    SecureChatDatabase database,
    String peerId,
  ) async {
    final name = await database.cryptoState.get('$_receivedPrefix$peerId');
    return name == null || name.isEmpty ? null : '~$name';
  }

  Future<void> _reportFailure(String operation, Object error) async {
    try {
      await _onAsyncFailure?.call(
        operation,
        StateError('Profile name sharing failed (${error.runtimeType})'),
        StackTrace.current,
      );
    } catch (_) {
      // Istege bagli tanitim mesaj teslimini engellememeli.
    }
  }
}
