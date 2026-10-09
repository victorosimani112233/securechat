import 'dart:convert';
import 'dart:typed_data';

import '../../services/crypto_service.dart';
import '../../services/peer_identity_review_service.dart';
import '../../storage/secure_chat_database.dart';
import '../../storage/storage_entities.dart';
import 'securechat_crypto_ffi.dart';
import 'vodozemac_protocol_store.dart';

/// Karsi tarafin oturum kurmak icin gereken acik anahtarlari.
///
/// libsignal'daki `PreKeyBundle` karsiligi. Olm'da signed prekey yerine
/// fallback key var ve imza dogrulamasi protokole gomulu degil; kimlik
/// dogrulamasi TOFU pinlemesiyle yapilir (bkz. [PeerIdentityReview]).
class OlmPreKeyBundle {
  const OlmPreKeyBundle({
    required this.identityKey,
    required this.signingKey,
    required this.oneTimeKey,
  });

  /// Curve25519 acik anahtari, base64. Oturum kurmak icin.
  final String identityKey;

  /// Ed25519 acik anahtari, base64. Imzalama kimligi.
  final String signingKey;

  /// Tek kullanimlik Curve25519 anahtari, base64.
  final String oneTimeKey;

  /// TOFU pinlemesinde kullanilan kimlik baytlari.
  ///
  /// IKI ANAHTAR BIRLIKTE pinlenir. Yalniz birini pinlemek digerini
  /// degistirilebilir birakirdi: Curve25519 oturum kurulumunu, Ed25519
  /// imzalamayi tasiyor ve ikisi de kimligin parcasi.
  Uint8List get identityBytes => Uint8List.fromList([
    ...base64Decode(base64.normalize(signingKey)),
    ...base64Decode(base64.normalize(identityKey)),
  ]);
}

abstract interface class OlmPreKeyBundleProvider {
  Future<OlmPreKeyBundle?> fetch(String recipientId);
}

/// Peer basina siraya alan kilit.
///
/// Ayni peer icin es zamanli iki islem ratchet durumunu yarisa sokar.
/// Eski libsignal servisindeki ayni desen; o dosya silinecegi icin kopyasi
/// burada tutuluyor.
class _AsyncKeyedMutex {
  final Map<String, Future<void>> _tails = {};

  Future<T> protect<T>(String key, Future<T> Function() operation) {
    final previous = _tails[key] ?? Future<void>.value();
    final ready = previous.then<void>((_) {}, onError: (_, _) {});
    final result = ready.then<T>((_) => operation());
    final tail = result.then<void>((_) {}, onError: (_, _) {});
    _tails[key] = tail;
    tail.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }
}

/// Uretim mesaj kriptografisi — vodozemac (Olm + Megolm) uzerinde.
///
/// Yerel veritabani sarmalama [LocalAeadCryptoService]'te kalir; bu sinif
/// yalniz peer ve grup KABLO mesajlari icindir.
///
/// DUZ METIN GERI DONUSU YOKTUR: sifreleme, oturum veya bundle hatasinda
/// islem basarisiz olur ve mesaj gonderilmez.
class VodozemacCryptoService
    implements
        CryptoService,
        GroupCryptoService,
        PeerSessionRecovery,
        PeerIdentityReviewService {
  VodozemacCryptoService({
    required SecureChatDatabase database,
    required VodozemacProtocolStore store,
    required OlmPreKeyBundleProvider preKeyBundles,
    PeerIdentityRotationHandler? onPeerIdentityRotated,
  }) : _database = database,
       _store = store,
       _preKeyBundles = preKeyBundles,
       _onPeerIdentityRotated = onPeerIdentityRotated;

  /// Direct zarf: `OLM:v1:<tip>:<base64>`; tip 0 = PreKey, 1 = mesaj.
  static const directPrefix = 'OLM:v1:';

  /// Grup zarfi: `MEGOLM:v1:<routingToken>:<sessionId>:<base64>`.
  ///
  /// `sessionId` ZORUNLU: Megolm mesaji hangi oturuma ait oldugunu kendi
  /// icinde tasimiyor, alici tarafin dogru gelen oturumu secebilmesi icin
  /// kabloda tasinmasi gerekiyor. libsignal'da bu bilgi
  /// `SenderKeyDistributionMessage.id` idi.
  static const groupPrefix = 'MEGOLM:v1:';

  /// Dagitim zarfi: `SKDM:v2:<groupId>:<base64 sessionKey>`.
  ///
  /// `groupId` acik tasinir ama bu zarf her alici icin AYRI ayri direct
  /// Olm kanalindan gonderilir; sunucu icerigini goremez.
  static const distributionPrefix = 'SKDM:v2:';

  final SecureChatDatabase _database;
  final VodozemacProtocolStore _store;
  final OlmPreKeyBundleProvider _preKeyBundles;
  final PeerIdentityRotationHandler? _onPeerIdentityRotated;
  final _operations = _AsyncKeyedMutex();
  final _issuedReviews = Expando<bool>();

  // -------------------------------------------------------------------------
  // Kimlik incelemesi — TOFU
  // -------------------------------------------------------------------------

  @override
  Future<PeerIdentityReview> reviewPeerIdentity(String peerId) =>
      _operations.protect('direct:$peerId', () async {
        final bundle = await _requireBundle(peerId);
        final previous = await _database.identities.get(peerId);
        final local = await _localIdentityBytes();
        final review = PeerIdentityReview(
          peerId: peerId,
          previousIdentity: previous?.identityKey,
          currentIdentity: bundle.identityBytes,
          localIdentity: local,
        );
        _issuedReviews[review] = true;
        return review;
      });

  @override
  Future<void> approvePeerIdentity(PeerIdentityReview review) =>
      _operations.protect('direct:${review.peerId}', () async {
        // Yalniz bu ornegin urettigi anlik goruntu bir degisikligi
        // yetkilendirebilir.
        if (_issuedReviews[review] != true) {
          throw const PeerIdentityReviewStaleException();
        }
        _issuedReviews[review] = null;
        final bundle = await _requireBundle(review.peerId);
        final previous = await _database.identities.get(review.peerId);
        final local = await _localIdentityBytes();
        if (!identityBytesEqual(bundle.identityBytes, review.currentIdentity) ||
            !identityBytesEqual(previous?.identityKey, review.previousIdentity) ||
            !identityBytesEqual(local, review.localIdentity)) {
          throw const PeerIdentityReviewStaleException();
        }
        await _database.identities.insert(
          IdentityEntity(
            addressName: review.peerId,
            identityKey: List<int>.from(review.currentIdentity),
            trustLevel: TrustLevel.trustedVerified,
          ),
        );
        // Eski kimlige bagli oturumlar yeni kimlikle gecerli degil. Kimlik
        // DEGISMEDIYSE (kullanici guvenlik numarasini yalnizca dogruladi)
        // oturum saglamdir ve korunur: silmek, karsi tarafin eski oturumla
        // yolda olan mesajlarini cozulemez yapardi.
        if (review.identityChanged) {
          await _store.deleteSessionsForPeer(review.peerId);
        }
      });

  Future<Uint8List> _localIdentityBytes() => _store.withAccount((account) async {
    final keys = account.identityKeys();
    return Uint8List.fromList([
      ...base64Decode(base64.normalize(keys['ed25519']!)),
      ...base64Decode(base64.normalize(keys['curve25519']!)),
    ]);
  });

  Future<OlmPreKeyBundle> _requireBundle(String peerId) async {
    final bundle = await _preKeyBundles.fetch(peerId);
    if (bundle == null) throw StateError('Peer prekeys are unavailable');
    return bundle;
  }

  // -------------------------------------------------------------------------
  // Oturum yasam dongusu
  // -------------------------------------------------------------------------

  /// [force] verilirse mevcut oturumlar gecersiz sayilir: once silinir, sonra
  /// taze bir bundle ile yenisi kurulur. Bozuk oturumdan kurtulmanin tek yolu
  /// budur; aksi halde var olan oturum sonsuza kadar kullanilmaya devam eder.
  Future<bool> ensureSession(String recipientId, {bool force = false}) =>
      _operations.protect(
        'direct:$recipientId',
        () => _ensureSessionUnlocked(recipientId, force: force),
      );

  Future<bool> _ensureSessionUnlocked(
    String recipientId, {
    bool force = false,
  }) async {
    if (force) {
      await _store.deleteSessionsForPeer(recipientId);
    } else if ((await _store.sessionIdsForPeer(recipientId)).isNotEmpty) {
      return true;
    }
    final bundle = await _preKeyBundles.fetch(recipientId);
    if (bundle == null) return false;

    // Kimlik degisimi bir liveness olayi degil, guven karari. Sunucudan gelen
    // yeni bundle eski TOFU pinini otomatik silemez; once kullanici onayi
    // gerekir.
    final pinned = await _database.identities.get(recipientId);
    if (pinned != null &&
        !identityBytesEqual(pinned.identityKey, bundle.identityBytes)) {
      await _onPeerIdentityRotated?.call(recipientId);
      throw PeerIdentityChangedException(recipientId);
    }
    if (pinned == null) {
      await _database.identities.insert(
        IdentityEntity(
          addressName: recipientId,
          identityKey: List<int>.from(bundle.identityBytes),
          trustLevel: TrustLevel.trustedUnverified,
        ),
      );
    }

    await _store.withAccount((account) async {
      final session = account.createOutboundSession(
        theirIdentityKey: bundle.identityKey,
        theirOneTimeKey: bundle.oneTimeKey,
      );
      try {
        await _store.persistNewSession(recipientId, session);
      } finally {
        session.dispose();
      }
    });
    return true;
  }

  @override
  Future<void> resetPeerSession(String peerId) => _operations.protect(
    'direct:$peerId',
    () => _store.deleteSessionsForPeer(peerId),
  );

  @override
  Future<bool> rebuildPeerSession(String peerId) =>
      _operations.protect('direct:$peerId', () async {
        await _store.deleteSessionsForPeer(peerId);
        return _ensureSessionUnlocked(peerId, force: true);
      });

  /// Hatanin oturumun kullanilamaz oldugunu mu gosterdigini siniflandirir.
  ///
  /// Sinif native taraftan TIPLI gelir; hata metnine bakilmaz. Tekrar teslim
  /// edilen cerceve ([CryptoErrorKind.missingMessageKey]) bilerek disarida:
  /// saglikli bir oturumda da olagandir ve oturumu sifirlamak, tekrar
  /// oynatilan tek bir cerceveyle oturumu yok etme imkani verirdi.
  static bool indicatesUnusableSession(Object error) =>
      error is SecureChatCryptoException &&
      error.kind.indicatesUnusableSession;

  // -------------------------------------------------------------------------
  // Direct mesajlar
  // -------------------------------------------------------------------------

  @override
  Future<String> encryptDirect({
    required String recipientId,
    required String plaintext,
  }) => _operations.protect('direct:$recipientId', () async {
    if (!await _ensureSessionUnlocked(recipientId)) {
      throw StateError('Signal session could not be established: $recipientId');
    }
    final sessionIds = await _store.sessionIdsForPeer(recipientId);
    if (sessionIds.isEmpty) {
      throw StateError('Signal session could not be established: $recipientId');
    }
    final envelope = await _store.withSession(
      recipientId,
      sessionIds.first,
      (session) async =>
          session.encrypt(Uint8List.fromList(utf8.encode(plaintext))),
    );
    return '$directPrefix${envelope.type}:${envelope.body}';
  });

  @override
  Future<String> decryptDirect({
    required String senderId,
    required String envelope,
  }) => _operations.protect('direct:$senderId', () async {
    if (!envelope.startsWith(directPrefix)) {
      throw FormatException('Unsupported Olm envelope', envelope);
    }
    final rest = envelope.substring(directPrefix.length);
    final separator = rest.indexOf(':');
    if (separator < 1) {
      throw FormatException('Unsupported Olm envelope', envelope);
    }
    final type = int.tryParse(rest.substring(0, separator));
    final body = rest.substring(separator + 1);
    if (type != OlmEnvelope.preKeyType && type != OlmEnvelope.messageType) {
      throw FormatException('Unknown Olm envelope type', envelope);
    }
    final message = OlmEnvelope(type: type!, body: body);

    // Bilinen oturumlar en yeniden baslayarak denenir. Olm ayni peer icin
    // birden fazla oturuma izin verdigi icin dogru oturumu kablo
    // soylemiyor; denemek gerekiyor. Basarisiz deneme durumu YAZMAZ.
    Object? lastError;
    SecureChatCryptoException? duplicate;
    for (final sessionId in await _store.sessionIdsForPeer(senderId)) {
      try {
        final plaintext = await _store.withSession(
          senderId,
          sessionId,
          (session) async => session.decrypt(message),
        );
        return utf8.decode(plaintext);
      } on SecureChatCryptoException catch (error) {
        lastError = error;
        // Var olan bir oturumun "anahtar tuketilmis" demesi BELIRLEYICI:
        // cerceve tekrar teslim edilmis ya da sirasiz gelmis demektir ve
        // oturum saglamdir. Asagidaki PreKey denemesi basarisiz olup daha
        // agir bir sinif dondurse bile bu karar ezilmemeli, yoksa tekrar
        // oynatilan tek bir cerceve oturumu yok etmeye yeterdi.
        if (error.kind == CryptoErrorKind.missingMessageKey) {
          duplicate = error;
        }
      }
    }

    // PreKey mesaji bilinen bir oturuma uymadiysa yeni gelen oturum kurar.
    // Olm, karsi taraftan cevap gelene kadar PreKey tipi uretmeye devam
    // ettigi icin tekrar teslim edilen cerceveler de buraya dusebilir; o
    // durumda tek kullanimlik anahtar tuketilmis oldugundan kurulum
    // basarisiz olur ve bu bir oturum hatasi DEGILDIR.
    if (message.isPreKey && duplicate == null) {
      try {
        return await _acceptInboundSession(senderId, message.body);
      } on SecureChatCryptoException catch (error) {
        if (error.kind == CryptoErrorKind.identityMismatch) {
          // Gonderen pinlenen kimlikten FARKLI bir kimlikle oturum kurmaya
          // calisiyor (yeni cihaz ya da araya giren biri). Bu bir guven
          // karari: kullaniciya bildirilir ve onay beklenir. Mevcut
          // oturumlar SAGLAM ve korunur; silmek, tek bir mesajla saglikli
          // oturumu yok etmeye izin verirdi. Hesap durumu degismedigi icin
          // onaydan sonra ayni zarf cozulebilir.
          await _onPeerIdentityRotated?.call(senderId);
          throw PeerIdentityChangedException(senderId);
        }
        lastError = error;
      }
    }

    if (duplicate != null) throw duplicate;

    final error = lastError;
    if (error == null) {
      // Hic oturum yok ve PreKey de degil: gonderenin yeni bir oturum
      // kurmasi gerekiyor.
      await _store.deleteSessionsForPeer(senderId);
      throw SignalSessionUnusableException(
        peerId: senderId,
        cause: StateError('no Olm session for $senderId'),
      );
    }
    if (!indicatesUnusableSession(error)) throw error;
    // Oturum olu: bir daha kullanilmasin diye silinir, boylece sonraki
    // gonderim taze bir bundle ile bastan kurar.
    await _store.deleteSessionsForPeer(senderId);
    throw SignalSessionUnusableException(peerId: senderId, cause: error);
  });

  Future<String> _acceptInboundSession(
    String senderId,
    String preKeyBody,
  ) async {
    final pinned = await _database.identities.get(senderId);
    if (pinned == null) {
      // Gonderenin kimligi henuz bilinmiyor; bundle'dan ogrenip pinlemek
      // gerekiyor, aksi halde oturum kurulamaz.
      final bundle = await _preKeyBundles.fetch(senderId);
      if (bundle == null) {
        throw StateError('Peer prekeys are unavailable');
      }
      await _database.identities.insert(
        IdentityEntity(
          addressName: senderId,
          identityKey: List<int>.from(bundle.identityBytes),
          trustLevel: TrustLevel.trustedUnverified,
        ),
      );
    }
    final identity = await _database.identities.get(senderId);
    // Pinlenen kimlik ed25519 || curve25519; oturum kurulumu ikinci yariyi
    // kullanir.
    final curve = base64Encode(identity!.identityKey.sublist(32));
    return _store.withAccount((account) async {
      final result = account.createInboundSession(
        theirIdentityKey: curve,
        preKeyMessageBase64: preKeyBody,
      );
      try {
        await _store.persistNewSession(senderId, result.session);
        return utf8.decode(result.plaintext);
      } finally {
        result.session.dispose();
      }
    });
  }

  // -------------------------------------------------------------------------
  // Grup mesajlari — Megolm
  // -------------------------------------------------------------------------

  /// Grubun oturum anahtarini dagitim zarfi olarak uretir.
  ///
  /// Zarf her alici icin AYRI direct Olm kanalindan gonderilir.
  Future<String> createSenderKeyDistribution({
    required String groupId,
    required String senderId,
  }) => _operations.protect('group:$groupId', () async {
    final sessionKey = await _store.withGroupSession(
      groupId,
      (session) async => session.sessionKey,
    );
    return '$distributionPrefix$groupId:$sessionKey';
  });

  Future<void> processSenderKeyDistribution({
    required String senderId,
    required String plaintext,
  }) async {
    if (!plaintext.startsWith(distributionPrefix)) {
      throw const FormatException('Invalid sender-key distribution envelope');
    }
    final rest = plaintext.substring(distributionPrefix.length);
    final separator = rest.indexOf(':');
    if (separator < 1) {
      throw const FormatException('Invalid sender-key distribution envelope');
    }
    final groupId = rest.substring(0, separator);
    final sessionKey = rest.substring(separator + 1);
    await _operations.protect(
      'group:$groupId',
      () => _store.acceptGroupSessionKey(
        groupId: groupId,
        senderId: senderId,
        sessionKey: sessionKey,
      ),
    );
  }

  @override
  Future<String> encryptGroup({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) => encryptGroupWire(
    senderId: senderId,
    groupId: groupId,
    plaintext: plaintext,
  );

  Future<String> encryptGroupWire({
    required String senderId,
    required String groupId,
    required String plaintext,
  }) => _operations.protect('group:$groupId', () async {
    final result = await _store.withGroupSession(groupId, (session) async {
      final ciphertext = session.encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
      );
      return (sessionId: session.sessionId, ciphertext: ciphertext);
    });
    final routingToken = await groupRoutingToken(groupId);
    return '$groupPrefix$routingToken:${result.sessionId}:${result.ciphertext}';
  });

  @override
  Future<String> decryptGroup({
    required String senderId,
    required String groupId,
    required String envelope,
  }) => _operations.protect('group:$groupId', () async {
    if (!envelope.startsWith(groupPrefix)) {
      throw FormatException('Unsupported Megolm envelope', envelope);
    }
    final parts = envelope.substring(groupPrefix.length).split(':');
    if (parts.length != 3) {
      throw FormatException('Unsupported Megolm envelope', envelope);
    }
    if (parts[0] != await groupRoutingToken(groupId)) {
      throw FormatException('Megolm envelope routing mismatch', envelope);
    }
    final plaintext = await _store.decryptGroupMessage(
      groupId: groupId,
      senderId: senderId,
      sessionId: parts[1],
      message: parts[2],
    );
    return utf8.decode(plaintext);
  });

  /// Grubun giden oturumunu atar; sonraki gonderim yeni anahtar uretir ve
  /// yeniden dagitim gerektirir. Uye cikarmada kullanilir.
  Future<void> resetLocalSenderKey(String groupId, String senderId) =>
      _operations.protect(
        'group:$groupId',
        () => _store.resetGroupSession(groupId),
      );
}

/// Pinlenen kimlik ile sunucudan gelen kimlik uyusmuyor.
///
/// Fail-closed: oturum kurulmaz ve mesaj gonderilmez. Yeni kimlik ancak
/// [PeerIdentityReviewService.approvePeerIdentity] ile kabul edilir.
class PeerIdentityChangedException implements Exception {
  const PeerIdentityChangedException(this.peerId);

  final String peerId;

  @override
  String toString() => 'PeerIdentityChangedException($peerId)';
}
