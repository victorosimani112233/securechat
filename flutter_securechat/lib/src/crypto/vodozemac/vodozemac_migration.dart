import '../../storage/secure_chat_database.dart';

/// libsignal kripto durumundan vodozemac'a tek seferlik gecis.
///
/// NEDEN VERI SILINIYOR: diskteki `record` blob'lari legacy Java libsignal
/// protobuf duzeninde. vodozemac'in `SessionPickle` / `AccountPickle` bicimi
/// baska bir yapi; bu kayitlar okunamaz. Donusturmek de mumkun degil, cunku
/// iki protokolun ratchet durumu ayni sey degil.
///
/// NE SILINIR: yalniz kriptografik durum — identity, prekey, signed prekey,
/// oturumlar ve sender key'ler.
///
/// NE KORUNUR: mesaj gecmisi, konusmalar, kisiler, arama kayitlari,
/// zamanlanmis mesajlar, ayarlar. Kullanici hicbir mesajini kaybetmez.
///
/// GORUNUR SONUC: her konusma icin oturum yeniden kurulur (ilk mesajda
/// otomatik) ve her grup icin sender key yeniden dagitilir. Karsi taraf
/// kimlik degisikligi gorur; bu beklenen ve dogru davranis.
///
/// YARIDA KESILIRSE: temizlik idempotent, isaret EN SON yazilir. Yani
/// kesilmis bir gecis sonraki acilista bastan kosar ve ayni sonuca varir.
class VodozemacMigration {
  const VodozemacMigration(this._database);

  /// Gecisin bir daha kosmamasi icin yazilan isaret.
  static const markerKey = 'vodozemac_migration_v1';

  final SecureChatDatabase _database;

  /// Gecis gerekli mi.
  Future<bool> isPending() async =>
      await _database.cryptoState.get(markerKey) == null;

  /// Gecisi kosar. Daha once kosmussa hicbir sey yapmaz.
  ///
  /// @return gecis bu cagride kosulduysa true.
  Future<bool> runIfNeeded() async {
    if (!await isPending()) return false;

    // Cihazda vodozemac hesabi varsa gecis zaten yapilmistir: hesap ancak
    // gecisten SONRA uretilir. Isaret yine de eksik olabilir (yerel veri
    // silindi, ayni surecte yeni hesap kuruldu). O hesabi silmek, kullanicinin
    // kimligini degistirir; sunucu yeni kimligi acik kurtarma olmadan kabul
    // etmedigi icin hesap mesajlasamaz hale gelir (QA 2026-10-13 T5).
    if (await _database.vodozemacAccount.exists()) {
      await markDone();
      return false;
    }

    // Temizlik taze kurulumda da zararsiz: silinecek bir sey yoksa islem
    // bos gecer. Varligi ayrica yoklamiyoruz, cunku "legacy durum var mi"
    // sorusunun her kaynagini saymak bu kontrolu kendi basina bir hata
    // yuzeyi yapardi.
    await _database.clearCryptoProtocolState();

    // Isaret EN SON: yukarisi kesilirse gecis tekrar kosar.
    await markDone();
    return true;
  }

  /// Gecisi kosmadan "yapildi" olarak isaretler.
  ///
  /// Yerel veri tamamen silindiginde (cikis, "Farkli hesapla basla") depo
  /// bostur ve gecirilecek legacy durum yoktur; isaret de silindigi icin
  /// hemen yeniden yazilir (QA 2026-10-13 T5).
  Future<void> markDone() => _database.cryptoState.put(
    markerKey,
    DateTime.now().toUtc().toIso8601String(),
  );
}
