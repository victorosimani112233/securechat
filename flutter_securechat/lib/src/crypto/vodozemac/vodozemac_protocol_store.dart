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

  /// Hesabin Ed25519 imzalama acik anahtari (base64, ham 32 bayt), ya da
  /// hesap yoksa null.
  ///
  /// Hesap kurtarma kimligi ARTIK bu anahtar: sunucu `users.signing_public_key`
  /// olarak pinler ve kurtarma kanitini bu anahtarla dogrular. Mesaj kriptosu
  /// zaten ayni Olm hesabini kullandigi icin kurtarma icin ayri bir kimlik
  /// uretilmez. Durum degismez, bu yuzden [readAccount].
  Future<String?> recoverySigningPublicKey() async {
    if (!await hasAccount()) return null;
    return readAccount((account) async => account.identityKeys()['ed25519']!);
  }

  /// Kurtarma kanitini hesabin Ed25519 anahtariyla imzalar (base64 imza).
  ///
  /// vodozemac standart Ed25519 uretir; sunucu JDK Ed25519 ile dogrular.
  /// Imzalama durumu ilerletmez, bu yuzden [readAccount].
  Future<String> signRecoveryProof(String message) =>
      readAccount((account) async => account.sign(utf8.encode(message)));

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

  // -------------------------------------------------------------------------
  // Megolm — grup oturumlari
  // -------------------------------------------------------------------------

  /// Grup icin giden oturumu acar, [action]'i kosar, SONRA yeniden
  /// pickle'layip saklar. Oturum yoksa olusturulur.
  ///
  /// Her `encrypt` mesaj indeksini ilerletir ve yazilmazsa ayni indeks tekrar
  /// kullanilir; o yuzden kaydetme burada, cagirana birakilmadan yapilir.
  Future<T> withGroupSession<T>(
    String groupId,
    Future<T> Function(MegolmGroupSession session) action,
  ) async {
    final stored = await _database.vodozemacGroupSessions.get(groupId);
    final session = stored == null
        ? _crypto.createGroupSession()
        : _crypto.groupSessionFromPickle(stored.pickle, _pickleKey);
    try {
      final result = await action(session);
      await _database.vodozemacGroupSessions.upsert(
        VodozemacGroupSessionEntity(
          groupId: groupId,
          sessionId: session.sessionId,
          pickle: session.pickle(_pickleKey),
        ),
      );
      return result;
    } finally {
      session.dispose();
    }
  }

  /// Grubun giden oturumunu siler; sonraki [withGroupSession] yenisini kurar.
  /// Uye cikarmada kullanilir: ayrilan uye yeni mesajlari cozememeli.
  Future<void> resetGroupSession(String groupId) =>
      _database.vodozemacGroupSessions.delete(groupId);

  /// Bir gonderenden gelen oturum anahtarini kaydeder.
  ///
  /// libsignal'daki `processSenderKeyDistribution` karsiligi.
  Future<void> acceptGroupSessionKey({
    required String groupId,
    required String senderId,
    required String sessionKey,
  }) async {
    final session = _crypto.inboundGroupSession(sessionKey);
    try {
      final existing = await _database.vodozemacInboundGroupSessions.get(
        groupId,
        senderId,
        session.sessionId,
      );
      // Ayni oturum tekrar dagitilirsa gorulen indeksi SIFIRLAMA: aksi halde
      // dagitimi tekrar gondermek replay korumasini devre disi birakmanin
      // yolu olurdu.
      if (existing != null) return;
      await _database.vodozemacInboundGroupSessions.upsert(
        VodozemacInboundGroupSessionEntity(
          groupId: groupId,
          senderId: senderId,
          sessionId: session.sessionId,
          pickle: session.pickle(_pickleKey),
          highestMessageIndex: -1,
        ),
      );
    } finally {
      session.dispose();
    }
  }

  /// Grup mesajini cozer ve REPLAY'i reddeder.
  ///
  /// Megolm bir oturumda her plaintext'i tek bir indeksle sifreler, yani ayni
  /// indeksin ikinci kez gorulmesi tekrar oynatmadir. vodozemac bunu kendisi
  /// takip etmiyor; gorulen en yuksek indeks saklanir ve burada kontrol
  /// edilir. Kontrolu cagirana birakmak, unutuldugunda sessizce replay'e
  /// acik bir sistem verirdi.
  ///
  /// @throws StateError oturum bilinmiyorsa veya mesaj replay ise.
  Future<Uint8List> decryptGroupMessage({
    required String groupId,
    required String senderId,
    required String sessionId,
    required String message,
  }) async {
    final stored = await _database.vodozemacInboundGroupSessions.get(
      groupId,
      senderId,
      sessionId,
    );
    if (stored == null) {
      throw StateError(
        'grup oturumu bilinmiyor: $groupId / $senderId / $sessionId',
      );
    }
    final session = _crypto.inboundGroupSessionFromPickle(
      stored.pickle,
      _pickleKey,
    );
    try {
      final decrypted = session.decrypt(message);
      if (decrypted.messageIndex <= stored.highestMessageIndex) {
        throw StateError(
          'replay reddedildi: indeks ${decrypted.messageIndex}, '
          'gorulen en yuksek ${stored.highestMessageIndex}',
        );
      }
      await _database.vodozemacInboundGroupSessions.upsert(
        stored.copyWith(
          pickle: session.pickle(_pickleKey),
          highestMessageIndex: decrypted.messageIndex,
        ),
      );
      return decrypted.plaintext;
    } finally {
      session.dispose();
    }
  }

  /// Bir grubun butun gelen oturumlarini siler.
  Future<void> deleteGroupSessions(String groupId) async {
    await _database.vodozemacGroupSessions.delete(groupId);
    await _database.vodozemacInboundGroupSessions.deleteForGroup(groupId);
  }
}
