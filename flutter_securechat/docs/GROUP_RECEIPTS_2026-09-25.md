# Grup Mesajlarinda Teslim ve Okundu Bilgisi

## Sorun

Bir grup uyesinin teslim/okundu bildirimi mesajin ortak durumunu ilerletiyordu.
Mesaj bilgisi ekrani da bu ortak durumu tum uyelere uygulayarak gercekte
okumayan kisileri okunmus listesinde gosteriyordu.

## Degisiklik

- Metin, anket, dosya, gorsel ve sesli mesaj gonderilirken gercek alicilarin
  listesi mesaja kaydedilir. Gonderen kisi ve tekrar eden uyeler sayilmaz.
- Teslim ve okundu bildirimleri her alici icin ayri saklanir. Okundu bildirimi
  ayni zamanda teslim kanitidir; gec gelen teslim bildirimi okumayi geri almaz.
- Tum alicilar teslim almadan mesaj topluca teslim edildi sayilmaz. Tum
  alicilar okumadan topluca okundu sayilmaz.
- Gruptan sonradan ayrilan veya gruba yeni katilan kisiler, eski mesajin
  gonderildigi andaki alici sayisini degistirmez.
- Mesaj bilgisi bolumleri artik once "Iletildi", sonra "Okundu" siralamasindadir.
  Yalnizca gercek bildirimi alinan kisiler ve bilinen toplam icindeki sayilari
  gosterilir. Pencere acikken yeni bildirimler ekrani gunceller.
- Okundu paylasimi kapaliyken gelen READ bildirimi sadece teslim olarak
  islenir. Okundu listesi ve sayaci gizlenir.
- Kimlikler mevcut rehber adi / paylasilan telefon / bilinmeyen uye kurallariyla
  gosterilir; UUID ekrana basilmamaya devam eder.

## Guvenlik ve Uyumluluk

Bildirimler mevcut E2EE ozel kontrol mesajlariyla tasinir. Duz metin kontrol
mesajlari kabul edilmez. Bir alicinin bildirimi yalnizca o alicinin bekleyen
teslim kaydini temizler. Bilinmeyen bir gonderici mesaj durumunu ilerletemez.

Yeni alanlar cihazin mevcut sifreli mesaj deposunda ve parola korumali yedegin
icerisinde tutulur. Sunucuya yeni tablo veya metadata eklenmez. Sunucu JAR
degisikligi gerekmez; istemci guncellemesi gerekir. Android ve iOS ayni Dart
uygulamasini kullanir.

## Eski Mesajlar

Onceki surum kisi bazinda kanit saklamadigi icin eski grup mesajlarinda kimin
okudugu gecmisten cikartilamaz. Bu mesajlar icin tum grup okunmus/iletilmis
gibi gosterilmez; yalnizca sonradan gercekten alinan bireysel bildirimler
listelenir. Gonderim anindaki alici listesi bilinmiyorsa toplam uydurulmaz.

## Test Kapsami

- Iki alicidan sadece birinin okumasi; her ikisinin teslim almasi/okumasi.
- Tekrar eden ve ters sirada gelen bildirimler, eszamanli yazmalar.
- Gruptan ayrilma/katilma ve yetkisiz bildirimler.
- E2EE kontrol akisi ve alici bazinda bekleyen gonderim temizligi.
- Okundu gizliligi ve birebir sohbetlerin mevcut davranisi.
- Depoyu yeniden acma, JSON/yedek uyumlulugu, eski kayitlar.
- Metin/anket ve medya/sesli mesajlarin gonderim anindaki alici listesi.
- Acik mesaj bilgisi penceresinin canli yenilenmesi, bolum sirasi ve etiketler.

Yerel otomatik testler gercek uc cihazli uctan uca testin veya iOS derlemesinin
yerine gecmez; bunlar bu duzeltmenin otomatik test kapsamindan ayridir.

### Yerel Dogrulama Notlari

- Degisiklige odakli bes test dosyasinda 64 test gecti.
- Son genel tur: `flutter test --no-pub --concurrency=4`, 1107 test gecti,
  cikis kodu 0 (2 dakika 42 saniye). Ilk turdaki veritabani kilit hatasi
  bu turda tekrarlanmadi; ilk hata yukarida belirtilen kapsamdan bagimsiz bir
  eszamanlilik riski olarak kayit altinda tutuldu.
- `dart format --output=none --set-exit-if-changed`: 13 dosya, degisiklik yok.
- `git diff --check`: temiz.
- `flutter analyze --no-pub` kod uyarisi raporlamadi ancak analiz sunucusu
  `Too many open files` hatasiyla cikis 1 verdi. Bu nedenle temiz analiz olarak
  kabul edilmedi.
- Varsayilan paralellikteki genel test turunda mevcut
  `cross_runtime_database_test` eszamanli yazma senaryosu bir kez
  `database is locked` verdi. Bu senaryo bos mesaj depolu birebir sohbet
  kullaniyor; eski grup mesaji normalizasyonu o veride degisiklik yapmiyor.
  Ilk hatanin tek basina zararsiz oldugu varsayilmadi; daha dusuk paralellikle
  genel test paketi tekrar calistirildi.
