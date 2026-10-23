import 'dart:async';
import 'dart:convert';

import '../core/signal_message.dart';
import '../services/async_operation_tracker.dart';
import '../services/crypto_service.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import 'peer_capabilities.dart';

/// Birebir aramanin SDP ve ICE sinyallerini uctan uca sifreler.
///
/// Onceden teklif, yanit ve adaylar sunucudan duz JSON olarak geciyordu.
/// Sunucu teklifteki DTLS parmak izini kendi parmak iziyle degistirip iki
/// taraf arasina girebilir, ses ve goruntuyu cozebilirdi. Sinyal artik Olm
/// ile sifrelenip `e2ee` alaninda tasinir; parmak izi yalniz karsi tarafin
/// cihazinda acilir. Sunucu bu alanlari okumaz, olduklari gibi iletir.
///
/// Karsi taraf [callSignalEncryptionCapability] bildirmediyse (eski surum)
/// sinyal duz gider. Bildirmis bir kisiden gelen duz sinyal reddedilir:
/// sunucu sifreli sinyali dusurup yerine duz sinyal koyamaz.
///
/// Grup aramasinda esler yonlendirme belirteciyle adreslenir ve bunlarin
/// yetenek kaydi yoktur; grup SDP'leri duz kalir. Grup medyasi zaten
/// cerceve duzeyinde ayrica sifrelidir.
class EncryptedCallSignaling implements SignalingService {
  EncryptedCallSignaling({
    required SignalingService inner,
    required CryptoService crypto,
    required CryptoStateDao cryptoState,
    AsyncOperationFailureHandler? onFailure,
  }) : _inner = inner,
       _crypto = crypto,
       _capabilities = PeerCapabilities(cryptoState),
       _onFailure = onFailure;

  static const _prefix = 'CALLSIG:v1:';

  final SignalingService _inner;
  final CryptoService _crypto;
  final PeerCapabilities _capabilities;
  final AsyncOperationFailureHandler? _onFailure;

  StreamController<SignalMessage>? _incoming;
  StreamSubscription<SignalMessage>? _subscription;
  Future<void> _tail = Future<void>.value();

  /// Gelen sinyaller sirasi korunarak tek tek islenir: ICE adayi tekliften
  /// once arama yoneticisine ulasmamali.
  @override
  Stream<SignalMessage> get incoming {
    final existing = _incoming;
    if (existing != null) return existing.stream;
    late final StreamController<SignalMessage> controller;
    controller = StreamController<SignalMessage>.broadcast(
      onListen: () {
        _subscription ??= _inner.incoming.listen(
          (signal) {
            _tail = _tail.then((_) async {
              final opened = await _open(signal);
              if (opened != null && !controller.isClosed) {
                controller.add(opened);
              }
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );
      },
    );
    _incoming = controller;
    return controller.stream;
  }

  @override
  Future<bool> send(SignalMessage message) async {
    if (!_isCallSignal(message) ||
        !await _capabilities.allSupport({
          message.recipientId,
        }, callSignalEncryptionCapability)) {
      return _inner.send(message);
    }
    final String envelope;
    try {
      envelope = await _crypto.encryptDirect(
        recipientId: message.recipientId,
        plaintext: _prefix + jsonEncode(_payload(message)),
      );
    } catch (error, stackTrace) {
      // Sifrelenemeyen sinyal duz gonderilmez; arama yoneticisi gonderimi
      // basarisiz sayar.
      await _report('call-signal.encrypt', error, stackTrace);
      return false;
    }
    return _inner.send(_sealed(message, envelope));
  }

  static bool _isCallSignal(SignalMessage signal) =>
      signal is SdpOfferSignal ||
      signal is SdpAnswerSignal ||
      signal is IceCandidateSignal;

  static String? _envelopeOf(SignalMessage signal) => switch (signal) {
    SdpOfferSignal(:final e2ee) => e2ee,
    SdpAnswerSignal(:final e2ee) => e2ee,
    IceCandidateSignal(:final e2ee) => e2ee,
    _ => null,
  };

  /// Sinyal turu de sifreli icerige baglanir: sunucu bir yaniti teklif
  /// olarak ya da baska bir kisiye yonlendiremez.
  static Map<String, Object?> _payload(SignalMessage signal) =>
      switch (signal) {
        SdpOfferSignal(:final sdp) => {
          'type': signal.type,
          'to': signal.recipientId,
          'sdp': sdp,
        },
        SdpAnswerSignal(:final sdp) => {
          'type': signal.type,
          'to': signal.recipientId,
          'sdp': sdp,
        },
        IceCandidateSignal(
          :final candidate,
          :final sdpMid,
          :final sdpMLineIndex,
        ) =>
          {
            'type': signal.type,
            'to': signal.recipientId,
            'candidate': candidate,
            'sdpMid': sdpMid,
            'sdpMLineIndex': sdpMLineIndex,
          },
        _ => throw ArgumentError.value(signal.type, 'signal'),
      };

  static SignalMessage _sealed(SignalMessage signal, String envelope) =>
      switch (signal) {
        SdpOfferSignal() => SdpOfferSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          sdp: '',
          // Gelen aramayi gostermek icin gereken tek bilgi; icerik degil.
          callType: signal.callType,
          e2ee: envelope,
        ),
        SdpAnswerSignal() => SdpAnswerSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          sdp: '',
          e2ee: envelope,
        ),
        IceCandidateSignal() => IceCandidateSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          candidate: '',
          sdpMLineIndex: 0,
          e2ee: envelope,
        ),
        _ => signal,
      };

  Future<SignalMessage?> _open(SignalMessage signal) async {
    if (!_isCallSignal(signal)) return signal;
    final envelope = _envelopeOf(signal);
    if (envelope == null || envelope.isEmpty) {
      // Sifreli sinyal gonderebilen kisiden duz sinyal gelmesi sunucunun
      // araya girmeye calistigini gosterir.
      if (await _capabilities.allSupport({
        signal.senderId,
      }, callSignalEncryptionCapability)) {
        await _report(
          'call-signal.plaintext-rejected',
          StateError('Plaintext call signal from an encrypting peer'),
          StackTrace.current,
        );
        return null;
      }
      return signal;
    }
    try {
      final plaintext = await _crypto.decryptDirect(
        senderId: directDecryptionPeer(
          envelope: envelope,
          authenticatedSenderId: signal.senderId,
          localRecipientId: signal.recipientId,
        ),
        envelope: envelope,
      );
      if (!plaintext.startsWith(_prefix)) {
        throw const FormatException('Not a call signal');
      }
      final json = (jsonDecode(plaintext.substring(_prefix.length)) as Map)
          .cast<String, Object?>();
      if (json['type'] != signal.type || json['to'] != signal.recipientId) {
        throw const FormatException('Call signal binding mismatch');
      }
      // Dogrulanmis sifreli sinyal yetenegi kanitlar; yanit ve adaylar da
      // sifreli gider.
      await _capabilities.recordOne(
        signal.senderId,
        callSignalEncryptionCapability,
      );
      return switch (signal) {
        SdpOfferSignal() => SdpOfferSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          sdp: json['sdp'] as String,
          callType: signal.callType,
        ),
        SdpAnswerSignal() => SdpAnswerSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          sdp: json['sdp'] as String,
        ),
        IceCandidateSignal() => IceCandidateSignal(
          senderId: signal.senderId,
          recipientId: signal.recipientId,
          timestamp: signal.timestamp,
          candidate: json['candidate'] as String,
          sdpMid: json['sdpMid'] as String?,
          sdpMLineIndex: (json['sdpMLineIndex'] as num).toInt(),
        ),
        _ => null,
      };
    } catch (error, stackTrace) {
      // Cozulemeyen ya da baglami tutmayan sinyal aramaya ulasmaz.
      await _report('call-signal.decrypt', error, stackTrace);
      return null;
    }
  }

  Future<void> _report(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    try {
      // Raporlayici tur ve baglami kaydeder; SDP ya da anahtar yazilmaz.
      await _onFailure?.call(operation, error, stackTrace);
    } catch (_) {
      // Teshis hatasi sinyal akisini durdurmamali.
    }
  }

  @override
  Stream<SignalingStatus> get statuses => _inner.statuses;

  @override
  SignalingStatus get currentStatus => _inner.currentStatus;

  @override
  String? get currentUserId => _inner.currentUserId;

  @override
  Future<void> connect({
    required String userId,
    required String url,
    required String accessToken,
    AccessTokenProvider? tokenProvider,
    AccessTokenProvider? refreshToken,
  }) => _inner.connect(
    userId: userId,
    url: url,
    accessToken: accessToken,
    tokenProvider: tokenProvider,
    refreshToken: refreshToken,
  );

  @override
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 8),
  }) => _inner.ensureConnected(timeout: timeout);

  @override
  Future<void> retryConnection() => _inner.retryConnection();

  @override
  Future<void> onNetworkChanged({required bool isAvailable}) =>
      _inner.onNetworkChanged(isAvailable: isAvailable);

  @override
  Future<void> disconnect() => _inner.disconnect();

  /// Ic baglantiyi kapatmaz; sahibi asil servistir.
  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _tail;
    await _incoming?.close();
  }
}
