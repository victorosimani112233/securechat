# İki Cihaz QA Testi — 2026-10-12

Bu dosya testler sırasında **adım adım** güncellenir. Testte anlık düzeltme
yapılmadı; her bulgu başka bir oturumda düzeltilmek üzere ayrıntılı yazıldı.

## Ortam

| | |
|---|---|
| Sunucu | 185.22.184.114, jar `8168ce8` (V29), dev profil, `SFU_ENABLED` boş, `JANUS_API_SECRET` yok |
| İstemci | `2f31b3e` debug APK (`1.0.76-debug`, arm64, `SECURECHAT_LOCAL_DIAGNOSTICS=true`) |
| Cihaz A | `R5GL2452S4A` — QaAlfa `+905321000412` (sistem dili Almanca) |
| Cihaz B | `R5GL2452SJK` — QaBeta `+905321000413` |
| Log | `adb logcat` içinde `I flutter : SC-*` satırları |

## Bulgu özeti

| # | Önem | Alan | Başlık | Durum |
|---|---|---|---|---|
| 1 | YÜKSEK (gizlilik) | Çıkış / yerel veri | Çıkış önceki hesabın mesaj geçmişini silmiyor; yeni hesap onu görüyor | Açık |
| 2 | DÜŞÜK | Sohbet başlığı | "son görülme 1 Oca 1970" (epoch 0) | Açık |
| 3 | ORTA | Gelen sohbet | Rehberde olmayan gönderenin sohbet başlığı ham kullanıcı UUID'si | Açık |
| 4 | DÜŞÜK | Avatar | İsimsiz kişilerin avatar harfi anlamsız ("9", "33") | Açık |
| 5 | ORTA | Görüntülü arama sesi | Görüntülü arama ahizeden başlıyor; arayanda "Hoparlör" düğmesi açık görünüyor ama ses ahizede | Açık |
| 6 | ORTA | Grup üye seçici | Telefon rehberinde olmayan, sohbet edilen kişi gruba eklenemiyor | Açık |
| 7 | DÜŞÜK | Rehber araması | Tam numarayla arama bulmuyor (biçimli numaradaki boşluklar normalize edilmiyor) | Açık |
| 8 | ORTA | Grup araması | Arayan 60 sn'de zaman aşımına uğrayınca aranan taraf "ölü" aramayı cevaplayabiliyor; "Bağlanıyor…"da takılıyor; "Katıl" TimeoutException; kayıtlar tutarsız | Açık |
| 9 | DÜŞÜK | Grup araması | Arama herkes için bittikten sonra "Devam eden sesli arama — Katıl" bandı ~20 sn kalıyor | Açık |
| 10 | DÜŞÜK | Sohbet kaydırma | Gönderen kendi mesajından sonra en alta kaymıyor; "En yeni mesaja git" rozeti kendi mesajlarını sayıyor | Açık |
| 11 | GÜVENLİK NOTU | Yerel depolama | Alınan dosyalar uygulama dizininde şifresiz (`files/media/received_files/`) | Karar gerekli |
| 12 | ORTA (güvenlik) | Tek gösterim | Tek gösterimlik dosyada "Uygulamayla aç" düğmesi var; içerik dış uygulamaya verilip kalıcı kopyalanabilir | Açık |
| 13 | DÜŞÜK | Tek gösterim | Gönderende alıcı açmadan "1 · Açıldı"; metin için "Bu medya artık açılamaz" | Açık |
| 14 | DÜŞÜK | Tek gösterim | Tek gösterimlik .txt dosyası alıcıda "Tek gösterimlik fotoğraf" diye etiketleniyor | Açık |
| 15 | DÜŞÜK | Tek gösterim | Anahtar açıkken anket normal anket olarak gidiyor, anahtar açık kalıyor | Açık |
| 16 | DÜŞÜK | Tek gösterim | Debug derlemede tek gösterim ekranı "ekran korumalı" diyor ama FLAG_SECURE yok; medya önizlemedeki "1" düğmesinin erişilebilirlik etiketi yok | Açık |

---

## Adım 0 — Başlangıç durumu

**Sonuç:** İki cihaz da yeni hesaplarla girişli (`users/register` 200,
`SC-PREKEY published one_time=50 fallback=true accepted=true`), sunucuya
bağlı. Ancak sohbet listesinde önceki hesapların sohbeti duruyor → Bulgu 1, 2.

### Bulgu 1 — Çıkış önceki hesabın mesaj geçmişini silmiyor (YÜKSEK, gizlilik)

- **Adımlar:** Cihaz A'da eski QA hesabı (`+908976464464`) girişliyken
  Ayarlar → Çıkış yap. Aynı cihazda yeni numarayla (`+905321000412`) yeni
  hesap kaydı.
- **Beklenen:** Yeni hesap boş sohbet listesiyle açılır; önceki hesabın
  mesajları, medyası, arama geçmişi cihazdan silinmiş olur (ya da en azından
  yeni hesaba görünmez).
- **Gerçekleşen:** Sohbetler sekmesinde eski hesabın `+901646767346` ile olan
  sohbeti duruyor. Açınca 7–8 Ekim'deki mesajlar **düz metin** görünüyor
  (`merhaba-test-1`, `cevap-test-2`, `Sa`) ve arama geçmişi (giden/gelen
  sesli, görüntülü). Cihaz B'de de aynısı (`+908976464464` sohbeti).
- **Etki:** Paylaşılan/devredilen cihazda yeni kullanıcı önceki kullanıcının
  şifresi çözülmüş mesaj geçmişini okur. Ayrıca yeni hesap bu eski sohbete
  yazarsa alıcı kimliği artık geçersiz bir kullanıcıya gider.
- **Kök neden:** `lib/src/auth/auth_coordinator.dart:143` `logout()` yalnız
  `_olmPreKeys.clearLocalCryptoState()` ve `_session.clearAndPersist()`
  çağırıyor. Sohbet/mesaj/medya/arama kaydı tabloları
  (`lib/src/storage/secure_chat_database.dart`) ve medya dosyaları
  temizlenmiyor. `clearLocalAuthentication()` (aynı dosya ~:188) da aynı.
- **Öneri:** Çıkışta (ve farklı `userId` ile girişte, savunma olarak)
  kullanıcıya ait tüm yerel veriyi silen tek bir `wipeLocalAccountData()`
  yolu; ya da veritabanını `userId` bazlı ayırmak. Test: çıkış sonrası yeni
  kayıtta sohbet listesi boş olmalı.

### Bulgu 2 — "son görülme 1 Oca 1970" (DÜŞÜK)

- **Adımlar:** Bulgu 1'deki eski sohbeti aç.
- **Gerçekleşen:** Başlıkta `son görülme 1 Oca 1970`.
- **Beklenen:** Son görülme bilinmiyorsa satır gizlenir (ya da "son görülme
  bilinmiyor").
- **Ek gözlem (Adım 1):** Yeni ve **çevrimiçi** karşı tarafla açılan sohbette
  de (`+905321000413`, Cihaz B uygulamada açıkken) aynı yazı çıktı. Yani
  ya presence hiç gelmiyor ya da gizlilik nedeniyle gizli olan durum 0
  olarak gösteriliyor.
- **Kök neden (tahmin):** Son görülme değeri yok/0 iken
  `DateTime.fromMillisecondsSinceEpoch(0)` biçimlendiriliyor. Sohbet başlığı
  widget'ında 0/null kontrolü eksik.

---

## Adım 1 — Birebir metin mesajı (A ⇄ B)

**Yol:** A: Rehber → "Tuş takımını aç" → `+905321000413` → Sohbet başlat →
`A1-merhaba-beta` gönder. B: gelen sohbeti aç → `B1-cevap-alfa` gönder.

**Sonuç: ÇALIŞIYOR.** A→B mesajı ~saniyeler içinde ulaştı, B→A cevabı
ulaştı, A'da kendi mesajında `Okundu` görünüyor. Sohbet listesinde önizleme
ve okunmamış rozeti doğru.

Not: Rehber araması (`5321000413`) yalnız telefon rehberini süzüyor; rehberde
olmayan numarayla sohbet ancak tuş takımı diyaloğundan açılabiliyor. Bu bir
hata değil ama keşfedilmesi zor (WhatsApp'ta da benzer).

### Bulgu 3 — Gelen sohbetin başlığı ham kullanıcı UUID'si (ORTA)

- **Adımlar:** A, B'nin rehberinde yokken A'dan B'ye ilk mesajı gönder.
- **Gerçekleşen:** B'de sohbet listesinde ve sohbet başlığında
  `3b3663e9-3046-4ba9-acd6-dfdaf3fa510c` (A'nın sunucu userId'si) yazıyor.
  A'nın görünen adı (`QaAlfa`) ya da numarası yok.
- **Beklenen:** WhatsApp gibi numara ya da gönderenin profil adı
  (`~QaAlfa`); en kötü ihtimalle "Bilinmeyen kişi". İç kimlik kullanıcıya
  gösterilmemeli.
- **Ters yön:** A tarafında başlık numara (`+905321000413`) çünkü A sohbeti
  numarayla başlattı. Yani sorun yalnız *gelen ilk mesajla oluşturulan*
  sohbette.
- **Ek (Adım 4):** A'nın numarası B'nin telefon rehberine eklenip rehber
  yeniden eşlenince başlık `QaAlfa` oldu. Yani sorun yalnız rehberde olmayan
  gönderenlerde; onlarda yine UUID yerine numara/profil adı gösterilmeli.
- **Nereye bakmalı:** Gelen mesajla sohbet/kişi kaydı oluşturan yol
  (mesaj alma → conversation upsert). Görünen ad için ya mesaj zarfına
  (şifreli) profil adı eklenmeli ya da kişi kaydı userId→profil sorgusuyla
  doldurulmalı. Gizlilik nedeniyle numara sunucudan alınamıyorsa en azından
  görünen ad gösterilmeli.

### Bulgu 4 — İsimsiz kişilerin avatar harfi anlamsız (DÜŞÜK)

- **Gerçekleşen:** Numarayla kayıtlı kişilerin avatarı `9` (`+90…`'dan),
  UUID başlıklı sohbetin avatarı `33`.
- **Beklenen:** İsim yoksa genel kişi ikonu.

---

## Adım 2 — Birebir sesli arama (A → B)

**Yol:** A: sohbet → ⋮ → Sesli ara. B: gelen arama ekranı → Cevapla. ~36 sn
sonra B: Bitir.

**Sonuç: ÇALIŞIYOR.**
- B'de gelen arama ekranı uygulama ön plandayken anında açıldı (Reddet / Cevapla).
- Cevaplayınca iki tarafta da süre saydı; `FlutterWebRTCPlugin:
  onSelectedCandidatePairChanged`, `onAddTrack`, `onConnectionChangeCONNECTED`.
- B kapatınca A'da da arama kapandı. İki sohbete de kayıt düştü: A `Giden
  sesli arama 0:36`, B `Gelen sesli arama 0:38`.
- A'da Hoparlör düğmesi rotayı `speaker` yaptı.
- **Doğrulanamadı:** Sesin gerçekten duyulup duyulmadığı (insan kulağı
  gerekiyor). Medya yolu kuruldu ama ses içeriği test edilmedi.
- Bilgi: Bu senaryoda (uygulama ön planda) SC-* logunda hata yok.
  Gelen arama ekranında da arayan ham UUID olarak görünüyor (Bulgu 3).

## Adım 3 — Birebir görüntülü arama (B → A)

**Yol:** B: sohbet → ⋮ → Görüntülü ara. A: Cevapla. ~70 sn sonra A: Bitir.

**Sonuç: ÇALIŞIYOR (ses yönlendirme hatası hariç).**
- Görüntü iki yönde geliyor (ekran görüntüsüyle doğrulandı: A'nın yerel
  önizlemesi B'nin ana görüntüsü, B'ninki A'nınki).
- Kamera / Çevir / Sessize al düğmeleri var. Kapatma iki tarafa yansıdı.
  Kayıtlar: A `Gelen görüntülü arama 1:11`, B `Giden görüntülü arama 1:09`.
- Küçük: A'daki gelen arama ekranı yalnız "Gelen arama" diyor, görüntülü
  olduğunu belirtmiyor.

### Bulgu 5 — Görüntülü arama ahizeden başlıyor, arayanda düğme yanlış durumda (ORTA)

- **Adımlar:** B'den A'ya görüntülü arama başlat, A cevaplasın. İki
  telefonda `adb shell dumpsys audio | grep "Active communication device"`
  ve `dumpsys telecom` (Pending route).
- **Gerçekleşen:**
  - İki telefonda da aktif çıkış `type:earpiece`, Telecom rotası `TYPE_EARPIECE`.
  - **Arayan (B):** Hoparlör düğmesi `checked=true` (beyaz/açık) görünüyor
    ama ses ahizeden çıkıyor. İlk dokunuş düğmeyi kapalıya çeviriyor (rota
    hâlâ ahize), ancak ikinci dokunuş rotayı `speaker` yapıyor.
  - **Cevaplayan (A):** Hoparlör kapalı, ahize. Tek dokunuşla `speaker`
    oluyor (doğru).
- **Beklenen:** Görüntülü aramada telefon kulağa tutulmadığı için iki tarafta
  da varsayılan hoparlör (WhatsApp davranışı). Düğme durumu her zaman gerçek
  rotayı yansıtmalı.
- **Ek (Adım 6):** Grup görüntülü aramada da iki tarafta `type:earpiece`.
- **Kök neden (tahmin):** Arayan tarafta görüntülü arama için UI'daki
  `speakerOn` başlangıçta `true` yapılıyor, ama Telecom `ConnectionService`
  bağlanınca rota ahizeye çekiliyor (ya da hoparlör isteği Telecom'dan önce
  verilip ezilmiş). Bağlantı aktif olduktan sonra görüntülü aramada
  `CallEndpoint`/`setAudioRoute(ROUTE_SPEAKER)` istenmeli ve UI durumu
  Telecom'un `onCallAudioStateChanged`/`onAvailableCallEndpointsChanged`
  geri bildiriminden türetilmeli. Bkz. memory: Telecom entegrasyonu
  (audio routing, 2026-05-07).

---

## Adım 4 — Grup kurma + grup mesajı

**Yol:** A: Rehber → Yeni Grup → ad `QA-Grup-1` → Devam et → QaBeta seç →
"Grubu kur ve Kişileri Ekle". Sonra A `G1-alfa-gruba`, B `G2-beta-gruba`.

**Sonuç: ÇALIŞIYOR** (üye seçici sorunu hariç).
- Grup A'da açıldı (`Üyeler (2)`), B'nin listesine anında `QaAlfa grubu
  oluşturdu` ile düştü.
- Grup mesajları iki yönde ulaştı, gönderen adı gösteriliyor, `Okundu` var.
- SC-* logunda hata yok.

**Test için yapılan ortam değişikliği:** Bulgu 6 nedeniyle A'nın rehberine
`QaBeta +905321000413`, B'nin rehberine `QaAlfa +905321000412` eklendi
(Android Kişiler uygulaması), sonra uygulamada Rehber → "Tekrar Dene".

### Bulgu 6 — Rehberde olmayan, sohbet edilen kişi gruba eklenemiyor (ORTA)

- **Adımlar:** A, B ile (tuş takımından numarayla) sohbet etmiş; B A'nın
  telefon rehberinde yok. A: Yeni Grup → ad → Devam et.
- **Gerçekleşen:** Üye listesinde yalnız telefon rehberindeki eşleşmiş
  kişiler (`Grj-2`, `İos`). B yok. Arama kutusuna `5321000413` yazınca
  `Eşleşen sohbet yok` — B ile sohbet olduğu halde.
- **Beklenen:** Mevcut birebir sohbetlerin karşı tarafları da seçilebilmeli
  (metin zaten "sohbet" arıyormuş gibi diyor). Rehber sekmesi B'yi
  (`9 / +905321000413`) gösteriyordu, seçici göstermiyor — iki ekran farklı
  kaynaktan besleniyor.
- **Nereye bakmalı:** Yeni grup üye seçicisinin veri kaynağı (yalnız
  directory-eşleşmiş rehber); Rehber sekmesindeki birleşik listeyle aynı
  kaynağı kullanmalı.

### Bulgu 7 — Rehber araması tam numarayı bulmuyor (DÜŞÜK)

- **Gerçekleşen:** Rehber sekmesinde `532` → QaBeta bulunuyor;
  `5321000413` → `Sonuç bulunamadı`. Kayıtlı numara `+90 532 100 04 13`
  (boşluklu).
- **Beklenen:** Sorgu ve numara rakamlara indirgenip karşılaştırılmalı.

Ayrıca: Rehber sekmesinin sağ üstünde sürekli **"Tekrar Dene"** düğmesi
duruyor; bir hata durumunu mu gösteriyor yoksa yenile düğmesi mi, belirsiz.
Etiketi "Yenile" olmalı ya da hata varsa hata metni gösterilmeli.

---

## Adım 5 — Grup sesli araması (A → grup, 2 üye)

**Yol:** A: `QA-Grup-1` → ⋮ → Sesli ara. B: Cevapla. Mesh modu (SFU kapalı;
`sfuThreshold = 6`).

**Sonuç: ÇALIŞIYOR — hemen cevaplanınca.** 3. denemede B ~4 sn içinde
cevapladı: iki tarafta `2 katılımcı`, süre sayıyor; A'da
`onConnectionChangeCONNECTED`, Telecom `DIALING -> ACTIVE`; B'de `RINGING ->
ACTIVE`, `onAddTrack`. A `Bitir` deyince B'de de bitti. Kayıtlar: A `Giden
sesli arama 0:48`, B `Gelen sesli arama 0:47`.

İlk iki deneme başarısızdı; nedenleri aşağıda (Bulgu 8). Not: 2. denemede B'yi
test eden ben 61,5 sn'de cevapladım; A'nın çalma zaman aşımı 60 sn
(`lib/src/media/call_manager.dart:77`, `ringTimeout`). Bu deneme tek başına bir
hata kanıtı değil, ama zaman aşımı sonrası durum yönetimini ortaya çıkardı.

### Bulgu 8 — Zaman aşımı sonrası grup araması "ölü" kalıyor (ORTA)

Zaman çizelgesi (2. deneme, cihaz saatleri):

| Saat | Cihaz | Olay |
|---|---|---|
| 14:55:19.57 | A | Telecom `CONNECTING -> DIALING`, `getUserMedia(audio)` |
| 14:55:20.52 | B | Telecom `NEW -> RINGING` (gelen arama ekranı) |
| 14:56:21.49 | B | Cevapla → `RINGING -> ACTIVE`, 21.71 `getUserMedia` |
| 14:56:21.88 | A | `setDisconnected ... Code: (LOCAL)` (`ringTimeout` 60 sn doldu) |
| 14:56:22.09 | B | `setDisconnected ... Code: (LOCAL)` |

Sonuç: A `Giden sesli arama Başarısız`, B `Gelen sesli arama Başarısız`.
SC-DIAG raporu **yok** (`_startRingTimeout` → `_finish(CallState.failed)`
`_reportCallFailure` çağırmıyor).

1. deneme (14:50–14:51):
- A aramayı başlattı. ~7 sn sonraki ekran dökümünde A artık arama ekranında
  değil, grup sohbetindeydi; üstte `Devam eden sesli arama — Katıl` bandı ve
  `Giden sesli arama · Cevapsız · 14:50` kaydı vardı. **Bu "7 sn'de kapandı"
  gözlemi tekrar üretilemedi**; tek ekran dökümüne dayanıyor.
- B'de gelen arama ekranı **60 sn'den uzun süre çalmaya devam etti**. Cevapla
  → `Bağlanıyor… / 1 katılımcı` ekranında takıldı, sonra kapandı.
- A'da `Katıl` → 8 sn sonra `SC-DIAG call-manager.accept-group-call
  TimeoutException` (`call_manager.dart:818`, `_mediaKeyReady.future
  .timeout(mediaKeyTimeout)`): geç katılan, koordinatörden medya anahtarı
  bekliyor, ama koordinatör (A'nın kendisi) zaten çıkmıştı.
- Kayıtlar tutarsız: B cevapladığı halde `Gelen sesli arama Cevapsız`; A'nın
  kendi başlattığı aramaya katılması `Gelen sesli arama Başarısız`.

**Beklenen:**
- Arayanın çalma süresi dolunca sunucu/istemci arananlara iptal göndermeli,
  arananın gelen arama ekranı aynı anda kapanmalı; arayan için kayıt
  `Cevapsız` olmalı, `Başarısız` değil (çalma zaman aşımı hata değil).
- Aktif katılımcısı kalmayan grup aramasına "Katıl" gösterilmemeli; ya da
  katılım, koordinatör yokken yeni bir arama başlatmalı.
- Cevaplanan arama `Cevapsız` diye kaydedilmemeli.

**Nereye bakmalı:** `call_manager.dart` `_startRingTimeout` (~2091) — çalma
zaman aşımında `CallState.failed` yerine `missed`/`noAnswer` benzeri bir durum
ve aranana iptal sinyali. Grup çağrısında aranan tarafın kendi
`ringTimeout`'u ve arayanın iptali B'ye ulaşıyor mu (B 60 sn'den fazla çaldı).
`_acceptGroupCall` geç katılımda koordinatör yoksa anahtar beklemek yerine
erken başarısız olmalı. Teşhis için: sessiz `_finish(CallState.failed)` yollarına
(`:378`, `:1641`, `:1668`, `:1918`, `:1922`, `:2096`) `_reportCallFailure`
eklenmeli; şu an bu yolların hangisinin çalıştığı logdan görülemiyor.

### Bulgu 9 — Bitmiş grup araması için "Katıl" bandı kalıyor (DÜŞÜK)

- 3. denemede A `Bitir` dedi, B'nin araması da bitti (2 kişilik). A'nın grup
  sohbetinde `Devam eden sesli arama — Katıl` bandı göründü, ~20 sn içinde
  kayboldu.
- **Beklenen:** Son katılımcı çıkınca bant hemen kalkmalı (sunucu
  `group_call_status isActive=false` hemen yayınlamalı ya da istemci kendi
  çıkışında bandı yerelde kapatmalı).

---

## Adım 6 — Grup görüntülü araması (B → grup)

**Yol:** B: `QA-Grup-1` → ⋮ → Görüntülü ara. A ~4 sn içinde Cevapla. ~30 sn
sonra B: Bitir.

**Sonuç: ÇALIŞIYOR** (ses yönlendirme hariç).
- İki tarafta `2 katılımcı`, ızgara görünüm: `Sen` + karşı tarafın adı
  (`QaBeta` / `QaAlfa`), görüntü iki yönde doğru (ekran görüntüsüyle
  doğrulandı). `onConnectionChangeCONNECTED` ~0,7 sn'de.
- B kapatınca A'da da bitti. Kayıtlar: A `Gelen görüntülü arama 0:32`, B
  `Giden görüntülü arama 0:33`.
- Ses iki tarafta ahizeden (Bulgu 5'e eklendi). A'da arama bitince yine
  geçici `Katıl` bandı (Bulgu 9).

---

## Adım 7 — Medya, dosya, anket (A → B, birebir)

Test dosyaları iki telefona `/sdcard/Download/` altına kondu:
`qa_foto_1.png` (1.104.728 bayt), `qa_dosya_1.txt`, `qa_ikili_300k.bin`
(300.000 rastgele bayt).

**7a Fotoğraf — ÇALIŞIYOR.** Ek ekle → Galeri → sistem fotoğraf seçici →
Bitti → önizleme + açıklama `M1-foto-aciklama` → Gönder. A: `SC-FILE
tx-progress parts=9 total=9`, B: `rx-complete bytes=1104728`. B'de
küçük resim ve açıklama görünüyor (ekran görüntüsüyle doğrulandı), dokununca
tam ekran açılıyor. Sohbet listesi önizlemesi `Fotoğraf · M1-foto-aciklama`.

**7b Dosya — ÇALIŞIYOR.** Ek ekle → Dosya → sistem dosya seçici →
`qa_ikili_300k.bin` → önizleme (`292 KB, application/octet-stream`) →
Gönder. 3 parça (128 KB chunk). B: `rx-complete bytes=300000`. B'de
`Açmak için dokunun` → dosya ekranı (`Paylaş`, `Uygulamayla aç`).
**Bütünlük:** B'deki dosyanın sha256'sı orijinalle aynı (`b988c2db…`).

**7c Anket — ÇALIŞIYOR.** Ek ekle → Anket → soru + 2 seçenek, Tekli seçim
→ Oluştur. B'de anında göründü. B `Evet` → A'da `Evet 1`. A `Hayir`,
B oyunu `Hayir`'a değiştirdi → iki tarafta `Evet 0 / Hayir 2` (oy değiştirme
doğru).

Not (test aracı): Anket diyaloğu açıkken `KEYCODE_ESCAPE` diyaloğu girdilerle
birlikte kapatıyor; Android geri tuşu davranışıyla tutarlı, hata sayılmadı.

### Bulgu 10 — Gönderen kendi mesajından sonra en alta kaymıyor (DÜŞÜK)

- **Adımlar:** Sohbet en altta değilken (ör. bir arama kaydı ekrandayken)
  dosya ya da anket gönder.
- **Gerçekleşen:** Ekran yerinde kalıyor; sağ altta `En yeni mesaja git`
  rozeti `2` (az önce gönderilen kendi iki mesajım) gösteriyor.
- **Beklenen:** Kullanıcı kendi mesajını gönderince liste en alta kaymalı;
  rozet yalnız okunmamış *gelen* mesajları saymalı.

### Bulgu 11 — Alınan dosyalar yerelde şifresiz (GÜVENLİK NOTU)

- `adb shell run-as com.securechat.app.debug` ile
  `./files/media/received_files/1791806666623_qa_ikili_300k.bin` düz içerik
  olarak okunabildi (orijinalle aynı sha256).
- Veritabanı SQLCipher ile şifreli, ama medya/dosya içerikleri uygulamanın
  özel dizininde düz metin. Normal cihazda başka uygulama erişemez; ancak root,
  adb yedekleme (`allowBackup`'a bağlı) veya adli imaj durumunda mesaj
  içeriği korunmuyor. CLAUDE.md "Hassas veriler … sıfırlanır / SQLCipher"
  ilkesiyle uyumu ürün kararı. Gönderen tarafta da aynısı olabilir
  (kontrol edilmedi).
- **Öneri:** Dosyaları DB anahtarından türetilmiş anahtarla şifreli sakla,
  görüntülerken geçici çöz; ya da en azından tek gösterimlik içerikte bunu
  zorunlu yap (bkz. Adım 8).

---

## Adım 8 — Tek gösterimlik gönderimler (A → B, birebir)

| Tür | Nasıl | Alıcı | Yeniden açma | Kalıntı |
|---|---|---|---|---|
| Metin | Giriş çubuğu `Tek gösterim` anahtarı → yaz → Gönder | `Açmak için dokunun` → `Tek gösterimlik · ekran korumalı` tam ekran metin | `Bu medya artık açılamaz` ✔ | — |
| Fotoğraf | Galeri → önizlemede `1` düğmesi (mavi) → Gönder | `Tek gösterimlik fotoğraf · Açmak için dokunun` → tam ekran, `Kapatmak için dokunun · bir daha açılamaz` | Açılmıyor ✔ | Uygulama dizininde 1 MB'lık çözülmüş dosya yok ✔ |
| Dosya (.txt) | Dosya → önizlemede `1` → Gönder | Açılıyor (ad + boyut + `Uygulamayla aç`) | Açılmıyor ✔ | Düz metin içerik uygulama dizininde bulunamadı ✔ |
| Anket | Anahtar açık → Anket → Oluştur | **Normal anket** olarak geldi | — | Bulgu 15 |

**Sonuç:** Metin, fotoğraf ve dosya için tek gösterim çalışıyor (bir kez açılıyor,
sonra yakılıyor). Metin anahtarı gönderimden sonra kendiliğinden kapanıyor
(anket hariç). Etiket/durum hataları ve bir gizlilik açığı aşağıda.

### Bulgu 12 — Tek gösterimlik dosyada "Uygulamayla aç" (ORTA, güvenlik)

- **Adımlar:** Tek gösterimlik `.txt` gönder; alıcıda aç.
- **Gerçekleşen:** Görüntüleyicide `Uygulamayla aç` düğmesi var
  (`Tek gösterimlik · ekran korumalı` başlığıyla birlikte). Basılırsa içerik
  dış uygulamaya (FileProvider/intent) verilir; o uygulama kalıcı kopya
  alabilir, tek gösterim garantisi biter. (Kopya bırakmamak için testte
  basılmadı.)
- **Beklenen:** Tek gösterimlik içerikte dışa aktarma/paylaşma/uygulamayla
  açma olmamalı; içerik yalnız uygulama içinde gösterilmeli (metin dosyası
  için uygulama içi önizleme), desteklenmeyen tür ise "bu tür tek gösterimlik
  gönderilemez" denmeli.

### Bulgu 13 — Gönderende tek gösterim durumu yanlış (DÜŞÜK)

- Fotoğraf/dosya gönderilir gönderilmez A'da `1 · Açıldı · Bu medya artık
  açılamaz` — B henüz açmamışken (B'de `Açmak için dokunun` duruyordu).
- Tek gösterimlik **metin** için A ve B'de `Bu medya artık açılamaz` —
  metin için "medya" yanlış.
- **Beklenen:** Gönderende `Tek gösterimlik · Gönderildi`, alıcı açınca
  `Açıldı`. Metinde "Bu mesaj artık açılamaz".

### Bulgu 14 — Tek gösterimlik dosya "fotoğraf" diye etiketleniyor (DÜŞÜK)

- `qa_dosya_1.txt` (text/plain) tek gösterimlik gönderildi; B'deki balon
  `1 · Tek gösterimlik fotoğraf · Açmak için dokunun`. Açınca doğru dosya
  görünüyor; yalnız etiket yanlış. MIME türüne göre "Tek gösterimlik dosya".

### Bulgu 15 — Tek gösterim anahtarı ankette yok sayılıyor (DÜŞÜK)

- Giriş çubuğunda `Tek gösterim` açık → Ek ekle → Anket → Oluştur.
- Anket normal anket olarak gidiyor, uyarı yok; anahtar `checked=true`
  kalıyor (sonraki metin mesajı beklenmedik şekilde tek gösterimlik gidebilir).
- **Beklenen:** Ya anket menüsü tek gösterim açıkken devre dışı/uyarılı olmalı,
  ya da anahtar ankete uygulanmayacağı belirtilip sıfırlanmalı.

### Bulgu 16 — Debug derlemede "ekran korumalı" yazısı doğru değil; "1" düğmesinin etiketi yok (DÜŞÜK)

- Tek gösterim görüntüleyicisi `ekran korumalı` diyor ama `adb exec-out
  screencap` içeriği yakaladı (ekran görüntüsü alındı). Sebep:
  `MainActivity.kt:534` `applyScreenProtectionPolicy` debug derlemede
  `com.securechat.DEBUG_ALLOW_SCREEN_CAPTURE` meta-data'sı varsa FLAG_SECURE'ı
  kaldırıyor (bilinçli QA ayarı). Release etkilenmez. Ama tek gösterim ekranı
  korumayı kendisi zorlamıyor (`enableScreenProtection` kanal yöntemi var,
  çağrılmıyor); debug istisnası buraya da sızıyor. Öneri: tek gösterim
  görüntüleyicisi açılırken FLAG_SECURE her derlemede zorlansın.
- Medya önizlemesindeki tek gösterim düğmesinin erişilebilirlik metni yalnız
  `1`; açık/kapalı durumu (`checked`) da bildirilmiyor. TalkBack kullanıcısı ne
  olduğunu anlayamaz.

---

## Adım 9 — Grupta medya / anket / tek gösterim (`QA-Grup-1`)

| Test | Yön | Sonuç |
|---|---|---|
| Fotoğraf + açıklama `GM1-grup-foto` | A → grup | ✔ `SC-FILE tx-progress group=true parts=23 total=23`, B `rx-complete bytes=1104728 group=true`, balonda gönderen adı `QaAlfa` |
| Anket `GA-grup-anket` (Kirmizi/Mavi) | B → grup | ✔ A'da göründü; A `Kirmizi` → iki tarafta `Kirmizi 1` |
| Tek gösterimlik fotoğraf | B → grup | ✔ A'da `QaBeta · 1 · Tek gösterimlik fotoğraf`, bir kez açıldı, sonra açılmıyor |

Bulgu 13 (gönderende hemen `Açıldı`) grupta da var. Yeni bulgu yok.

Not (test aracı): Fotoğraf önizlemesinde açıklama yazıldıktan sonra
`KEYCODE_ESCAPE` klavyeyi kapatmadı ve `ENTER` açıklamaya satır sonu ekledi
(`GM1-grup-foto\n`). Açıklama alanı çok satırlı olduğu için beklenen olabilir;
hata sayılmadı.

---

## Kapsam dışı / test edilmedi

- Uygulama arka planda ya da ekran kilitliyken mesaj bildirimi ve gelen arama
  (FCM / ConnectionService ile uyandırma). Tüm testler iki uygulama ön plandayken
  yapıldı.
- Sesin gerçekten duyulması (insan kulağı gerekiyor). Medya yolu
  (`CONNECTED`, `onAddTrack`) doğrulandı.
- 3+ kişilik grup araması ve SFU'ya (Janus) geçiş: yalnız 2 cihaz var;
  canlı sunucuda `SFU_ENABLED` boş, `JANUS_API_SECRET` yok.
- Sesli mesaj, kamera ile çekim, video gönderimi, süreli mesajlar.
- Sunucu logu: deploy sonrası SSH oturumu askıda kaldı (master açık ama komut
  zaman aşımı); sunucu logu yalnız ERROR seviyesinde, istemci tarafı
  teşhis yeterli oldu.

## Test sonrası ortam durumu

- A ve B rehberine birbirinin numarası eklendi (QaAlfa / QaBeta).
- `/sdcard/Download/` altında `qa_foto_1.png`, `qa_dosya_1.txt`,
  `qa_ikili_300k.bin` (iki cihazda).
- Sohbetlerde test mesajları, `QA-Grup-1` grubu.
