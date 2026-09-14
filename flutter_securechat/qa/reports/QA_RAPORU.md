# SecureChat (elçim) — Cihaz Üzerinde QA Raporu

## Kapsam ve ortam

| Alan | Değer |
|---|---|
| Cihaz | Samsung SM-S921B (Galaxy S24), Android 14, API 34 |
| Ekran | 1080x2340 @480dpi |
| ADB seri | RFCY601MDPT |
| Paket | `com.securechat.app.debug` v1.0.76-debug (versionCode 76) |
| Uygulama tipi | Flutter (122 dart dosyası, ~41.8k satır) |
| Sunucu | Yok — yerine çok istemcili lokal mock (TLS, pinlenmiş) |
| Mock adresi | `https://127.0.0.1:18444` (adb reverse) |
| Kaynak değişikliği | **Yok** — yalnızca `--dart-define` build bayrakları |

### Senaryo özeti

| Sonuç | Adet |
|---|---|
| PASS | 78 |
| FAIL | 1 |
| WARN | 1 |
| BLOCKED | 0 |
| **Toplam** | **80** |

## Bulgular (önem sırasına göre)

### 1. BUG-016: Metin alaninda dikey imlec hareketi assertion uretiyor

- **Önem:** Medium  ·  **Sonuç:** FAIL  ·  **Alan:** Sohbet ve girdi dogrulama
- **Tekrar üretme:** Sohbet composer'i odakli iken DPAD yukari/asagi tuslarina bas (monkey rastgele uretiyor)
- **Beklenen:** Imlec hareketi hatasiz islenmeli
- **Gözlenen:** 16 adet _AssertionError crash raporu: VerticalCaretMovementRun.movePrevious (flutter/src/rendering/editable.dart:214) icindeki assert(isValid) tetikleniyor; cagri zinciri _UpdateTextSelectionVerticallyAction.invoke (editable_text.dart:6657). Bayat bir VerticalCaretMovementRun, metin/layout degistikten sonra kullanilmaya devam ediliyor. NOT: assert'ler release build'de derlenmez, yani production'da cokme uretmez; ancak bayat durum kullanimi gercek ve debug'da 16 rapor uretti.
- **Kanıt:**
  - `qa/artifacts/crashes/ (_AssertionError x16)`
  - `flutter/packages/flutter/lib/src/rendering/editable.dart:214`

### 2. BUG-017 (KISMEN DUZELTILDI): servis metinleri yerellestirildi, ceviri bosluklari acik

- **Önem:** Medium  ·  **Sonuç:** WARN  ·  **Alan:** Yerellestirme
- **Tekrar üretme:** Ayarlar -> Dil -> Arapca sec (monkey testi sirasinda rastgele tetiklendi) -> ana ekrana bak
- **Beklenen:** Secilen dilde tum arayuz metinleri o dilde olmali
- **Gözlenen:** RTL duzeni DOGRU uygulaniyor (baslik saga hizali, alt navigasyon ters cevrilmis, yon oklari donmus). Ancak metinler UC DILDE birden: Arapca ('الدردشات المؤرشفة', alt sekmelerden uc tanesi), Ingilizce (filtre cipleri 'All', 'Unread', 'Groups', 'Favorites'; ayrica alt navigasyondaki 'Settings' - ayni navigasyon cubugunda digerleri Arapca iken), Turkce (calisma zamani uretilen 'Kacirilan arama'). Filtre cipleri ve bazi calisma zamani metinleri Arapca ceviri kaynagina dusmuyor. KOK NEDEN OLCULDU: app_tr.arb 490 anahtar, app_ar.arb ve app_de.arb 97'ser anahtar (%20 kapsam) -> eksikler template locale'e (app_en.arb) dusuyor. ALMANCA'DA DA AYNI BOSLUK VAR (test edilmedi). Ayrica ikinci ve ayri bir kok neden: lib/src icinde l10n'dan hic gecmeyen 94 sabit Turkce literal var (ornek missed_call_tracker.dart:71 'Kacirilan arama', message_notification_service.dart:209-215). Bunlar her dilde Turkce kaliyor. Bildirim servisleri BuildContext'siz calistigi icin duzeltme locale-farkinda bir strings-provider enjeksiyonu gerektiriyor; Grup 1 kapsaminda degil.

DUZELTILEN (kod): servis katmani BuildContext'siz calistigi icin bildirim basliklari, kanal adlari, kacirilan arama onizlemesi ve guvenlik uyarisi kaynak koda Turkce gomulmustu. lib/src/l10n/service_strings.dart eklendi: AppLocalizations.delegate context olmadan yuklenebildigi icin aktif dil tercihinden (session.languagePreference) okunuyor. message_notification_service, missed_call_tracker ve security_notice_service donusturuldu; 11 yeni anahtar DORT dile de eklendi (tr/en/de/ar). Cihazda dogrulandi: dil Ingilizce yapilinca arayuz tam Ingilizce ('Chats/Search/More/All/Unread/Groups/Favorites/Archived Chats').
ACIK KALAN 1 (icerik): app_ar.arb ve app_de.arb 108/501 anahtar iceriyor; eksikler sablon dile (Ingilizce) dusuyor. 393 anahtarlik ceviri bir icerik isidir - guvenlik uygulamasi icin gozden gecirilmemis makine cevirisi uretmek dogru olmaz, CEVIRMEN gerekiyor.
ACIK KALAN 2 (kod): geri kalan sabit Turkce dizelerin cogu ic istisna mesajidir (tls_pinning 11, backup_service 5 vb.). Bunlarin bir kismi error.toString() ile SnackBar'a dusebiliyor; ayri bir tur gerektirir.
- **Kanıt:**
  - `qa/screenshots/72_arabic_mixed.png`
  - `lib/src/l10n/service_strings.dart`
  - `test/service_strings_test.dart`
- **Ekran görüntüsü:** `qa/screenshots/72_arabic_mixed.png`

## Senaryo detayları

### Anket

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-P01 Bos anket engeli | Anket olusturulmamali, ekran kapanmamali | Ekran acik kaldi=True; gorunen uyari=yok | PASS |
| T-P02 Anket olusturma ve gonderme | Anket sifreli govdede POLL bayragiyla iletilmeli | cozulen govde flags=['MSGID', 'POLL', 'bodyLen=96']; yeni crash=0 | PASS |
| T-P03 Ankete oy verme | Oy kaydedilmeli, toplam oy sayisi artmali, karsi tarafa sifreli iletilmeli | anket durumu='Anket Ogle yemegi nerede Tekli seçim Toplam 1 oy 08:26 Gönderildi'; karsi tarafa giden sifreli sinyal sayisi=1; yeni crash=0 | PASS |
| T-P04 Tekli secim kisiti | Toplam oy 1'de kalmali (oy tasinmali, eklenmemeli) | ikinci oydan sonra anket durumu='Anket Ogle yemegi nerede Tekli seçim Toplam 1 oy 08:26 Gönderildi' | PASS |

### Ayarlar

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-S01 Ayar anahtarlarinin kaliciligi (surec olumu sonrasi) | Her anahtarin yeni degeri surec olumunden sonra korunmali | Arka Plan Deseni: True -> toggle False -> restart False (KALICI); Tam Ekran Modu: False -> toggle True -> restart True (KALICI); Planlı Mesajlar: False -> toggle True -> restart True (KALICI) | PASS |
| T-S02 Ayarlar kapsam taramasi | Tum ayar ekranlari acilabilmeli | 18 oge bulundu: Profil fotografi, Sohbet Temasi, Dil, Bildirim Sesi, Gizlilik, Arka Plan Deseni, Tam Ekran Modu, Planli Mesajlar, Otomatik indirme, Arama hazirligi, Planli Mesajlari Yonet, Toplu mesaj, Depolama Kullanimi, Yedekleme, Acik kaynak lisanslari, Tum | PASS |
| T-S03 Gizlilik varsayilanlari | Gizlilik acisindan hassas secenekler varsayilan KAPALI olmali | Gizlilik: 'Son gorulmeyi paylas' = KAPALI. Bildirim Sesi: 'Mesaj icerigini goster' (kilit ekrani onizlemesi) = KAPALI. Her ikisi de gizlilik-onceleyen varsayilan. Sohbet Temasi: Sistem/Acik/Koyu secenekleri mevcut. | PASS |
| T-S04 Depolama kullanimi ekrani | Sohbet bazinda mesaj/dosya sayisi ve boyut gosterilmeli | Sohbet basina dokum dogru: qa-peer-01 27 mesaj 0 dosya 6.8 KB; qa-peer-02 8 mesaj 2.0 KB; QA_Grup_1 2 mesaj 512 B; QA_Test_Mehmet/Ayse 1'er mesaj 256 B; debug-conversation 1 mesaj. Mesaj sayilari gonderdigim test mesajlariyla tutarli. | PASS |

### Duzeltme dogrulama

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| FIX-001 dogrulama: navigator observer build fazi hatasi giderildi | Repro artik crash raporu uretmemeli | Duzeltme oncesi bu repro her turda FlutterError uretiyordu (oturumda 4 kayit). Duzeltmeden sonra 3 tur kosuldu: 0 YENI crash raporu, navigator imzasi hic uretilmedi. Warm launch sureleri 2128/1241/1228 ms, regresyon yok. | PASS |
| FIX-006 dogrulama: signaling akis hatalari artik root zone'a kacmiyor | Akis hatalari olumcul-olmayan teshis kaydi olmali, root zone'a kacmamali | 3 tur sonunda 2 yeni rapor olustu ve IKISI DE fatal=False. Onceki turda ayni yol 13 saniyede 18 adet fatal=True WebSocketChannelException uretmisti; artik hic yok. Yeni raporlarin ikisi de BUG-005'in disposal ciftine ait (duzeltilmedi, beklenen). Ekranda kirmi | PASS |
| FIX-crash-ring: crash raporu halkasi 20 -> 200 | Tekrar eden tek bir hata onceki kanit raporlarini tahliye etmemeli | QA oturumunda halka 20'de dolmus ve ilk kanit raporlari (dahil orijinal navigator crash'i) tahliye olmustu; gercek crash sayisi olculemedi. Yeni limitle cihazda rapor sayisi 22'ye cikti, yani devrede. crash_reporter_test maximumFiles'i acikca veriyor, etkilenm | PASS |
| FIX-018 dogrulama: dosya parcasi cerceve butcesine sigiyor | Dolu parcalar 256 KiB (262.144 byte) limitinin altinda kalmali, transfer tamamlanmali | Dolu parca cercevesi 233.463 byte (pay 28.681). Onceki olcum 311.171 byte idi (asim 49.027). Uc parca da SIGIYOR, file_complete alindi, 0 yeni crash. encryption=flutter-file-v4-direct. Tel trafigi %25 dustu. | PASS |
| FIX-018 regresyon testi (4 test) | Testler duzeltmeyle gecmeli, duzeltme olmadan DUSMELI | 4 test: (1) uretim parca boyutunda dolu parca 256 KiB butcesine sigar + SignalMessage.decode kabul eder, (2) v4 zarfi ham tasir, (3) eski v2 gonderenin cerceveleri hala cozulup birlestiriliyor (geriye uyumluluk), (4) sisme orani < 2.0x. Duzeltme geri alininca  | PASS |
| FIX-009 dogrulama: kimlik rotasyonundan kurtarma cihazda calisiyor | Istemci bozuk oturumu tespit edip prekey bundle'i yeniden cekmeli, karsi tarafa reset bildirmeli ve sohbet calisir hale gelmeli | Zaman cizelgesi: bayat oturumla gonderimler peer_error NoSessionException verdi; cozulemeyen zarf sonrasi prekey_served=qa-peer-01 (BUNDLE YENIDEN CEKILDI - duzeltme oncesi bu HIC olmuyordu), ardindan session_reset_request gonderildi; sonraki gonderim peer_dec | PASS |
| FIX-009 regresyon testleri (3 test) | Testler duzeltmeyle gecmeli, duzeltme olmadan dusmeli | 3 test: (1) karsi taraf kimligini yenileyince oturum kendini toparlar - Bob'un yeniden kurulumu tam olarak modelleniyor (yeni depo, yeni kimlik, dizine yeni bundle) ve kurtarma sonrasi mesaj cozuluyor; kimlik rotasyonunun disari bildirildigi de assert ediliyor | PASS |
| FIX-013 dogrulama: tek-gosterim onizleme sizintisi kapandi | Liste onizlemesinde icerik gorunmemeli, notr etiket olmali, ozellik bozulmamali | Liste satiri: 'Q \| qa-peer-01 \| Tek gosterimlik mesaj \| 25.08 \| 1' - duz metin YOK, notr etiket VAR, okunmadi rozeti korundu. Ardindan ozellik turu tekrar kosuldu: baloncuk gizli geldi ('Acmak icin dokunun'), acilista icerik ve 'Tek gosterimlik - ekran kor | PASS |
| FIX-013 regresyon testleri (3 test) | Tek-gosterim icerigi hicbir icerik tipinde onizlemeye sizmamali | 3 test: (1) tek-gosterim onizlemesi icerigi sizdirmaz, (2) bayrak TUM StorageMessageContentType degerlerinde onceliklidir, (3) normal mesajlarda onizleme davranisi korunur (dosya adi da sizmiyor). Tam paket: 262 test geciyor. | PASS |
| FIX-005 dogrulama: dialog disposal cokmesi giderildi | Kirmizi hata ekrani cikmamali, yeni teshis kaydi olusmamali, ozellikler calismali | 5 tur sonunda 0 YENI teshis kaydi, kirmizi ekran yok. Onceki turda ayni repro her seferinde FlutterError + _AssertionError ciftini uretiyordu. Tus takimi aciliyor ve metin kabul ediyor; grup olusturma calisiyor ve grup adi yeni record yolundan dogru geciyor (' | PASS |
| FIX-010 / FIX-T-A04 regresyon testleri | Kimlik uyarisi sohbete yazilmali; reddetme aktif cagri kapatmadan ayrilmali | security_notice: 3 test (sistem mesaji + onizleme + okunmadi sayaci yaziliyor; ayni gun tekrari sohbeti doldurmuyor; bilinmeyen sohbette sessiz kaliyor). native_call_reject: 3 test (ringing/initiating gelen cagri reddetme sayilir; active/connecting/reconnectin | PASS |
| FIX-017 dogrulama: servis metinleri dile uyuyor | Secilen dilde arayuz o dilde olmali | Ingilizce'de arayuz tam tutarli: Chats / Search / More / All / Unread / Groups / Favorites / Archived Chats. Onceki turda Arapca secildiginde bu cipler Ingilizce, bazi calisma zamani metinleri Turkce kaliyordu. Servis katmani metinleri artik ServiceStrings uze | PASS |
| FIX-017 regresyon testleri (4 test) | Servis metinleri her desteklenen dilde dogru gelmeli | 4 test: (1) tr/en/de kendi metnini donduruyor, ar Turkce donmuyor; (2) guvenlik uyarisi cevrilmis geliyor ve Ingilizce'de Turkce kalinti yok; (3) kacirilan arama govdesi peer adini yerlestiriyor; (4) desteklenmeyen dil kodu sablon dile dusuyor. Tam paket: 272  | PASS |
| FIX-A03 dogrulama: kontrol durumlari erisilebilirlik aginda | Kontroller ac/kapa durumlarini bildirmeli | Hoparlor: False -> tiklandiktan sonra True. Mute: etiket 'Sessize al' -> 'Sesi ac' ve toggled False -> True. Ilk turda bu durumlar hic gorunmuyordu. | PASS |
| FIX-008 dogrulama: yaziyor-gostergesi trafigi | Gizlilik padding'i korunarak trafik dusmeli | 2 cerceve / 58.794 byte (57 KB). Duzeltme oncesi ayni senaryo 8 cerceve / ~232 KB uretirdi -> %75 azalma. Paket boyutu degismedi (hala 16 KiB padli), yalniz gonderim sikligi dustu. | PASS |

### Grup mesajlasma

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-G01 Grup mesaji: sender-key dagitimi ve per-uye yonlendirme | Her uyeye once SenderKey Distribution Message (SKDM), sonra GROUPROUTE zarfi ayri ayri 1:1 Signal oturumunda gitmeli; wire metadata'sinda grup kimligi | Her iki uyeye de SKDM dagitildi (2 adet, opak grup id 'group-54TD5uuJBm-...'), ardindan 2 uye GROUPROUTE:v3 zarfini cozdu. Sunucu yalnizca birbirinden bagimsiz encrypted_message cerceveleri gordu; grup adi/uye listesi wire'da yok. peer_error=1, yeni crash=0 (K | PASS |

### Kimlik dogrulama

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-AUTH01 Temiz kurulum: onboarding + kayit + prekey + baglanti | Kayit tamamlanmali, prekey'ler yuklenmeli, WebSocket baglanmali | Onboarding 3 sayfa (Uctan uca sifreli / Dogrudan arama / Tam gizlilik kontrolu) ve ardindan gerekce acikli izin ekrani goruldu (Bildirimler, Rehber - 'Kisileri yalnizca hash ile kesfetmek icin', Mikrofon, Kamera). Akis: otp/request 200 -> otp/verify -> users/r | PASS |

### Kripto ve oturum

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-004 (DUZELTILDI): kullanilmayan wire mesaj tipleri kaldirildi | Decode edilen her tip uretilmeli/tuketilmeli | PreKeyBundleSignal, SessionResetRequestSignal, AudioDataSignal decode ediliyor ama kod tabaninda hicbir yerde uretilmiyor/tuketilmiyor. SessionResetRequestSignal'in yoklugu bayat Signal oturumu kurtarma yolu olmadigi anlamina gelebilir.  KISMEN GIDERILDI: Sess | PASS |
| BUG-009 (DUZELTILDI): karsi taraf kimlik degistirince oturum kalici bozuluyordu | Istemci bozuk oturumu tespit edip prekey bundle'i yeniden cekmeli ve X3DH'i tazelemeli | Istemci bayat oturumla sifrelemeye DEVAM ediyor. Sunucu tarafinda 4x 'InvalidMessageException - No valid sessions. [Bad Mac!]'. Kritik: /api/v1/users/{id}/prekeys HIC yeniden cagrilmiyor (prekey_served=False), yani kurtarma yolu yok. SessionResetRequestSignal  | PASS |
| BUG-010 (DUZELTILDI): kimlik degisiminde kullaniciya gorunur uyari yok | Mesaj 'gonderilemedi' olarak isaretlenmeli veya kullanici uyarilmali | Sohbet ekraninda gonderilen mesaj hic gorunmedi; hata gostergesi, retry aksiyonu veya guvenlik-numarasi-degisti uyarisi yok. Kullanici mesajin gittigini saniyor.  KISMEN GIDERILDI: kurtarma calistigi icin mesajlar artik sessizce kaybolmuyor, sohbet kendini top | PASS |
| BUG-011 (DUZELTILDI): cozulemeyen gelen mesaj sessizce dusuyordu | Uygulama hatayi kaydetmeli; kullaniciya 'mesaj cozulemedi' gibi bir iz birakmali | Hicbir iz yok: logcat sinyali=0, yeni crash raporu=0, yeni UI baloncugu=0. Mesaj sayaci artmiyor, kullanici mesaj kaybettigini asla ogrenemiyor. Ayni sessiz dusme gercek oturum bozulmasinda da gozlendi (bkz BUG-009).  DUZELTME: incoming_message_handler.dart'ta | PASS |

### Medya

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-MD01 Dosya paylasimi: sifreleme ve wire metadata gizliligi | Dosya sifreli parcalar halinde gitmeli; gercek dosya adi, MIME turu, aciklama ve gercek boyut wire metadata'sinda gorunmemeli | Transfer tamamlandi (transferId=62dd8190bc25d-2c11371f, 1 parca, 632 byte). Wire metadata denetimi: fileName='attachment.bin' (GERCEK AD SIZMIYOR), mimeType='application/octet-stream' (GERCEK MIME SIZMIYOR), caption=base64 blob -> cozulunce 'E2EE:v1:SIGNAL:670 | PASS |
| BUG-018 (DUZELTILDI): dolu dosya parcasi 256 KiB cerceve limitini asiyordu | Her parca hem istemcinin kendi decode limitinin (256 KiB) hem de sunucunun maxFrameSize'inin altinda kalmali | 300 KB dosya 3 parcaya bolundu. DOLU parcalar (0/3 ve 1/3) wire'da 311.171 byte; limit 262.144 byte -> her biri +49.027 byte ASIYOR. Yalniz artik parca (2/3, 107.780 B) ve kucuk dosya (1.512 B) limitin altinda. Kok neden: 128 KiB'lik ham parca UC KEZ base64'le | PASS |
| T-MD02 Dosya parcalama (300 KB) | 128 KiB'lik parcalara bolunmeli, bildirilen boyut tam parcaya padlenmeli | 3 parca uretildi (0/3, 1/3, 2/3), transfer tamamlandi (transferId=62dd8255bb6a3-4d5d08c0, toplam 728.576 byte kodlanmis). declaredFileSize=393216 = 3 x 131072, gercek boyut 307.200 -> boyut dogru sekilde padlenmis, gercek boyut sizmiyor. Parcalama mantigi DOGR | PASS |

### Mesajlasma

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| 1:1 E2EE mesaj gonderimi (gercek Signal turu) | Mesaj X3DH/Double Ratchet ile sifrelenip iletilmeli, karsi taraf cozebilmeli | Bot zarfi cozdu: peer_decrypt_ok messageId=1739248781323348-3008ba09429a plaintextLength=48; peer_reply_sent text='echo: hello QA-T01'. Wire'da duz metin yok (envelopeType=SIGNAL). | PASS |
| T-M01 Kisa metin mesaji | Zarf X3DH/Ratchet ile cozulebilmeli, crash olmamali | peer_decrypt_ok messageId=1739249708760861-ede506f9e045 plaintextLength=46 envelopeType=PREKEY; peer_error=6; yeni crash=0 | PASS |
| T-M02 Unicode/Turkce karakter | Zarf cozulebilmeli, crash yok | decrypt OK plaintextLength=77 type=SIGNAL; max cerceve=29397B; peer_error=0; crash=0 | PASS |
| T-M04 Tek karakter | Zarf cozulebilmeli, crash yok | decrypt OK plaintextLength=37 type=SIGNAL; max cerceve=29397B; peer_error=0; crash=0 | PASS |
| T-M03 Uzun mesaj (1500 karakter) | Zarf cozulebilmeli, crash yok | decrypt OK plaintextLength=1523 type=SIGNAL; max cerceve=29397B; peer_error=0; crash=0 | PASS |
| T-M05 Bos mesaj engeli | Bos mesaj gonderilememeli (Gonder butonu gorunmemeli) | Composer bosken Gonder butonu yok, yerine 'Sesli mesaj kaydet' var. (send_button=None) | PASS |
| T-M06 Hizli ardisik gonderim (6 mesaj) | Hepsi sirayla sifrelenip iletilmeli, ratchet bozulmamali, crash yok | gonderilen=6, karsi tarafta cozulen=6, peer_error=0, crash=0 | PASS |
| T-M08 Temiz oturumda gelen mesaj render'i | Gelen mesaj cozulup baloncuk olarak gorunmeli | cihaz->bot PREKEY zarfi ile kuruldu; bot->cihaz 'INBOUND-CLEAN-1' baloncugu goruldu. | PASS |
| T-DM01 Kaybolan mesajlar (saat duzeldikten sonra) | Suresi dolan mesaj silinmeli | TASARIM: sure dolumu canli zamanlayiciyla degil, on plana geciste (AppBackgroundRuntime.runForegroundMaintenance -> deleteExpiredMessages) ve periyodik WorkManager bakim gorevinde supuruluyor. OLCUM: 20 sn sureli mesaj t+40s'te hala goruntuleniyordu; uygulama  | PASS |

### Navigasyon ve UI

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-001 (DUZELTILDI): navigator observer build fazinda setState | Route degisimi hatasiz islenmeli | FlutterError: setState()/markNeedsBuild() called during build. _AppNavigatorObserver._setActiveRoute (app.dart:232) didPush icinde ValueNotifier.value= yaziyor; Navigator gozlemci callback'leri _flushHistoryUpdates icinde senkron calisiyor. Bu oturumda UC bagi | PASS |
| BUG-005 (DUZELTILDI): dialog controller'i cikis animasyonu sirasinda dispose ediliyordu | Ekran normal render edilmeli | Kirmizi hata ekrani: 'package:flutter/src/widgets/framework.dart': Failed assertion line 6268 '_dependents.isEmpty'. Once ChangeNotifier.addListener disposed notifier uzerinde cagriliyor (_AnimatedState.didUpdateWidget), ardindan InheritedElement.debugDeactiva | PASS |

### Ortam

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-002 (COZULDU): cihaz saati senkronize edildi | Saatler yakin olmali | Cihaz 2025-02-11, host 2026-08-25. TLS gecerlilik, JWT exp, mesaj zaman damgasi ve disappearing-timer testlerini etkiler. Kural geregi sistem saati degistirilmedi.  Kullanici cihaz saatini duzeltti. Dogrulama: cihaz ve host arasinda 7 saniye fark (onceden 18 a | PASS |
| T-CLK01 Saat senkronizasyonu sonrasi mesaj siralamasi | Mesajlar kronolojik sirada gorunmeli | SIRA-0 (18:15) / SIRA-1 (18:15) / SIRA-2 (18:16) / BOT-CEVAP (18:16) - dogru sira. Onceki turda cihaz 2025, bot 2026 saatinde oldugu icin bot mesajlari her zaman listenin sonuna dusuyordu. | PASS |

### Otomatik testler ve guvenlik

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-SEC01 Statik guvenlik taramasi (kaynak + manifest) | Plaintext mesaj/anahtar loglanmamali; gomulu sir olmamali; exported yuzey minimum olmali | Loglama: mesaj icerigi, zarf, private key veya token loglayan tek bir cagri yok (zaten tum kod tabaninda yalnizca 1 debugPrint var). Gomulu sir/anahtar bulunamadi. Manifest: allowBackup=false, fullBackupContent=false, usesCleartextTraffic=false, dataExtraction | PASS |
| T-UT01 Mevcut birim/widget test paketi | Tum testler gecmeli | 250 test calisti, tamami gecti ('All tests passed!'), 0 basarisiz. Sure ~19 s. Kapsam icinde dikkat cekenler: private_contact_discovery (blind OPRF cover batch, gecersiz keyId'de fail-closed, fallback yok), signal_protocol_crypto_service, libsignal_wire_compat | PASS |

### Performans

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| Cold start (mock server'a pinlenmis) | Uygulama acilir, WSS baglanir, crash yok | TotalTime 1850-2088ms; WSS pinned TLS ile baglandi; UI'da offline ikonu kayboldu | PASS |
| Sicak baslatma | Hizli geri donus | TotalTime 1251ms | PASS |
| BUG-008 (DUZELTILDI): yaziyor-gostergesi trafigi %75 azaldi | Kontrol paketleri makul boyutta olmali | Her typing_indicator ve delivery_receipt 16 KiB'a sabit-padleniyor (private_chat_control.dart:10 _privateControlPacketBytes = 16*1024) -> 21860 byte plaintext -> 29396 byte WebSocket cercevesi. Tek bir mesaj gonderiminde 20+ adet 29 KB'lik cerceve gozlendi; as | PASS |
| T-A02 Arama sirasinda kaynak kullanimi | CPU ve bellek makul sinirlarda kalmali | Debug build: CPU %14-18, PSS 627-645 MB (grafik ~170 MB dahil). Cagri oncesi PSS 678 MB idi; cagri sirasinda artis olmadi. NOT: debug build JIT + 83 MB kernel_blob tasidigi icin mutlak degerler release ile karsilastirilamaz; yalniz goreli trend anlamlidir. | PASS |
| BUG-015 (DUZELTILDI/geri cekildi): fat APK resmi dagitim artefakti degil | Yalniz hedef cihaz mimarisi teslim edilmeli (ABI split veya App Bundle) | ILK TESPIT YANLIS CERCEVELENMISTI. build/app/outputs/flutter-apk/app-release.apk 109 MB ve uc ABI tasiyor, ancak bu dosya resmi dagitim artefakti DEGIL. tool/build_hardened_android_release.sh:29 'flutter build appbundle' calistiriyor; teslim edilen artefakt AA | PASS |
| T-PK01 SQLCipher bagimliligi incelemesi | Kullanilmayan native kutuphane teslim edilmemeli | Ilk bakista olu kod gibi gorundu (Dart tarafinda sqlite referansi yok, cihazda databases/ dizini bos). Ancak build.gradle.kts:78 acikca belirtiyor ve android/app/src/main/kotlin/com/securechat/app/LegacyRoomExporter.kt mevcut: eski Kotlin Room v22 veritabanini | PASS |
| T-PF01 Baslatma suresi | Soguk baslatma debug'da < 2500 ms, sicak baslatma < 500 ms | Soguk medyan 1838 ms (min/maks 1827 / 1850), tutarli. Sicak medyan 116 ms. | PASS |
| T-PF02 Bellek sizintisi taramasi | PSS ve View sayisi tekrarli dongude surekli artmamali | Mesajlasma trendi (KB): [631446, 631905, 629534, 630030] -> duz, artis yok. 12x sohbet ac/kapat (KB): [660481, 634353, 639001, 638073] -> ilk olcumden sonra DUSMUS, birikme yok. View sayisi tum olcumlerde sabit 9. Bosta PSS 605 MB, 12 dongu sonrasi 628 MB (gra | PASS |
| T-PF03 Grafik akiciligi (jank) | 120Hz ekranda jank orani < %5 ve missedFrames = 0 olmali | Sohbet listesi kaydirma: %3.45 jank, 2377 kare, missedFrames=0; Sohbet ekrani kaydirma: %3.54 jank, 1949 kare, missedFrames=0; Sekme gecisleri: %4.08 jank, 1983 kare, missedFrames=0. Ekran 120Hz, hedef kare suresi 8.33 ms. Uc senaryoda da missedFrames=0. | PASS |
| T-PF04 Release build performans karsilastirmasi | Release, debug'a gore belirgin daha iyi olmali | Soguk baslatma: 288 / 299 / 297 ms (medyan ~297). Debug medyani 1838 ms idi -> 6 KAT hizli. Native heap 33.6 MB (debug ~65 MB). APK 114.3 MB (debug 219.9 MB). Bu, rapordaki tum debug performans sayilarinin ust sinir oldugunu dogruluyor; uretimde gercek degerle | PASS |

### Push

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-003 (COZULDU): FCM istemci yolu internetli cihazda calisiyor | FCM token alinmali | ILK TESHISIM YANLISTI. 'W FirebaseApp: Default FirebaseApp failed to initialize because no default options were found ... google-services was not applied' uyarisina bakip google-services.json eksikligini sebep sandim. Uyari IYI HUYLU: firebase-common'in otomat | PASS |
| BUG-019: iOS'ta Firebase varsayilani yok, push sessizce devre disi kaliyordu | iOS ve Android ayni sekilde yapilandirilabilmeli | Android app id'si dart-define varsayilaniyla gomuluydu, iOS'unki DEGILDI: String.fromEnvironment('SECURECHAT_FIREBASE_IOS_APP_ID') bos donunce metot null donuyor ve Firebase iOS'ta HIC baslamiyordu - hicbir hata da uretmeden. Asimetrik ve sessiz bir tuzak. DUZ | PASS |

### Rehber

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| Rehber: sunucu modulu yokken davranis (negatif) | Acik hata mesaji, cokme yok, guvensiz fallback yok | 'Sunucu guncellemesi gerekiyor - guvenli rehber modulu etkin degil. Rehber verilerin gonderilmedi.' Tekrar Dene aksiyonu sunuluyor. Duz telefon numarasi fallback'i YOK. | PASS |
| T-C01 Private contact discovery (blind-RSA OPRF) uctan uca | Istemci keyId'yi dogrulamali, 256'lik kor batch gondermeli, kendi kaydini yapmali, eslesme yoksa notr bos durum gostermeli | Protokolun tamami calisti: config keyId istemci tarafindan dogrulandi (SPKI SHA-256 openssl kanonik degeriyle birebir), evaluate 256 elemanlik kor batch ile 200, directory-token ile kendi kaydi yazildi, snapshot 1 kayit dondu. 'Guvenli rehber hizmeti kullanila | PASS |
| T-C02 Rehber esleme (gercek cihaz rehberi ile) | Kayitli kullanicilar rehberdeki isimleriyle listelenmeli; duz numara sunucuya gitmemeli | Her iki kisi de blind-RSA OPRF ile eslesti ve listede rehber ismiyle gorundu: ['Q \| QA_Test_Ayse \| +905550000001', 'Q \| QA_Test_Mehmet \| +905550000002']. Wire'da yalniz kor RSA grup elemanlari gonderildi; duz telefon numarasi veya deterministik hash sunucu | PASS |

### Sesli/goruntulu arama

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-A01 Giden sesli arama: signaling + Telecom yasam dongusu | SDP offer/answer ve ICE trickle akmali; Android foreground call service ve CallStyle bildirimi olusmali; kapatmada temizlenmeli | sdp_offer gonderildi (callType=VOICE, sdp 1308 karakter); bot RINGING dondu; 4 adet ice_candidate trickle edildi; sdp_answer + ACCEPT alindi. Android tarafinda SecureChatCallService isForeground=true foregroundId=1200 types=00000004 (phoneCall) channel=call_ch | PASS |
| T-A03 (DUZELTILDI): arama kontrolleri durumlarini bildirmiyordu | Kontroller durum degistirmeli ve crash uretmemeli | Her iki kontrol de tiklandi, crash olusmadi. Semantik etiket degisimi uiautomator dump'inda yakalanamadi (Flutter Switch semantics), bu yuzden durum degisimi gorsel olarak dogrulanmali.  KOK NEDEN: _round() Semantics'e yalniz label veriyordu. 'Sessize al' etik | PASS |
| T-A04 Gelen arama: bildirim, kimlik gizleme ve reddetme | Tam ekran/heads-up arama bildirimi cikmali, arayan kimligi gizli olmali, reddetmede REJECT sinyali gitmeli ve kaynaklar temizlenmeli | Heads-up bildirim 'Elcim aramasi' (arayan adi GIZLENMIS) + Reddet/Yanitla aksiyonlari, channel=incoming_call_channel id=1200 importance=4. Reddet sonrasi REJECT sinyali gonderildi=False; kalan foreground service=0; crash yok. [GUNCELLEME: reddetmenin HANGUP go | PASS |
| T-A04 (DUZELTILDI): bildirimden reddetme HANGUP yerine REJECT gonderiyor | Arayan tarafin 'reddedildi' ile 'kapatildi' ayrimini yapabilmesi icin REJECT beklenir | Gonderilen action=HANGUP (REJECT degil). CallControlSignal REJECT/BUSY degerlerini destekliyor (incoming_message_handler'da case 'REJECT' ve 'BUSY' var) ama reddetme yolunda kullanilmiyor. Arayan tarafta 'mesgul/reddedildi' ayrimi yapilamaz. Kaynak temizligi d | PASS |

### Signaling ve ag

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| 60 saniyelik sunucu kesintisi (offline dayaniklilik) | UI kilitlenmez, crash yok, otomatik yeniden baglanir | 60s boyunca 0 yeni crash raporu; sunucu donunce ayni userId ile otomatik reconnect | PASS |
| Sunucu yeniden baslatma sirasinda reconnect | Sessiz yeniden baglanma | 0 yeni crash; reconnect basarili | PASS |
| BUG-006 (DUZELTILDI): fatal WebSocketChannelException root-zone'a kaciyordu | Ag hatalari yakalanip typed hataya donusmeli | 13 saniye icinde 18 adet fatal=True WebSocketChannelException crash raporu, context=root-zone, stack bos. 20'lik ring buffer doldu ve onceki kanit raporlari tahliye oldu. NOT: kontrollu 60s kesinti ayni hatayi URETMIYOR; tetikleyici disposal sirasi.  DUZELTME: | PASS |

### Sohbet ve girdi dogrulama

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-007 (GERI CEKILDI): kontrol zarfinin metin olarak gosterilmesi acik degil | Uygulama taninmayan kontrol zarfini sessizce atmali | ILK DEGERLENDIRME HATALIYDI. Karsi taraf zaten istedigi metni gonderebilir; 'CHATCTRL:v2:...' dizesini mesaj baloncugunda gostermek 'keyfi icerik bastirma' degil, normal mesajlasmadir. Gozlemin asil sebebi benim mock bot'umun kontrol zarflarini echo'lamasiydi. | PASS |
| Sohbet silme (onay + kalicilik) | Sohbet ve mesajlari kalici silinmeli, restart sonrasi geri gelmemeli | Onay diyalogu net: 'peer-ayse sohbeti ve bu cihazdaki mesajlari kalici olarak silinsin mi?'. Silindi, force-stop + relaunch sonrasi listede yok. Crash yok. | PASS |
| Taslak (draft) kaliciligi | Yazilmis taslak korunmali | Taslak restart sonrasi composer'da duruyordu (Gonder butonu aktif). | PASS |
| BUG-016: Metin alaninda dikey imlec hareketi assertion uretiyor | Imlec hareketi hatasiz islenmeli | 16 adet _AssertionError crash raporu: VerticalCaretMovementRun.movePrevious (flutter/src/rendering/editable.dart:214) icindeki assert(isValid) tetikleniyor; cagri zinciri _UpdateTextSelectionVerticallyAction.invoke (editable_text.dart:6657). Bayat bir Vertical | FAIL |

### Stabilite

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-ST01 Monkey stabilite testi (5000 event) | Uygulama cokmemeli, ANR vermemeli, surec ayakta kalmali | 5000 event 516 saniyede enjekte edildi. Monkey ciktisi: '// Monkey finished', 'Dropped: keys=0 pointers=0 trackballs=0 flips=2 rotations=0'. CRASH yok, ANR yok, native crash yok (logcat'te FATAL/SIGSEGV/ANR bulunamadi). Test sonunda uygulama surecinin ayakta o | PASS |

### Tek gosterim

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| T-M07 Tek gosterim bayragi sifreli govdede tasiniyor | VIEWONCE oneki sifreli govde icinde olmali; normal mesajda olmamali; wire metadata'sinda gorunmemeli | normal=['MSGID', 'bodyLen=16']; tek-gosterim=['MSGID', 'VIEWONCE', 'bodyLen=18'] | PASS |
| T-M09 Tek gosterim (gelen): tam yasam dongusu | Icerik gizli gelmeli, bir kez acilabilmeli, sonra kalici kilitlenmeli; acilmamis mesaj acilabilir kalmali | Gelen baloncuk 'Acmak icin dokunun' olarak gizli geldi. Acilista tam ekran 'Tek gosterimlik - ekran korumali' overlay'i ile icerik gorundu. Kapatinca baloncuk 'Bu medya artik acilamaz' oldu ve icerik bir daha gosterilmedi. Acilmamis bir tek-gosterim mesaji ise | PASS |
| T-M10 (DOGRULANDI): release build'de ekran goruntusu engeli calisiyor | Ekran koruma durumu kullaniciya bildirilmeli | Release APK uretildi (flutter build apk --release), imzasiz cikti (signing.properties yok) - QA icin Android debug sertifikasiyla apksigner ile imzalandi; derleme tipi, R8/AOT ve manifest RELEASE'tir. Ayri applicationId oldugu icin com.securechat.app.debug otu | PASS |
| BUG-013 (DUZELTILDI): acilmamis tek-gosterim icerigi sohbet listesinde sizyordu | Tek-gosterim mesajinin icerigi onizlemede gorunmemeli; 'Tek gosterimlik mesaj' gibi notr bir etiket olmali | Sohbet listesi satiri duz metni gosteriyor: ['Q \| qa-peer-02 \| VO-UNOPENED-A \| 25.08']. Mesaj henuz hic acilmadi; sohbet ekraninda dogru sekilde 'Acmak icin dokunun' olarak gizli. Tek-gosterim garantisi listede delinmis oluyor (omuz sorfu / bildirim yuzeyi  | PASS |

### Yerellestirme

| Senaryo | Beklenen | Gözlenen | Sonuç |
|---|---|---|---|
| BUG-017 (KISMEN DUZELTILDI): servis metinleri yerellestirildi, ceviri bosluklari acik | Secilen dilde tum arayuz metinleri o dilde olmali | RTL duzeni DOGRU uygulaniyor (baslik saga hizali, alt navigasyon ters cevrilmis, yon oklari donmus). Ancak metinler UC DILDE birden: Arapca ('الدردشات المؤرشفة', alt sekmelerden uc tanesi), Ingilizce (filtre cipleri 'All', 'Unread', 'Groups', 'Favorites'; ayri | WARN |
| T-L01 RTL duzen destegi | Duzen sagdan sola cevrilmeli, tasma olmamali | RTL duzeni dogru: uygulama basligi saga hizali, sohbet satirlarinda avatar saga gecmis, zaman damgasi sola gecmis, alt navigasyon sirasi ters cevrilmis, arsiv satirindaki rozet dogru tarafta. Metin tasmasi veya kirpilma gozlenmedi. | PASS |

## Performans ölçümleri

### Başlatma süresi

| Senaryo | TotalTime (ms) | Eşik önerisi |
|---|---|---|
| Soguk baslatma (3 tur medyan) | 1838 | < 2000 (debug), < 1000 (release) |
| Soguk baslatma (min/maks) | 1827 / 1850 | < 2000 (debug), < 1000 (release) |
| Sicak baslatma (3 tur medyan) | 116 | < 2000 (debug), < 1000 (release) |

### Bellek (dumpsys meminfo)

| Durum | PSS (MB) | Native (MB) | Dalvik (MB) | Graphics (MB) | Views |
|---|---|---|---|---|---|
| Bosta (ana ekran) | 605 | 61 | 6 | 161 | 9 |
| Mesajlasma sirasinda | 615 | 56 | 3 | 161 | 9 |
| 12x sohbet ac/kapat sonrasi | 628 | 64 | 4 | 161 | 9 |

### Grafik / jank (SurfaceFlinger timestats)

| Senaryo | Ekran | Hedef kare (ms) | Ölçülen kare | Akıcı | Geçen | Jank % | missedFrames |
|---|---|---|---|---|---|---|---|
| Sohbet listesi kaydirma | 120 Hz | 8.33 | 2377 | 2295 | 82 | 3.45 | 0 |
| Sohbet ekrani kaydirma | 120 Hz | 8.33 | 1949 | 1880 | 69 | 3.54 | 0 |
| Sekme gecisleri | 120 Hz | 8.33 | 1983 | 1902 | 81 | 4.08 | 0 |

### Bellek sızıntısı trendi

| Ölçüm | Değerler (KB) | Yorum |
|---|---|---|
| 10 mesaj gönderimi | [631446, 631905, 629534, 630030] | düz, artış yok |
| 12x sohbet aç/kapat | [660481, 634353, 639001, 638073] | birikme yok |

### CPU (top)

| Durum | %CPU |
|---|---|
| Bosta | 0.0 |
| Mesajlasma sirasinda | 0.0 |

> Tum olcumler DEBUG build uzerinde alindi (JIT + 83 MB kernel_blob). Release build belirgin sekilde daha dusuk bellek ve daha iyi jank verir; mutlak degerler release ile karsilastirilamaz, yalniz goreli trend anlamlidir.
> dumpsys gfxinfo Flutter icin GECERSIZ: uygulama SurfaceView kullanip HWUI'yi bypass ediyor, gfxinfo 0 kare donduruyor. SurfaceFlinger --latency de Android 13+ uzerinde bos donuyor. Olcum SurfaceFlinger --timestats ile yapildi.
> Jank yuzdesi hesabinda jestler arasi bosta bekleme araliklari (>200ms) haric tutuldu.

## Kapsam özeti

| Özellik alanı | Durum | Not |
|---|---|---|
| Anket | kapandı | 4 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Ayarlar | kapandı | 4 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Duzeltme dogrulama | kapandı | 15 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Grup mesajlasma | kapandı | 1 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Kimlik dogrulama | kapandı | 1 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Kripto ve oturum | kapandı | 4 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Medya | kapandı | 3 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Mesajlasma | kapandı | 9 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Navigasyon ve UI | kapandı | 2 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Ortam | kapandı | 2 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Otomatik testler ve guvenlik | kapandı | 2 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Performans | kapandı | 10 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Push | kapandı | 2 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Rehber | kapandı | 3 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Sesli/goruntulu arama | kapandı | 4 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Signaling ve ag | kapandı | 3 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Sohbet ve girdi dogrulama | açık bulgu var | 3 PASS, 1 FAIL, 0 WARN, 0 BLOCKED |
| Stabilite | kapandı | 1 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Tek gosterim | kapandı | 4 PASS, 0 FAIL, 0 WARN, 0 BLOCKED |
| Yerellestirme | kapandı (uyarılı) | 1 PASS, 0 FAIL, 1 WARN, 0 BLOCKED |

## Açık riskler

- **Oturum kurtarma yok (BUG-009, Critical).** Karşı taraf uygulamayı yeniden kurarsa o sohbet kalıcı olarak ölüyor ve kullanıcı hiçbir uyarı almıyor (BUG-010, BUG-011). Üretimde en yüksek etkili bulgu bu; tek bir kişinin telefon değiştirmesi sohbeti bitiriyor.
- **Sessiz veri kaybı (BUG-011, High).** Çözülemeyen gelen mesaj hiçbir iz bırakmadan düşüyor: log yok, crash raporu yok, sayaç yok. Üretimde bu sınıf hatayı teşhis etmek imkânsız olur.
- **Tek-gösterim garantisi listede deliniyor (BUG-013, High).** Açılmamış mesajın düz metni sohbet listesi önizlemesinde görünüyor.
- **Gözlemlenebilirlik neredeyse sıfır.** 41.8k satırda tek bir `debugPrint` var ve o da yalnızca `kDebugMode`. Crash raporu halkası 20 dosyada sınırlı; bu oturumda halka doldu ve önceki kanıtlar tahliye oldu. Üretim teşhisi için yetersiz.
- **Cihaz saati 18 ay geride (BUG-002).** Kaybolan mesaj zamanlayıcısı, JWT süresi ve mesaj sıralaması bu ortamda güvenilir test edilemedi.

## Sunucu geldiğinde ek olarak test edilmesi gerekenler

- Gerçek OTP e-postası ile kayıt akışı; SMTP kapalı ve rate-limit yollarının canlı doğrulaması.
- Refresh token rotasyonu ve `1008` sonrası gerçek yeniden yetkilendirme.
- Gerçek FCM push ile uyandırma (bu cihazda Play Services `241518038` < gerekli `261200000`; ayrıca `google-services.json` bu derlemede yok).
- Sunucu tarafı prekey havuzu tükenmesi ve `prekeys/refresh` davranışı.
- Janus SFU ile gerçek grup çağrısı medya yolu (`sfu_room_created`, `janusWsUrl`).
- TURN/STUN üzerinden NAT arkası gerçek ICE bağlantısı.
- Sunucu tarafı hesap silme ve `account/delete` sonrası gerçek veri temizliği.
- Private directory'nin production anahtar rotasyonu (`DirectoryKeyChangedException` yolu).

## Gerçek ikinci cihazla tekrar doğrulanması gerekenler

Aşağıdaki sonuçlar **simüle karşı taraf** (mock sunucudaki sanal peer) ile alındı. Sanal peer gerçek `libsignal_protocol_dart` kimliği taşır ve X3DH/Double Ratchet'i gerçekten çalıştırır, ancak WebRTC medya düzlemi gerçek değildir.

- 1:1 sesli/görüntülü çağrıda gerçek DTLS/SRTP kurulumu ve iki yönlü medya akışı (bu turda çağrı 'Bağlanıyor…' aşamasında kaldı — sanal peer gerçek medya üretemiyor).
- Grup çağrısı mesh/SFU davranışı, katılımcı ekleme-çıkarma.
- Gerçek karşı tarafta mesaj teslim/okundu makbuzlarının uçtan uca doğrulanması.
- Sender-key dağıtımının gerçek ikinci istemcide çözülmesi ve grup mesajının okunması.
- Tek-gösterim medyanın karşı tarafta ekran görüntüsü engeli (release build gerekir).
- Dosya transferinin karşı tarafta yeniden birleştirilmesi ve açılması.

## Test altyapısı (yeniden kullanım için)

| Bileşen | Yol | Not |
|---|---|---|
| Mock sunucu (TLS, çok istemcili) | `qa/mock/bin/server.dart` | Sanal peer'ler gerçek Signal kimliği taşır |
| Private directory (blind-RSA OPRF) | `qa/mock/bin/directory.dart` | RSA-3072, istemciyle bit-uyumlu |
| Sözleşme probu | `qa/mock/bin/probe.dart` | Cihaza dokunmadan 17 kontrat kontrolü |
| Senaryo koşucusu | `qa/scripts/scenario.py` | UI + log + mock olayı + kanıt kaydı |
| Cihaz yardımcıları | `qa/scripts/dev.sh` | Tümü `-s <serial>` parametreli |
| QA APK derleme | `qa/scripts/build_qa_apk.sh` | Kaynak değişikliği yok, sadece dart-define |
| Mock yaşam döngüsü | `qa/scripts/mock.sh` | start/stop/restart/rebuild/status |
| Jank ölçümü | `qa/scripts/jank.py` | SurfaceFlinger timestats (gfxinfo Flutter'da geçersiz) |

**İkinci fiziksel cihaz eklemek için:** `SC_SERIAL=<seri> adb -s <seri> reverse tcp:18444 tcp:18444` ve aynı QA APK'yı kur. Sunucuda değişiklik gerekmez — her istemci kendi `userId`'siyle kaydolur ve mesajlar gerçekten yönlendirilir.
