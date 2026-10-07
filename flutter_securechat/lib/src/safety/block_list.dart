import '../storage/secure_chat_database.dart';

/// Engellenen kisiler yalnizca bu cihazda tutulur.
///
/// Sunucu kimin kimi engelledigini ogrenmez: grup mesajlari sunucuda
/// siradan 1:1 zarf olarak tasindigi icin sunucu tarafli bir engel grup
/// trafigini de keserdi, ayrica sunucuda bir sosyal iliski kaydi dogardi.
/// Engel bu yuzden alicida uygulanir: sifre cozme ve grup kontrolu islenir,
/// gorunur icerik, arama ve bildirim atilir.
///
/// Kayit SQLCipher'li `cryptoState` alaninda durur; ana uygulama ve arka plan
/// isolate'i ayni veritabanini okudugu icin iki tarafta da gecerlidir.
class BlockList {
  BlockList(this._state);

  final CryptoStateDao _state;

  static const _prefix = 'blocked_user:';

  Future<bool> isBlocked(String userId) async =>
      userId.isNotEmpty && await _state.get('$_prefix$userId') != null;

  /// [isBlocked]'in bekleme noktasi olmayan hali.
  bool isBlockedNow(String userId) =>
      userId.isNotEmpty && _state.getNow('$_prefix$userId') != null;

  Future<void> block(String userId) =>
      _state.put('$_prefix$userId', DateTime.now().toUtc().toIso8601String());

  Future<void> unblock(String userId) => _state.delete('$_prefix$userId');

  /// Engellenen kullanici kimlikleri, en son engellenen basta.
  Future<List<String>> all() async {
    final entries = (await _state.getByPrefix(_prefix)).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final entry in entries) entry.key.substring(_prefix.length)];
  }
}
