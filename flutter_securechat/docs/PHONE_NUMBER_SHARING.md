# Istege bagli E2EE telefon numarasi paylasimi

Tarih: 2026-09-21

## Kullanici tercihi

- Ayarlar > Gizlilik > Telefon numarami paylas.
- Varsayilan KAPALI. Eski kurulumlar da kapali baslar; kullanici onay vermeden
  acilmaz. Tercih mevcut sifreli yerel oturum dosyasinda saklanir.
- Acikken birebir metin, dosya, gorsel ve sesli mesaj gonderimi numarayi yalniz
  o aliciya iletir. Ayni birebir gonderim yolunu kullanan yonlendirme, toplu ve
  planlanmis mesajlarda da gonderim anindaki tercih gecerlidir.
- Grup gonderimi, arama, mesaj alma, yaziyor bilgisi ve okundu/teslim alindisi
  kendi basina numara paylasmaz. Ayari acmak da aninda herkese yayin yapmaz.
- Kapatmak yeni paylasimlari durdurur. Onceki onayla sifrelenip teslim
  kuyruguna alinmis bir paket veya alicinin daha once ogrendigi numara geri
  alinamaz. Alicinin rehberi, ekran goruntusu veya yerel kopyasi silinmez.
- Hesap degisiminde, cikista ve farkli hesap yedegi yuklenirken izin sifirlanir.

## Tasarim ve guvenlik sinirlari

Yeni bir sifreleme algoritmasi eklenmedi. `shared_phone`, mevcut sabit boyutlu
`CHATCTRL:v2:` kontrol paketinin icinde, uretimdeki Signal ratchet ile aliciya
ozel sifrelenir. Dis signaling JSON'una, FCM govdesine veya acik bir profil
yayinina telefon alani eklenmez. Mevcut yonlendirme metaverilerinin tamamini
gizledigi iddia edilmez.

Acik `shared_phone` signaling mesajlari islenmez. Cozulen kontrolun gonderici
ve alici kimlikleri sifreli iletim baglamindan atanir; paketin kendi kimlik
iddialarina guvenilmez. Grup kapsami reddedilir. Gonderimden hemen once izin,
hesap ve numara tekrar kontrol edilir; prekey beklerken kapatilan izinle
gonderim yapilmaz.

Bir hesabin E2EE icinde numara soylemesi, numaranin ona ait oldugunu kanitlamaz.
Yeni numara gosterilmeden once mevcut korumali rehber kesfiyle numara-hesap
eslesmesi aranir. Uretim uygulamasi blind-RSA OPRF rehber servisini kullanir;
UUID'den numara sorgulayan veya acik numara/hash gonderen geri donus eklenmedi.
Eslesen mevcut yerel rehber/sohbet kaydi varsa yeniden ag sorgusu yapilmaz.

**Bu kontrol SMS sahiplik dogrulamasi degildir.** Mevcut giris akisi e-posta
OTP'sini dogrular. Rehberdeki kayit ve hesap eslesmesi, telefon hattinin hukuki
veya fiziksel sahibini ya da kisinin gercek kimligini kanitlamaz. Sunucu rehber
kayitlarinin guvenilirligi ve mevcut Signal kimlik anahtari guven modeli
gecerlidir. Bu degisiklik bagimsiz kriptografi denetimi yerine gecmez.

Numara yalniz kanonik `+` ve 7-15 rakam biciminde kabul edilir. Uyusmayan,
bozuk veya dogrulanamayan iddia gosterilmez. Ag hatasinda acik sorguya geri
donulmez; normal mesaj islenmeye devam eder ve bilinmeyen kisi UUID olarak
kalabilir. Yeni bir eslesme dogrulamasi en fazla 5 saniye bekletir. Her calisan
servis orneginde kisi basina dakikada bir, toplamda dakikada 20 yeni dogrulama
siniri vardir. Bu, sunucu genelinde veya kalici bir saldiri siniri degildir.

Dogrulanan numara sifreli yerel sohbet kaydina yazilir; telefon rehberine
otomatik kisi eklenmez. Rehberde kullanicinin koydugu ad onceliklidir. Mevcut
mesajlar, okunmamis sayisi ve sohbet kilidi degistirilmez. Acik sohbet basligi
kimlik guncellemesini dinler. Numara ve alinan hata metni tanilara yazilmaz;
yalniz islem adi ve hata turu raporlanir.

## Uyumluluk ve maliyet

Metin mesaji govdesi degismedi. Numara bilgisi ayri, en iyi gayretle gonderilen
kontroldur; bu kontrolun hatasi normal mesaj gonderimini durdurmaz. Metin
yolunda mevcut sifreli yeniden deneme kuyrugu kullanilir; medya tanitiminda
ayri yeniden deneme yoktur. Alicida desteklenmeyen kontrol, normal mesaji
numara olmadan almaya engel olmamalidir.

Tanitim her izinli birebir gonderimde tekrarlanir. Bu, kayip/suresi dolmus
tanitimdan sonraki gonderimde toparlanmayi saglar; kalici sunucu profil tablosu
veya paylasildi varsayimi eklemez. Bedeli her gonderimde ek bir Signal paketi:
16 KiB dolgulu kontrol, Base64 ve sifreli zarf ek yuku. Dolgu tam trafik analizi
korumasi saglamaz. Dogrulanmis numarada rehber sorgusu tekrarlanmaz.

Ozelligin gorunmesi icin gonderen paylasimi acmali, alici guncel istemciyi
kullanmali ve yeni eslesme icin mevcut ozel rehber servisi calisiyor olmalidir.
Eski mesajlar geriye donuk numara icermez. Bu degisiklikte sunucu kodu,
PostgreSQL migrasyonu veya FCM payload'i degistirilmedi.

## Degisen dosyalar

- `session_store.dart`, `settings_service.dart`, `settings_screen.dart`, dort
  dilin ARB dosyalari: sifreli tercih, kapali varsayilan ve gizlilik anahtari.
- `phone_number_sharing_service.dart`: izin, sifreleme, rehber eslesmesi,
  sinirlandirilmis dogrulama ve yerel kimlik guncellemesi.
- `signal_message.dart`, `private_chat_control.dart`,
  `incoming_message_handler.dart`: yalniz E2EE icinden kabul edilen kontrol.
- `send_message_use_case.dart`, `media_message_service.dart`,
  `app_container.dart`, `background_tasks.dart`: on/arka plan baglantilari.
- `contact_service.dart`, `secure_chat_database.dart`, `models.dart`,
  `chat_screen.dart`: rehber adi onceligi, kilidi koruyan guncelleme ve baslik.

## Test kapsami

`phone_number_sharing_test.dart`, `settings_module_test.dart`,
`private_chat_control_test.dart`, `signal_protocol_crypto_service_test.dart`:
kapali varsayilan, kalicilik, hesap degisimi, gonderim sirasinda iznin iptali,
metin/dosya/sesli mesaj ve grup ayrimi, sifreli disk kaydi, acik protokol
enjeksiyonu, yanlis hesap/hash, bozuk numara, ag hatasi, sorgu butcesi, mevcut
rehber adi/kilit korunumu, dar ekran ve gercek Signal ratchet testi.

Canli iki cihaz arasi kabul testi ayridir: gonderen ayari acip yeni bir birebir
mesaj gonderir; alici rehberinde kayit yoksa numara gorunmelidir. Daha sonra
ayar kapatilip baska, numarayi onceden almamis bir aliciyla denenir. Onceki
alicidan numaranin kaybolmasini beklemek dogru bir test degildir.

Bu turdaki sonuc: 476/476 Flutter testi, statik analiz, Android release APK
derlemesi (123.3 MB) ve Codemagic gizlilik denetimi gecti. Canli iki cihaz
denemesi ve Xcode derlemesi yapilmadi. Mevcut iOS hazirlik denetimi, bu
degisiklikten onceki arama sesi metodlarini tarama eksigi nedeniyle basarisiz;
ayrinti `CALISMA_KAYDI_2026-09.md` kaydinda. APK telefona kurulmus sayilmiyor.
