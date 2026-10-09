/// Bir gelen Megolm oturumu icin replay penceresi.
///
/// Megolm her plaintext'i oturum icinde tek bir indeksle sifreler; ayni
/// indeksin ikinci kez cozulmesi tekrar oynatmadir. vodozemac bunu kendisi
/// takip etmez, bu yuzden kayit burada tutulur.
///
/// **Neden "gorulen en yuksek indeks" yetmez.** Bir gondericinin grup
/// mesajlari SIRA DISI gelebilir: offline kuyruk bosalmasi, es zamanli
/// gonderim, yeniden deneme. Eski kontrol `indeks <= en yuksek` ise
/// reddediyordu; 2'den sonra gelen MESRU 1 replay sayilip sessizce
/// dusuruluyordu. Bu bir mesaj kaybiydi ve libsignal SenderKey (atlanmis
/// anahtarlarla) sira disini tolere ettigi icin goc regresyonuydu.
///
/// Model: [watermark] ve altindaki her indeks tuketilmis sayilir; ustundeki
/// tuketilmisler [seen] icinde. Ardisik olanlar filigrana emilir, boylece
/// sirali trafikte kume bos kalir. Kume [maxOutOfOrder]'i asarsa en eski
/// bosluk feda edilir: o kadar geride kalmis bir mesaj artik reddedilir.
/// Bellek sinirli kalir.
///
/// Eski kayitlar yalniz "en yuksek indeks" tutuyordu; filigran olarak
/// okunduklarinda davranis eskisiyle birebir aynidir.
class GroupReplayWindow {
  const GroupReplayWindow({required this.watermark, this.seen = const []});

  /// Bu ve altindaki tum indeksler tuketildi (ya da feda edildi).
  final int watermark;

  /// Filigranin ustunde tuketilmis indeksler, artan sirada.
  final List<int> seen;

  /// Filigranin ustunde tutulabilecek en fazla sira disi indeks.
  static const maxOutOfOrder = 1024;

  bool isReplay(int index) => index <= watermark || seen.contains(index);

  /// [index] tuketildikten sonraki pencere. Cagiran once [isReplay] ile
  /// kontrol etmeli.
  GroupReplayWindow accept(int index) {
    if (isReplay(index)) {
      throw StateError('replay: indeks $index zaten tuketildi');
    }
    final pending = {...seen, index}.toList()..sort();
    var mark = watermark;
    void absorb() {
      while (pending.isNotEmpty && pending.first == mark + 1) {
        mark = pending.removeAt(0);
      }
    }

    absorb();
    while (pending.length > maxOutOfOrder) {
      mark = pending.removeAt(0);
      absorb();
    }
    return GroupReplayWindow(watermark: mark, seen: List.unmodifiable(pending));
  }
}
