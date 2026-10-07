import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../storage/secure_chat_database.dart';
import '../../storage/storage_entities.dart';
import 'securechat_crypto_ffi.dart';

/// vodozemac durumunu sifreli yerel veritabaninda tutar.
///
/// NEDEN KAPANIS TABANLI API: vodozemac'ta hem anahtar uretimi hem her
/// `encrypt`/`decrypt` cagrisi durumu ILERLETIR ve degisen durum pickle'a
/// yazilmazsa kaybolur. Kaybin sonuclari sessiz ve yikicidir: sunucuya
/// yuklenen tek kullanimlik anahtarin yerel karsiligi olmaz, ya da ayni
/// mesaj anahtari ikinci kez kullanilir.
///
/// libsignal bu sorumlulugu store callback'leriyle kendisi tasiyordu.
/// Burada cagirana birakilsa "pickle'lamayi unutma" yazili bir kural olurdu;
/// bunun yerine [withAccount] ve [withSession] islem bittiginde yeniden
/// pickle'lamayi KENDISI yapar. Cagiran unutamaz.
class VodozemacProtocolStore {
  VodozemacProtocolStore({
    required SecureChatDatabase database,
    required SecureChatCrypto crypto,
    required Uint8List pickleKey,
  }) : _database = database,
       _crypto = crypto,
       _pickleKey = pickleKey {
    if (pickleKey.length != 32) {
      throw ArgumentError.value(
        pickleKey.length,
        'pickleKey',
        'pickle anahtari tam 32 bayt olmali',
      );
    }
  }

  final SecureChatDatabase _database;
  final SecureChatCrypto _crypto;
  final Uint8List _pickleKey;

  /// Pickle anahtarini cihaz master key'inden AMAC AYRIMIYLA turetir.
  ///
  /// Depolama anahtarinin kendisi kullanilmaz: ayni anahtari iki farkli amac
  /// icin kullanmak, birinin sizmasini digerinin de sizmasi yapar. Sunucu
  /// tarafindaki `PRIVACY_INDEX_KEY` / `OFFLINE_QUEUE_ENCRYPTION_KEY`
  /// ayrimiyla ayni gerekce.
  static Future<Uint8List> derivePickleKey(List<int> masterKey) async {
    final derived = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: SecretKey(masterKey),
      info: utf8.encode('securechat/vodozemac-pickle/v1'),
      nonce: const <int>[],
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Hesap var mi. Yoksa [withAccount] ilk cagrida olusturur.
  Future<bool> hasAccount() => _database.vodozemacAccount.exists();

  /// Hesabi acar, [action]'i kosar, SONRA yeniden pickle'layip saklar.
  ///
  /// Hesap yoksa olusturulur. [action] firlatirsa durum YAZILMAZ: yarim
  /// kalmis bir anahtar uretimi diske gecmez.
  Future<T> withAccount<T>(Future<T> Function(OlmAccount account) action) async {
    final pickle = await _database.vodozemacAccount.readPickle();
    final account = pickle == null
        ? _crypto.createAccount()
        : _crypto.accountFromPickle(pickle, _pickleKey);
    try {
      final result = await action(account);
      await _database.vodozemacAccount.writePickle(account.pickle(_pickleKey));
      return result;
    } finally {
      account.dispose();
    }
  }

  /// Hesabi yalniz OKUR; durum degismediginden yeniden pickle'lanmaz.
  ///
  /// Anahtar ureten veya tuketen bir cagri icin bunu KULLANMA: uretilen
  /// anahtarlar kaybolur. Sadece identity anahtari, sayac okuma ve imza
  /// gibi durumu degistirmeyen islemler icindir.
  Future<T> readAccount<T>(Future<T> Function(OlmAccount account) action) async {
    final pickle = await _database.vodozemacAccount.readPickle();
    if (pickle == null) {
      throw StateError('vodozemac hesabi henuz olusturulmadi');
    }
    final account = _crypto.accountFromPickle(pickle, _pickleKey);
    try {
      return await action(account);
    } finally {
      account.dispose();
    }
  }

  /// Bir peer icin kayitli oturumlari en son kullanilandan baslayarak doner.
  ///
  /// Olm ayni peer icin birden fazla oturuma izin verir; karsi taraf eski bir
  /// prekey ile yeni bir oturum baslatabilir. Cozme denemesi bu sirayla
  /// yapilmali.
  Future<List<String>> sessionIdsForPeer(String peerId) async {
    final sessions = await _database.vodozemacSessions.forPeer(peerId);
    return sessions.map((session) => session.sessionId).toList(growable: false);
  }

  /// Oturumu acar, [action]'i kosar, SONRA yeniden pickle'layip saklar.
  ///
  /// Ratchet'i ilerleten her islem bundan gecmeli. [action] firlatirsa durum
  /// yazilmaz; basarisiz bir cozme denemesi ratchet'i tuketmis gibi
  /// kaydedilmez.
  Future<T> withSession<T>(
    String peerId,
    String sessionId,
    Future<T> Function(OlmSession session) action,
  ) async {
    final stored = await _database.vodozemacSessions.get(peerId, sessionId);
    if (stored == null) {
      throw StateError('oturum bulunamadi: $peerId / $sessionId');
    }
    final session = _crypto.sessionFromPickle(stored.pickle, _pickleKey);
    try {
      final result = await action(session);
      await _database.vodozemacSessions.upsert(
        stored.copyWith(
          pickle: session.pickle(_pickleKey),
          lastUsedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return result;
    } finally {
      session.dispose();
    }
  }

  /// Yeni kurulmus bir oturumu saklar. Oturum cagirana ait kalir.
  Future<void> persistNewSession(String peerId, OlmSession session) =>
      _database.vodozemacSessions.upsert(
        VodozemacSessionEntity(
          peerId: peerId,
          sessionId: session.sessionId,
          pickle: session.pickle(_pickleKey),
          lastUsedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  /// Bir peer ile butun oturumlari siler. Kimlik degisiminde kullanilir.
  Future<void> deleteSessionsForPeer(String peerId) =>
      _database.vodozemacSessions.deleteForPeer(peerId);
}
