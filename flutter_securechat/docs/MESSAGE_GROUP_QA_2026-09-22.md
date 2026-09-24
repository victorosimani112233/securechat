# Mesaj, bildirim ve grup duzeltmeleri - 22 Eylul 2026

## Kapsam ve durum

Orijinal Android/Kotlin uygulamasi degistirilmedi. Istemci degisiklikleri
`flutter_securechat` icinde; grup aramasi sunucu degisiklikleri bu dizinin
`server_hardened/signaling-server` agacindadir. Canli sunucuya otomatik
yukleme yapilmadi. Asagidaki otomatik testler gercek iki cihazli arama
veya iOS native derlemesi yerine gecmez.

| Istek | Degisiklik / durum |
| --- | --- |
| Uygulama acikken bildirim | Yalnizca ekranda gorunen, kilidi acilmis ilgili sohbet bildirimi bastirir. Kisi bilgisi, diger sohbet ve arka plan gorunur sohbet sayilmaz. |
| Sohbet sekmesinde sayac | Tum sohbetlerin okunmamis mesaj toplami rozetle gosterilir; okuma ve temizleme ile guncellenir. |
| Icerigi gizli bildirim ozeti | Mesaj ve farkli sohbet sayilari birlikte yazilir. Gizli bildirimde sohbet kimligi/payload yer almaz. Gosterme ve temizleme islemleri siralandi. |
| Tek reaction | Kullanici/mesaj basina tek emoji tutulur. Farkli emoji oncekinin yerini alir; ayni emoji tekrar secilirse kalkar. Eski cift kayitlar da tek gosterilir. |
| Tek gosterimlik gorsel aciklamasi | Aciklama sifreli aktarimda korunur ve medya acildiginda gorunur. Uzun aciklama kaydirilir. |
| Tek gosterimlik icerigin gizliligi | Arama, ortak medya/belgeler/yildizli listeleri ve sohbet son-mesaj ozetinden cikarildi. Eski ozet kayitlari acilista onarilir. |
| Arama eslesmeleri | Yalnizca gorunen metin, normal medya aciklamasi, belge adi ve anket soru/secenekleri aranir. Dosya yolu, oy veren kimligi, ses/arama teknik kaydi ve suresi dolmus icerik aranmaz. |
| Medya onizlemeleri | Fotograf izgara onizlemesi ve yerel video kareleri eklendi. Korunan tek gosterimlik dosyada decoder bile cagrilmaz. |
| Grup aramasi | Katilma, mesh teklif/cevap siralamasi, anahtar hazirligi, gercek baglanti durumu ve sunucu kabul akisi duzeltildi. Canli test bekliyor; ayrinti ayri raporda. |
| Sesli mesaj durumu | Kayit aktarimdan once olusturulur; hizli teslim ACK'i kaybolmaz. Gonderildi/teslim/okundu/basarisiz durumu sohbet ozetine yansir. |
| Grup medya/belgeleri | Grup bilgilerinde ortak medya, belge, arama ve yildizli girisleri var. Secilen kayit ilgili sohbet mesajina doner. |
| Grup sohbetini sil | Uyari sonrasinda yalnizca yerel mesaj gecmisi temizlenir. Grup, uyeler, yoneticiler ve ayarlar korunur; sunucuya gruptan ayril istegi gitmez. |
| Mevcut hesaba giris | TAMAMLANMADI. Sunucuda e-posta/hesap kurtarma baglantisi yok. Ilgisiz e-posta OTP'si ile baska hesaba giris acilmadi; calismayan giris dugmesi eklenmedi. |

## Dosya ve kararlar

- `notifications/message_notification_service.dart`, `widgets/main_shell.dart`,
  `features/chat/chat_screen.dart`: gorunurluk sahipligi, sirali bildirim,
  okunmamis rozet ve okunma korumasi. Gec gelen eski tarihli mesaj icin sadece
  son mesaj kimligine bakmak yeterli degildi; gelen mesaj kimlikleri izleniyor.
- `chat/message_reactions.dart`, `message_interaction_service.dart`,
  `incoming/incoming_message_handler.dart`, `storage/secure_chat_database.dart`:
  tek reaction ve atomik degisim. Eszamanli baska kullanicinin oyu ezilmez.
- `chat/message_search.dart`, `core/models.dart`, veri deposu ve repository:
  gorunur icerik arama politikasi; tek gosterimlik, silinmis ve suresi dolmus
  kayitlarin haric tutulmasi. Dosya adindan klasor kismi da ayiklanir.
- `media/media_message_service.dart`, `features/chat/media_viewer_screen.dart`:
  gonderim durumu sirasi, gizli ozet ve medya aciklamasi.
- `features/chat/shared_content_browser.dart`, kisi/grup bilgi ekranlari,
  `app.dart`: ortak icerik gorunumu ve mesaja donus sonucu.
- `widgets/local_video_thumbnail.dart`, `platform/native_bridge.dart`, Android
  `MainActivity.kt`, iOS `AppDelegate.swift`: en fazla 320px video karesi,
  sinirli decoder kuyrugu, yalniz uygulamanin medya dizini, kaynak temizligi.
  Kalici thumbnail dosyasi veya yeni paket eklenmedi. iOS'ta AVAssetImageGenerator,
  Android'de MediaMetadataRetriever kullanilir. iOS kodu Linux'ta derlenmedi.
  Galeri fotograflari `LocalImageView` icinde en fazla 384x384 decode
  boyutuna, en-boy orani korunarak sinirlanir; tam ekran gorsel degismez.
- `features/conversations/conversations_screen.dart`, repository/veri deposu:
  grup gecmisi temizleme onayi ve uyeligi koruma.
- `auth/` ve kayit ekrani: belirsiz/eski kayit cevaplarini reddetme,
  yedekten gelen kimligi yeni UUID ile ezmeme, OTP ile kurulum hatalarini ayirma.
  Kurtarma/giris eksigi icin [ayri inceleme](AUTH_EXISTING_ACCOUNT_LOGIN.md).
- Grup aramasi dosyalari, sunucu gereksinimleri ve test sinirlari:
  [grup aramasi raporu](GROUP_CALL_FAILURES_2026-09-22.md).

## Dogrulama

- Ilk tam Flutter turu: 688 test gecti.
- Ikinci tam Flutter turu: 703 test gecti.
- Kalici okunmamis sayac entegrasyonu sonrasinda tam tur: 705 test gecti.
- Son grup SFU gecis korumasi ile tam tur: 706 test gecti. Ardindan galeri
  decode siniri ve medya aciklamasi kapsamindaki 22 test tekrar gecti.
- Statik analiz temiz; Android release on derlemesi basarili.
- Hizli teslim ACK'i ve basarisiz aktarim icin gercek sifreli veri deposu
  testleri var. Gorunmeyen sohbet, gec/sirasiz mesaj, pause/resume ve eski
  route dispose kontrolleri eklendi.
- Grup gecmisi icin onay/iptal widget testleri; medya aciklamasi icin dar ekran
  ve buyuk yazi testleri var. Bunlar gercek kamera/video decode testi degildir.
- Bagli Samsung `SM_S731B` uzerinde bildirim, mikrofon ve kamera izinlerinin
  acik oldugu goruldu. Telefon kilitli oldugundan bu asamada canli UI,
  mesajlasma ve iki cihazli arama testi tamamlanmadi. Kullanici verisi silinmedi.

### Android cihaz paketi

- `1.0.83+83` release, kullanicinin `185.22.184.114` API/WSS adresleri ve
  mevcut iki sertifika piniyle derlendi. WSS portu 443.
- Cihaz test anahtariyla v2/v3 imza dogrulamasi ve zip alignment kontrolu gecti.
  Bu anahtar production yayin anahtari olarak sunulmuyor.
- APK ZIP butunlugu kontrol edildi; kaynak tablosunda 13 `raw/elcim_*`
  ses ve `drawable/notification_icon` var. Release kaynak yolu optimizasyonu
  nedeniyle yalniz ZIP icindeki `res/raw` adlarini aramak yeterli degildir.
- iOS readiness ve Codemagic privacy audit: PASS. Bunlar native Swift/Xcode
  derlemesinin yapildigi anlamina gelmez.
- `R5GL2452S4A` cihazina `adb install -r` basarili; paket yoneticisi surum 83'u
  ve izinlerin korundugunu dogruladi (22 Eylul 18:42:49 yerel saat).
- Dosya: `build/app/outputs/flutter-apk/app-release-1.0.83-device-test-signed.apk`
- SHA-256: `5f2fd3a5cf2ccec50c76073ac2efdd37b99673a5182ca257009fd29fd07e42f0`

Son aday **1.0.84+84**: geciken mesh SDP/ICE paketlerinin SFU gecisinden sonra
aramayi kapatmasi engellendi ve fotograf onizleme decode boyutu sinirlandi.
Yeniden release derlemesi, zip alignment ve v2/v3 imza kontrolleri gecti.
Ayni telefona 22 Eylul 19:01:59'da `adb install -r` ile kuruldu; surum 84
dogrulandi. Yukaridaki 83 ara surumdur, son kurulu paket 84'tur.

- Dosya: `build/app/outputs/flutter-apk/app-release-1.0.84-device-test-signed.apk`
- SHA-256: `13d7a885ce0e2dd67a933083e92a9c9d7554fafa79942ac3dd28346b9a0a4d2e`

### Sunucu adayi

- Tam sunucu turu: 57 test grubunda 1.250 test gecti. Son paylasilan
  HttpClient duzeltmesinden sonra 78 odakli test tekrar gecti.
- Tekrar uretilebilir test JVM ayarlari:
  `server_hardened/tools/isolated-test-workers.init.gradle`.
- JAR: `server_hardened/signaling-server/build/libs/signaling-server-all.jar`.
- SHA-256: `4bf60c0c16bc40812e54f21dcb79b3575c1ae795ff7b4dbf4e6b2aa6a2e48e3b`.
- Bu paket commit edilmemis calisma agacindan derlenen test adayidir.
  Canli sunucuya yuklenmedi; migration, commit veya push yapilmadi.
- SFU varsayilan olarak kapali. Gercek Janus/TURN ve cihazlar arasi medya
  dogrulamasi otomatik protokol testlerinin yerine gecmez.

## Acik sinirlar

- Mevcut hesap girisi, guvenilir oturumdan dogrulanmis kurtarma e-postasi
  baglama ve kimlik/anahtar kurtarma karari gerektirir. Telefon numarasini
  bilmek veya herhangi bir e-postayi dogrulamak hesap sahipligi kaniti degildir.
- Ana ve arka plan bildirim koordinatorleri mevcut yerel sohbet okunmamis
  sayilarini kullanir. Isolate yeniden olusunca toplam kaybolmaz. Bildirimi
  kaydirmak mesaji okunmus yapmaz; sonraki ozet hala okunmamis mesajlari sayar.
- Yerel grup gecmisi temizleme, bu cihazdaki mesaj/veri tabani satirlaridir;
  dosya depolama yonetiminin tum fiziksel medya dosyalarini temizleme akisini
  yeniden tasarlamaz. Diger cihazlarin gecmisini silmez.
- Canli SFU/TURN kurulumu, sekiz fiziksel cihazda bant genisligi, native iOS
  derlemesi ve gercek arama sesi/goruntusu ayrica dogrulanmalidir.
