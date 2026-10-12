# QA Bulguları ve Çözüm Planı — 2026-10-12

Bu belge, 2026-10-12'deki iki cihaz testinde bulunan **16 bulgunun** tamamını,
kodda doğrulanmış kök nedenleriyle ve **yapılacak işler** listesiyle anlatır.
Yeni bir oturumda bu belgeyi açıp maddeleri sırayla uygulamak için yazıldı.
Testin ham kaydı (ekran dökümleri, zaman damgaları):
[`QA_IKI_CIHAZ_2026-10-12.md`](QA_IKI_CIHAZ_2026-10-12.md).

> Satır numaraları `1774aaa` commit'indeki koda göredir. Kod değiştiyse
> fonksiyon adıyla arayın.

---

## 0. Yeni oturum için hazırlık

### 0.1 Oturuma verilecek önerilen talimat

```
docs/QA_BULGU_COZUM_PLANI_2026-10-12.md belgesini oku. Öncelik sırasına göre
(bölüm 1) maddeleri tek tek uygula. Her madde için: önce başarısız olan testi
yaz, sonra düzelt, testler yeşil olunca yalnız o maddenin dosyalarını
conventional commit ile commitle ve sıradakine geç. "Doğrulanacak" yazan
hipotezleri önce doğrula; yanlışsa belgeye not düş. Bitince belgedeki
"Durum" sütununu güncelle.
```

### 0.2 Proje kuralları (CLAUDE.md + kullanıcı tercihi)

- Kod İngilizce, yorum/dokümantasyon Türkçe, UI metinleri `lib/l10n/app_tr.arb`
  (+ `app_en.arb`), sonra `flutter gen-l10n`.
- Conventional commits (`fix:`, `feat:`, `test:` …). **Her madde ayrı commit**,
  yalnız o maddenin dosyaları; paylaşılan ağaçta branch değiştirme.
- Plaintext mesaj içeriği asla loga yazılmaz.
- Deploy sırası: önce sunucu, sonra istemci.

### 0.3 Test komutları

```bash
# Flutter (repo kökü: flutter_securechat/)
export PATH="/home/user497/flutter/bin:$HOME/.cargo/bin:$PATH"
export SECURECHAT_SQLCIPHER_PATH=/usr/lib/x86_64-linux-gnu/libsqlcipher.so.1
flutter test                               # ~1307 test, hepsi yeşil olmalı
dart analyze

# Sunucu
cd server_hardened && ./gradlew :signaling-server:test --offline
# Not: GroupCallSignalingContractTest / WebSocketRoutingE2ETest tam suite
# yükünde aralıklı düşer, tek başına geçer (bilinen durum).

# Debug APK (iki QA telefonu için)
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=SECURECHAT_LOCAL_DIAGNOSTICS=true
```

### 0.4 Cihaz ortamı

| | |
|---|---|
| Cihaz A | `R5GL2452S4A` — QaAlfa `+905321000412` |
| Cihaz B | `R5GL2452SJK` — QaBeta `+905321000413` |
| Paket | `com.securechat.app.debug`, Activity `com.securechat.app/com.securechat.app.MainActivity` |
| Sunucu | 185.22.184.114, jar `8168ce8`, dev profil, `SFU_ENABLED` boş, `JANUS_API_SECRET` yok |
| Log | `adb -s <cihaz> logcat -d \| grep "I flutter : SC-"` |
| Ekran dökümü | `adb -s <cihaz> shell uiautomator dump` (yardımcı betik ek A'da) |

---

## 1. Öncelik sırası

| Sıra | # | Önem | Başlık | Taraf | Durum |
|---|---|---|---|---|---|
| 1 | 1 | YÜKSEK (gizlilik) | Çıkış, önceki hesabın yerel verisini silmiyor | İstemci | Düzeltildi (955e825) |
| 2 | 8 | ORTA (sunucu kökenli) | Grup araması bitince "bitti" yayını gitmiyor (Janus sınıfı başlatılamıyor) + zaman aşımı durumları | Sunucu + istemci | Düzeltildi (2a17afc sunucu, fa5d841 istemci, e597c10 test) |
| 3 | 12 | ORTA (güvenlik) | Tek gösterimlik dosyada "Uygulamayla aç" | İstemci | Düzeltildi (91cdd94) |
| 4 | 5 | ORTA | Görüntülü arama ahizeden başlıyor, hoparlör düğmesi yanlış durumda | İstemci (Android) | Düzeltildi (3095165) |
| 5 | 6 | ORTA | Rehber eşitlemesi elle eklenen kişiyi siliyor, grup seçicide görünmüyor | İstemci | Düzeltildi (c1cae56) |
| 6 | 3 | ORTA | Rehberde olmayan gönderenin adı UUID | İstemci | Düzeltildi (dcae8a6, d91e066) |
| 7 | 13 | DÜŞÜK | Tek gösterim: gönderende sahte "Açıldı", metinde "medya" | İstemci | Düzeltildi (8f6641f) |
| 8 | 9 | DÜŞÜK | Bitmiş grup araması için "Katıl" bandı kalıyor | İstemci | Düzeltildi (02f136e) |
| 9 | 2 | DÜŞÜK | "son görülme 1 Oca 1970" | İstemci | Düzeltildi (cf90899) |
| 10 | 10 | DÜŞÜK | Kendi mesajından sonra en alta kaymıyor | İstemci | Düzeltildi (5a33968) |
| 11 | 14 | DÜŞÜK | Tek gösterimlik dosya "fotoğraf" diye etiketleniyor | İstemci | Düzeltildi (6cb8ee4) |
| 12 | 15 | DÜŞÜK | Tek gösterim anahtarı ankette yok sayılıyor | İstemci | Düzeltildi (476079f) |
| 13 | 16 | DÜŞÜK | Tek gösterim ekranı FLAG_SECURE'ı kendisi zorlamıyor; "1" düğmesinin erişilebilirlik etiketi yok | İstemci | Düzeltildi (ccd5a67) |
| 14 | 7 | DÜŞÜK | Rehber araması tam numarayı bulmuyor | İstemci | Düzeltildi (ac38a0d) |
| 15 | 4 | DÜŞÜK | İsimsiz kişilerin avatarı anlamsız | İstemci | Düzeltildi (79acba5) |
| 16 | 11 | KARAR | Alınan dosyalar yerelde şifresiz | İstemci | Ürün kararı |


### 1.1 Uygulama notları (2026-10-12, uygulayan oturum)

- **Bulgu 8a doğrulandı:** canlı `sunucu.log`'da grup HANGUP anında
  `WebSocketRoutes.kt:623` → `JanusOrchestrator.<clinit>` →
  `JANUS_API_SECRET or JANUS_API_SECRET_FILE is required` (11:52) ve
  sonrasında `NoClassDefFoundError` (11:56). Handler bitiş yayınından önce
  ölüyordu.
- **"Aralıklı 13 sunucu test hatası"nın kök nedeni bulundu:**
  `GroupCallSessionStoreLincheckTest` her senaryoda global store'da arama
  açıp kapatmıyordu; `MAX_ACTIVE_CALLS` (1024) doluyor, sonraki grup arama
  testleri `SERVER_CAPACITY_REACHED` ile zincirleme düşüyordu (e597c10).
  Tam suite artık 1272/1272.
- **Bulgu 2 kök nedeni plandakinden farklı:** sunucu "çevrimiçi" bilgisini
  bağlantı başına ve yalnız `presence_update` alınca tutuyor; istemci bunu
  yalnız ön plana geçişte gönderiyordu. Uygulama açıkken soket kendiliğinden
  yeniden bağlanınca (ağ değişimi, sunucu deploy'u) durum bildirilmiyor,
  karşı taraf çevrimdışı + `lastSeen=0` görüyordu. İstemci artık her yeni
  bağlantıda durumu yeniden bildiriyor; `lastSeen<=0` "bilinmiyor".
- **Bulgu 12:** uygulamada video oynatıcı olmadığı için tek gösterim yalnız
  `image/*` ve `text/plain` için izinli (plan video da diyordu).
- **Bulgu 3 madde 3:** "Rehbere ekle" eklenmedi — alıcı karşı tarafın
  numarasını bilmiyor (numara paylaşımı varsayılan kapalı); şeritte
  Engelle + Kapat var.
- **Bulgu 13 madde 2 uygulandı:** şifreli `view_once_opened` kontrolü;
  okundu bilgisi kapalıysa gönderilmez.
- **Yeni özel kontrol türleri** (`shared_profile_name`, `view_once_opened`)
  eski istemcide "desteklenmeyen kontrol" olarak reddedilir; iki QA
  telefonu birlikte güncellenmeli. iOS native tarafı (Swift) yalnız kanal
  adları için güncellendi, Mac'te derlenmedi.
- **Bulgu 11** ürün kararı bekliyor.

---

## Bulgu 1 — Çıkış, önceki hesabın yerel verisini silmiyor (YÜKSEK, gizlilik)

### Gözlem
- Cihaz A'da eski QA hesabı (`+908976464464`) → Ayarlar → **Çıkış yap** →
  aynı cihazda yeni numarayla (`+905321000412`) yeni kayıt.
- Yeni hesabın sohbet listesinde eski hesabın `+901646767346` sohbeti duruyor.
  Açınca 7–8 Ekim mesajları **düz metin** (`merhaba-test-1`, `cevap-test-2`,
  `Sa`) ve arama geçmişi görünüyor. Cihaz B'de de aynısı.
- Yeni hesap bu eski sohbete yazarsa, artık başka bir hesaba ait olan eski
  kimliğe gönderim denenir.

### Kök neden (doğrulandı)
- `lib/src/features/settings/settings_screen.dart` ~:219–233 — "Çıkış yap"
  `onTap` yalnız `container.pushRuntime?.coordinator.unregister()` ve
  `auth.logout()` çağırıyor.
- `lib/src/auth/auth_coordinator.dart:143` `logout()` yalnız sunucu
  token'larını iptal ediyor, `_olmPreKeys.clearLocalCryptoState()` ve
  `_session.clearAndPersist()` çağırıyor. Sohbet, mesaj, kişi, arama kaydı ve
  medya **silinmiyor**.
- Tam silme kodu zaten var: `lib/src/settings/account_data_service.dart:33`
  `deleteLocalData()` → push kaydını siler, zamanlanmış mesajları kapatır,
  `auth.logout()`, `_database.clearAll()` (`secure_chat_database.dart:403`)
  ve medya, profil ve yedek dizinlerini (`app_container.dart:941–945`) siler.
  Ayarlar'daki **ayrı** "Yerel verileri sil" öğesi bunu kullanıyor
  (`settings_screen.dart` ~:192–203 → `_confirmLocalDelete` ~:506–535 →
  `_runAndLeave(context, accountData.deleteLocalData)`). **"Çıkış yap" ise bu
  yolu kullanmıyor**; kullanıcı yalnız çıkış yapınca veri kalıyor.

### Yapılacaklar
1. **Çıkışı tam silmeye bağla.** `settings_screen.dart` çıkış `onTap`'i:
   - Önce onay diyaloğu: "Çıkış yapınca bu cihazdaki tüm mesajlar, medya ve
     arama geçmişi silinir. Hesabınız sunucuda kalır; tekrar girişte geçmiş
     geri gelmez." (TR + EN arb anahtarları, örn. `logout_confirm_title`,
     `logout_confirm_body`).
   - Onaylanırsa `_runAndLeave(context, accountData.deleteLocalData)` çağır
     (`accountData = container.accountDataRuntime?.service`, ekranın
     `build`'inde zaten var: ~:45). Push kaydını da o siliyor; ayrı
     `unregister()` çağrısı gereksiz olur. En basit uygulama: çıkış
     `onTap`'ini `_confirmLocalDelete` benzeri, çıkış metinli bir diyaloğa
     yönlendirmek.
   - `accountData` null ise (servis kurulamadıysa) mevcut yola düş, ama
     madde 2'deki sahip kontrolü bir sonraki girişte veriyi yine temizler.
   - `_runAndLeave` zaten `/auth`'a dönüyor; değilse mevcut davranışı koru.
2. **Savunma katmanı (farklı kullanıcıyla girişte silme):** Veritabanında bir
   "sahip" kaydı tut (ör. `SecureChatDatabase` içinde küçük bir meta/ayar
   koleksiyonu: `ownerUserId`). Başarılı kayıt/giriş/kurtarma sonrası
   (`auth_coordinator.dart` register/login yolları ve
   `secure_account_recovery_coordinator.dart`):
   - `ownerUserId` boşsa → yaz.
   - `ownerUserId != yeni userId` → `clearAll()` + yönetilen dizinleri sil
     (yani `deleteLocalData` gövdesindeki `_clearDeviceData`), sonra yeni
     `ownerUserId`'yi yaz.
   Bu, eski sürümle çıkış yapılmış ve verisi kalmış cihazları da temizler.
   Arka plan isolate'i (`lib/src/background/background_tasks.dart`) aynı
   veritabanını açıyor; silme sırasında oturum zaten kapalı olduğu için yazma
   yapmaz, ama `_refreshLocalState` sonrası boş görmesi test edilmeli.
3. **Ölü sohbet temizliği:** Madde 2 bunu kapsar. Ek olarak, silinmiş/var
   olmayan bir kullanıcıya gönderimde (`prekey 404`) sohbet "Bu kişi artık
   SecureChat kullanmıyor" olarak işaretlenebilir (ayrı iş, isteğe bağlı).

### Testler
- Birim: `test/account_data_service_test.dart` (varsa genişlet) — çıkış
  sonrası `database.conversations/messages/contacts/callLogs` boş, medya
  dizini yok.
- Birim: `auth_coordinator` — `ownerUserId` farklıyken girişte `clearAll`
  çağrılıyor; aynıyken çağrılmıyor.
- Widget: Ayarlar → Çıkış → onay diyaloğu çıkıyor; İptal hiçbir şey silmiyor.
- Cihaz: A'da çıkış → yeni numarayla kayıt → sohbet listesi **boş**.

### Kabul kriteri
Çıkış ya da farklı hesapla giriş sonrası, önceki hesabın hiçbir mesajı,
medyası, kişisi veya arama kaydı uygulamada görünmüyor ve uygulama dizininde
kalmıyor (`adb shell run-as com.securechat.app.debug ls files/media`).

---

## Bulgu 8 — Grup araması: bitiş yayını gitmiyor, zaman aşımı sonrası "ölü" arama (ORTA)

### Gözlem (zaman çizelgesi, cihaz saatleri)
**2. deneme:**

| Saat | Cihaz | Olay |
|---|---|---|
| 14:55:19.57 | A | Telecom `CONNECTING -> DIALING`, `getUserMedia(audio)` |
| 14:55:20.52 | B | Telecom `NEW -> RINGING` |
| 14:56:21.49 | B | Cevapla → `RINGING -> ACTIVE` |
| 14:56:21.88 | A | `setDisconnected Code: (LOCAL)` — 60 sn `ringTimeout` doldu |
| 14:56:22.09 | B | `setDisconnected Code: (LOCAL)` |

Kayıtlar: A `Giden sesli arama · Başarısız`, B `Gelen sesli arama · Başarısız`.
SC-DIAG raporu yok.

**1. deneme:**
- B'nin gelen arama ekranı **60 sn'den uzun** çaldı. Cevapla →
  `Bağlanıyor… / 1 katılımcı` ekranında takıldı.
- A'da `Devam eden sesli arama — Katıl` bandı çıktı. `Katıl` → 8 sn sonra
  `SC-DIAG call-manager.accept-group-call TimeoutException`
  (`call_manager.dart:818`, `_mediaKeyReady.future.timeout(mediaKeyTimeout)`).
- Kayıtlar tutarsız: B cevapladığı halde `Cevapsız`; A'nın kendi aramasına
  katılması `Gelen sesli arama · Başarısız`.
- ~7 sn içinde A'nın arama ekranının kapandığı tek bir ekran dökümünde
  görüldü, **tekrar üretilemedi**.

**3. deneme** (B ~4 sn'de cevapladı): sorunsuz, `2 katılımcı`, `CONNECTED`.

### Kök neden 8a — SUNUCU (kodla doğrulandı, canlı logla doğrulanacak)
- `server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/JanusOrchestrator.kt:29`
  `object JanusOrchestrator`, `:36–37`:
  `private val janusApiSecret = requireSecret("JANUS_API_SECRET")`.
  Kotlin `object`'inde bu alan **sınıf başlatıcısında** çalışır. Sır yoksa
  sınıfa **ilk erişim** `ExceptionInInitializerError`, sonraki erişimler
  `NoClassDefFoundError: Could not initialize class …JanusOrchestrator`
  fırlatır. Bu, `hasActiveRoom()` gibi Janus'la ilgisiz yardımcılar için de
  geçerlidir.
- Canlıda SFU kapalı (`Application.kt:96` `SfuPolicy.isEnabled()` false), sır
  yok. Mesh grup araması bu sınıfa normalde hiç dokunmaz, **ama**:
  - `WebSocketRoutes.kt` ~:589–630 — `call_control` `HANGUP`,
    `recipientId == "server"`: `removeParticipant` → kalan ≤1 ise
    `GroupCallSessionStore.end(...)` → **`JanusOrchestrator.hasActiveRoom(...)`**
    (:623) → `broadcastGroupCallEnded(...)`. `hasActiveRoom` fırlatırsa
    `broadcastGroupCallEnded` **hiç çalışmaz**: kalan üye "arama bitti"
    almaz, gelen arama ekranı çalmaya devam eder.
  - Aynı desen WebSocket kopma yolunda: `WebSocketRoutes.kt` :338, :355, :389.
- Testler bunu yakalayamıyor: `server_hardened/signaling-server/build.gradle.kts:229–234`
  test ortamına **her zaman** `JANUS_API_SECRET`/`JANUS_ADMIN_SECRET` koyuyor.
- **Doğrulama (önce yap):** Sunucuda
  `grep -nE "Could not initialize class|ExceptionInInitializerError" /root/securechat/sunucu.log | tail`
  — grup araması bitişlerinde bu hatalar görünmeli. (Deploy sonrası
  `Thread-4` içinde `JanusOrchestrator.<clinit>` hatası görüldü. Bu, eski
  sürecin kapanış kancasından `destroyAllRooms` olabilir; HANGUP yolundaki
  hata ayrıca aranmalı.)

### Kök neden 8b — İSTEMCİ (kodla doğrulandı)
- `lib/src/media/call_manager.dart:77` `ringTimeout = 60 sn`, `:2091–2097`
  `_startRingTimeout` → `_finish(CallState.failed, notifyPeer: true)`. Çalma
  zaman aşımı **hata** olarak kaydediliyor (`Başarısız`), `_reportCallFailure`
  da çağrılmıyor (log yok).
- `_finish` (~:1951–1977) grup aramasında önce **her üyeye `reliable: true`**
  `HANGUP` gönderip ACK bekliyor, **sonra** sunucuya `HANGUP`
  (`reliable: false`) gönderiyor. Sunucu bildirimi ACK beklemeleri kadar
  gecikiyor (Bulgu 9'un da nedeni).
- Geç katılım (`_acceptGroupCall`, ~:797–818): koordinatör yoksa ya da çağrı
  bitmişse 8 sn medya anahtarı bekleyip `TimeoutException` ile düşüyor.
  Önce arama durumunu sunucudan sormuyor.
- Sessiz `_finish(CallState.failed)` yolları (rapor yok): `:378`, `:1641`,
  `:1668`, `:1918`, `:1922`, `:2096`. Hangisinin çalıştığı logdan görülemiyor.

### Yapılacaklar
**Sunucu (önce):**
1. `JanusOrchestrator`'da sırları **tembel** oku: `private val janusApiSecret by lazy { requireSecret(...) }`
   (ya da sırları yalnız `init()` ve Janus'a gerçekten bağlanan
   fonksiyonlarda oku). `hasActiveRoom`, `getRoomInfo` gibi yalnız bellek
   haritasına bakan fonksiyonlar sınıf başlatmayı tetiklemesin ya da
   başlatma sır gerektirmesin.
2. `WebSocketRoutes.kt` HANGUP ve kopma yollarında `broadcastGroupCallEnded`'i
   Janus temizliğinden **önce** çağır; Janus temizliğini `runCatching` +
   `logger.error` (içerik yok) ile sar. Bitiş yayını hiçbir koşulda
   atlanmamalı.
3. Test: `build.gradle.kts` test ortamı sırları koyduğu için, sırsız ortamı
   simüle eden ayrı bir test görevi ya da `SecretSource` / `requireSecret`'e
   enjekte edilebilir ortam haritası ekle. Senaryo: SFU kapalı, sır yok →
   2 kişilik grup araması → koordinatör `HANGUP` → kalan üye
   `group_call_ended` (ya da mevcut bitiş çerçevesi) alıyor.
4. Deploy: sunucu jar'ı (deploy yöntemi `reference_server_deploy` hafızasında:
   `/root/securechat/deploy_vN.sh`, yalnız `expected=` sha256 değişir).

**İstemci:**
5. Çalma zaman aşımı için ayrı terminal durum: `CallState.noAnswer` (ya da
   mevcut `missed`) — giden için kayıt `Cevapsız`, `Başarısız` değil.
   `_startRingTimeout` → `_finish(CallState.noAnswer, action: 'HANGUP')`.
   `_saveLog` eşlemesini ve `call_screen.dart` etiketlerini güncelle.
6. `_finish` grup bildirim sırası: sunucuya `HANGUP`'ı **önce** ve beklemeden
   gönder, üyelere `reliable` gönderimleri sonra/paralel yap
   (`Future.wait`).
7. Aranan taraf: gelen grup araması çalarken koordinatörden `HANGUP` ya da
   sunucudan bitiş gelince ekran hemen kapanmalı (`_handleControl` →
   `_removeGroupPeer` → `peers.isEmpty` → `_finish`). Bunun için birim test
   yaz. Aranan tarafın kendi `ringTimeout`'u arayanınkiyle yarışmasın:
   aranan için `ringTimeout + 5 sn` tampon makul.
8. Geç katılım: `_acceptGroupCall` (late join) başında `activeGroupCall` /
   `group_call_status` ile çağrının aktif ve koordinatörünün çevrimiçi olduğunu
   doğrula. Değilse anahtar beklemeden "Arama sona erdi" göster ve kayıt
   açma.
9. Cevaplanan aramayı `Cevapsız` yazma: `_finish` içindeki `missedCalls`
   koşulu (`session.state == CallState.ringing`) yalnız gerçekten
   cevaplanmamışsa tetiklenmeli. Kabul anında state `connecting`'e geçiyor
   mu, kontrol et.
10. Sessiz `_finish(CallState.failed)` yollarının hepsine
    `_reportCallFailure('<neden>', …)` ekle (yalnız neden, içerik yok).

### Testler
- Sunucu: madde 3.
- İstemci (`test/call_manager_*`): (a) zaman aşımı → durum `noAnswer`, kayıt
  `Cevapsız`; (b) gelen grup araması çalarken koordinatör `HANGUP` → aranan
  `ended`; (c) aktif olmayan aramaya geç katılım → anahtar beklemeden `false`;
  (d) `_finish` sunucu `HANGUP`'ını üye ACK'lerinden önce gönderiyor.
- Cihaz: A grup araması başlatsın, B **cevaplamasın** → 60 sn'de iki tarafta
  da ekran kapanıyor, A `Cevapsız`, B `Cevapsız`, A'da `Katıl` bandı yok.
  B 61. saniyede cevaplayamamalı.

### Kabul kriteri
Zaman aşımı, ayrılma ve kopma durumlarında kalan üyelerin ekranı ≤2 sn'de
kapanıyor. Kayıtlar gerçeği yansıtıyor. `Katıl` yalnız gerçekten aktif bir
aramada çıkıyor.

---

## Bulgu 12 — Tek gösterimlik dosyada "Uygulamayla aç" (ORTA, güvenlik)

### Gözlem
Tek gösterimlik `qa_dosya_1.txt` alıcıda açılınca görüntüleyicide başlık
`Tek gösterimlik · ekran korumalı`, gövdede **`Uygulamayla aç`** düğmesi var.
Basılırsa içerik dış uygulamaya (intent/FileProvider) gider ve orada kalıcı
kopyalanabilir. (Testte kopya bırakmamak için basılmadı.)

### Kök neden (doğrulandı)
`lib/src/features/chat/media_viewer_screen.dart` — üst çubuktaki `Paylaş`
eylemi `!message.isViewOnce` ile gizleniyor (~:135), ama görsel olmayan dosya
gövdesindeki `FilledButton.icon(… open_with_app …)` (~:264–270, `onOpen:
() => _open(context, path, mime)` ~:166) tek gösterim kontrolü olmadan
çiziliyor.

### Yapılacaklar
1. `message.isViewOnce` ise `open_with_app` düğmesini **çizme** ve `_open`'ı
   da koşulla koru (savunma: `isViewOnce` ise erken dön).
2. Tek gösterimlik dosya için uygulama içi önizleme: `text/*` → metni
   ekranda göster (boyut sınırı ile); görsel → mevcut; diğer türler →
   "Bu dosya türü tek gösterimlik açılamaz" + kapat.
3. Daha güvenli seçenek: gönderim tarafında tek gösterimi yalnız
   `image/*`, `video/*` ve `text/plain` için izin ver; diğer türlerde "1"
   düğmesini devre dışı bırak (`media_preview_screen.dart`).
4. Tek gösterim içeriği için `FileProvider` URI'si hiç üretilmediğini test et.

### Testler
- Widget: `MediaViewerScreen(message: isViewOnce=true, mime=application/pdf)`
  → `find.text(l10n.open_with_app)` **bulunmamalı**.
- Cihaz: tek gösterimlik `.txt` gönder → alıcıda içerik uygulama içinde
  görünüyor, dışa aktarma yok.

---

## Bulgu 5 — Görüntülü arama ahizeden başlıyor; hoparlör düğmesi yanlış durumda (ORTA)

### Gözlem
- Birebir görüntülü arama B→A. Arama sırasında iki telefonda
  `dumpsys audio` → `Active communication device: type:earpiece`;
  `dumpsys telecom` → `TYPE_EARPIECE`.
- **Arayan (B):** Hoparlör düğmesi `checked=true` (beyaz) ama ses ahizede.
  1. dokunuş → düğme kapalı, rota yine ahize. 2. dokunuş → `speaker`.
- **Cevaplayan (A):** Düğme kapalı, ahize; tek dokunuşla hoparlör (doğru).
- Grup görüntülü aramada da iki taraf `type:earpiece`.

### Kök neden (doğrulandı)
- `lib/src/media/call_manager.dart:549` (giden birebir) ve `:1112` (gelen
  birebir): oturum `isSpeakerOn: callType == CallType.video` ile **yalnız UI
  durumu** olarak açılıyor. Grup: `:624`, `:1389` `isSpeakerOn: true`.
  Arama başında Telecom'a hoparlör isteği **gönderilmiyor**.
- Gerçek rota Telecom (self-managed `ConnectionService`) tarafından belirleniyor:
  `android/app/src/main/kotlin/com/securechat/app/SecureChatConnectionService.kt`
  ~:146–170 `onCallAudioStateChanged` / `onCallEndpointChanged` →
  `speakerOn`/`speakerOff` olaylarını Dart'a yayıyor
  (`call_manager.dart:2123–2130` UI'ı günceller). Arayan tarafta bu olay
  oturum oluşmadan ya da `ACTIVE`'den önce geldiği için kaybolmuş olabilir;
  UI `true` kalıyor.
- Grup motoru `lib/src/media/group_media_engine.dart:233`
  `Helper.setSpeakerphoneOn(true)` çağırıyor; Telecom yönetimindeki çağrıda
  `AudioManager` isteği Telecom rotasıyla eziliyor.
- `toggleSpeaker` (`call_manager.dart:913–927`) `!session.isSpeakerOn` ile
  ters çeviriyor. UI yanlış başladığı için ilk dokunuş "kapat" isteği oluyor.

### Yapılacaklar
1. Görüntülü arama (birebir + grup) Telecom'da **aktif olunca** (native
   bağlantı `ACTIVE`/`onCallEndpointChanged` sonrası) bir kez
   `_nativeCalls.setSpeaker(callId, true)` iste. Native entegrasyon yoksa
   `_media.setSpeakerOn(true)` / `_groupMedia.setSpeakerOn(true)`.
2. `isSpeakerOn` başlangıç değerini `false` yap. UI durumunu **yalnız**
   native `speakerOn/speakerOff` olaylarından (ya da native yoksa başarılı
   `setSpeakerOn` dönüşünden) türet. Oturum oluşmadan gelen olayları
   saklayıp oturum kurulunca uygula.
3. `toggleSpeaker`: hedefi UI bayrağından değil son bilinen gerçek rotadan
   hesapla. Native istek başarısızsa UI'ı değiştirme.
4. `group_media_engine.dart:233`'teki koşulsuz `setSpeakerphoneOn(true)`'yu
   kaldır ya da native yoksa çalışacak şekilde koşula bağla.
5. Sesli aramada varsayılan ahize kalsın; grup sesli aramada (`:624`, `:1389`
   `true`) ürün kararı: WhatsApp grup sesli aramada da ahizeyle başlar.

### Testler
- Birim: sahte `NativeCallIntegration` ile görüntülü arama aktif olunca
  `setSpeaker(callId, true)` bir kez çağrılıyor; `speakerOff` olayı UI'ı
  `false` yapıyor; oturumdan önce gelen olay kaybolmuyor.
- Cihaz: B→A görüntülü arama; iki tarafta `dumpsys audio` → `type:speaker`,
  düğmeler beyaz; tek dokunuşla `earpiece`.

---

## Bulgu 6 — Rehber eşitlemesi elle eklenen kişiyi siliyor; grup seçicide görünmüyor (ORTA)

### Gözlem
- A, B'yle **tuş takımından** numarayla sohbet açtı (14:41). Rehber sekmesinde
  `9 / +905321000413` satırı göründü.
- ~5 dk sonra Yeni Grup üye seçicisinde B yoktu; `5321000413` araması
  `Eşleşen sohbet yok` dedi. Test için B'yi telefon rehberine eklemek gerekti.

### Kök neden (doğrulandı)
- Tuş takımı akışı: `lib/src/features/contacts/contacts_screen.dart` ~:338 →
  `ContactService.resolvePhone` (`lib/src/contacts/contact_service.dart:228–245`)
  `isRegistered: true` bir `ContactEntity` ekliyor.
- Arka plan rehber eşitlemesi `importAndDiscover`
  (`contact_service.dart` ~:219–223):
  ```dart
  final deviceHashes = byHash.keys.toSet();
  for (final existing in await _database.contacts.getAllOnce()) {
    if (!deviceHashes.contains(existing.phoneHash)) {
      await _database.contacts.delete(existing.id);
    }
  }
  ```
  Telefon rehberinde olmayan **her** kişiyi siliyor, elle eklenenler dahil.
- Grup seçici `lib/src/features/contacts/create_group_flow.dart:50`
  `service.watchRegistered()` (= `contacts.getRegistered()`); birebir
  sohbetleri kaynak almıyor.
- Seçicinin boş sonuç metni `recipient_picker_screen.dart` ~:152
  `l10n.bulk_no_results` = "Eşleşen **sohbet** yok" — kişi seçicide yanlış
  metin.

### Yapılacaklar
1. `ContactEntity`'ye kaynak alanı ekle (ör. `source: device | manual`, ya da
   `addedManually: bool`). Şema/serileştirme: `storage_entities.dart` +
   `secure_chat_database.dart` (eski kayıtlarda varsayılan `device`).
2. `resolvePhone` → `source: manual`.
3. `importAndDiscover` silme döngüsü yalnız `source == device` olanları
   silsin. Ayrıca bir telefon rehberi kişisi silindiğinde **o kişiyle açık
   birebir sohbet varsa** kişiyi silmek yerine `manual`'a çevir.
4. Grup seçiciye birebir sohbetlerin karşı taraflarını da ekle (kişi
   tablosunda yoksa sohbetten `ContactEntity` türet: `id=peerId`,
   `displayName=peerName`, `phoneNumber=peerPhone`), `id` ile tekilleştir.
5. Seçicide boş metin için yeni anahtar: `recipient_no_results`
   ("Eşleşen kişi yok").
6. Rehber sekmesindeki `IconButton(Icons.sync, tooltip: action_retry)`
   (`contacts_screen.dart` ~:62–66): erişilebilirlik etiketi "Tekrar Dene"
   okunuyor; `contacts_sync` ("Rehberi eşitle") anahtarı kullan.

### Testler
- Birim: `resolvePhone` ile eklenen kişi, `importAndDiscover` sonrası
  **kalıyor**; rehberden silinen cihaz kişisi siliniyor.
- Widget: sohbeti olan ama rehberde olmayan kişi grup seçicide listeleniyor.
- Cihaz: rehberde olmayan numarayla sohbet → uygulamayı kapat/aç (eşitleme)
  → Yeni Grup'ta kişi görünüyor.

---

## Bulgu 3 — Rehberde olmayan gönderenin sohbet başlığı ham UUID (ORTA)

### Gözlem
A (B'nin rehberinde değil) B'ye yazdı. B'de sohbet listesinde, sohbet
başlığında **ve gelen arama ekranında** `3b3663e9-3046-4ba9-acd6-dfdaf3fa510c`.
A'nın numarası B'nin rehberine eklenip eşitlenince başlık `QaAlfa` oldu.

### Kök neden (doğrulandı)
- `lib/src/incoming/incoming_message_handler.dart` ~:627–643: yeni sohbet
  oluşturulurken `peerName: identity?.displayName ?? signal.senderId`.
- `lib/src/services/app_container.dart` ~:598–603 `resolvePeerName`:
  `contact?.displayName ?? peerId` (gelen arama ekranı bu yolu kullanıyor).
- Numara paylaşımı (`SharedPhoneSignal`,
  `lib/src/contacts/phone_number_sharing_service.dart` `shareWith`) var ama
  **varsayılan kapalı**: `lib/src/services/session_store.dart:20`
  `sharePhoneNumber = false`. Bu gizlilik kararı doğru; B'nin A'nın
  numarasını bilmemesi beklenen durum. Hata, iç kimliğin ad olarak
  gösterilmesi.

### Yapılacaklar
1. UI'da asla UUID gösterme. `peerName` boş ya da `peerId`'ye eşitse
   gösterim katmanında (sohbet listesi, sohbet başlığı, arama ekranı,
   bildirim) `l10n.unknown_contact` ("Bilinmeyen kişi") kullan; numara
   biliniyorsa (`peerPhone`) numarayı göster. Tek bir yardımcı:
   `displayNameFor(conversation)`.
2. Profil adı paylaşımı (WhatsApp "~Ad" davranışı): şifreli özel sohbet
   kontrolü olarak `SharedProfileNameSignal` (ya da mevcut
   `SharedPhoneSignal` desenini genişlet). Gönderen ilk doğrudan mesajda
   kendi görünen adını (`session.displayName`, uzunluk sınırı, kontrol
   karakterleri temizlenmiş) gönderir. Alıcı kişi kaydı yoksa
   `peerName = "~$ad"` olarak saklar; rehber eşleşmesi gelince rehber adı
   önceliklidir. Profil adı paylaşımı da ayarlardan kapatılabilmeli
   (varsayılan açık olabilir: numara değil, kullanıcının seçtiği ad).
3. Yeni sohbet ilk açıldığında WhatsApp'taki gibi bir şerit: "Bu kişi
   rehberinizde değil — Engelle / Rehbere ekle".
4. `incoming_message_handler.dart`'ta fallback'i `signal.senderId` yerine boş
   dize yap (madde 1 gösterimi halleder) — mevcut UUID'li kayıtlar için de
   gösterim katmanı korur.

### Testler
- Birim: kişi kaydı olmadan gelen ilk mesaj → `displayNameFor` "Bilinmeyen
  kişi" (ya da `~QaAlfa`), UUID değil.
- Cihaz: rehberde olmayan numaradan mesaj + arama → hiçbir ekranda UUID yok.

---

## Bulgu 13 — Tek gösterim: gönderende sahte "Açıldı", metinde "medya" (DÜŞÜK)

### Gözlem
- Tek gösterimlik fotoğraf/dosya gönderilir gönderilmez A'da
  `1 · Açıldı · Bu medya artık açılamaz` — B henüz açmamışken.
- Tek gösterimlik **metin** iki tarafta `Bu medya artık açılamaz`.

### Kök neden (doğrulandı)
- `lib/src/features/chat/chat_message_details.part.dart:17–18`:
  `consumed = message.isViewOnce && (message.isOutgoing || message.isViewed)`
  → gönderen için her zaman "tüketildi"; `:34–41` `opened` +
  `media_no_longer_available`.
- `lib/src/features/chat/chat_message_bubble.part.dart` ~:366–370 metin için
  de `media_no_longer_available`.
- Alıcının "açtım" bilgisini gönderene ileten bir sinyal **yok**
  (`isViewed` yalnız yerelde `secure_chat_database.dart` ~:1061/:1081).

### Yapılacaklar
1. Gönderen tarafında durum: `Tek gösterimlik fotoğraf/dosya/mesaj` +
   mevcut teslim/okundu göstergesi. `Açıldı` yalnız açılma bilgisi gelince.
2. (İsteğe bağlı) Şifreli özel kontrol `ViewOnceOpenedSignal{messageId}`:
   alıcı açınca gönderir; gönderen `isViewed=true` yapar ve `Açıldı`
   gösterir. Grup için her üyeden ayrı ya da yalnız "en az biri açtı".
3. Metin için yeni anahtarlar: `view_once_message` ("Tek gösterimlik mesaj"),
   `message_no_longer_available` ("Bu mesaj artık açılamaz").

### Testler
- Widget: giden tek gösterimlik görsel balonunda `opened` metni **yok**;
  `ViewOnceOpenedSignal` sonrası var.

---

## Bulgu 9 — Bitmiş grup araması için "Katıl" bandı ~20 sn kalıyor (DÜŞÜK)

### Gözlem
2 kişilik grup aramasında A `Bitir` dedi, B'nin araması da bitti. A'nın grup
sohbetinde `Devam eden sesli arama — Katıl` bandı göründü, 20 sn içinde
kayboldu. Grup görüntülü aramada da aynısı.

### Kök neden (doğrulandı + çıkarım)
- Bant `lib/src/features/calls/group_call_banner.dart` ~:34–60: oturum
  değişince hemen ve her 5 sn'de `widget.calls.activeGroupCall(groupId)`
  ile sunucuya soruyor.
- Oturum bittiği anda sunucu henüz `HANGUP` almamış oluyor: `_finish`
  sunucu `HANGUP`'ını üyelere `reliable` gönderimlerin ACK'lerinden **sonra**
  yolluyor (Bulgu 8b). Bu sırada sunucu çağrıyı aktif bildiriyor.
- Ayrıca Bulgu 8a varsa sunucu tarafı yayın da eksik kalabilir.

### Yapılacaklar
1. Bulgu 8 madde 6 (sunucu `HANGUP`'ı önce gönder).
2. Banner: kullanıcının **kendi az önce ayrıldığı** `callId` için bandı
   gizle (CallManager'da `recentlyLeftCallIds` ya da terminal oturumun
   `callId`'si; sunucu yeni `callId` dönerse göster).
3. `activeGroupCall` yanıtında katılımcı sayısı 0 ise bandı gösterme.

### Testler
- Widget: terminal oturumun `callId`'si ile aynı aktif çağrı → bant yok.

---

## Bulgu 2 — "son görülme 1 Oca 1970" (DÜŞÜK)

### Gözlem
Hem eski sohbette hem çevrimiçi yeni karşı tarafla açılan sohbette (B
uygulamada açıkken) başlıkta `son görülme 1 Oca 1970`.

### Kök neden (doğrulandı)
- `lib/src/core/signal_message.dart:74–75`:
  `DateTime _dt(Object? value) => DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);`
  Eksik/0 `lastSeen` epoch 0 oluyor.
- `PresenceUpdateSignal.fromJson` ~:684 `lastSeen: _dt(json['lastSeen'])`.
- `lib/src/incoming/incoming_message_handler.dart` ~:916–921
  `_presenceSignal` bu değeri `PresenceInfo.lastSeen` olarak saklıyor;
  `lib/src/features/chat/chat_screen.dart` ~:683–700 `_peerSubtitle`
  `lastSeen != null` ise biçimlendiriyor.
- Ek soru: B çevrimiçiyken A neden `isOnline=false` aldı? Sunucunun
  presence yanıtı ve B'nin `shareOnline` ayarı kontrol edilmeli (B, A'yı
  `çevrimiçi` görüyordu; ters yön değil).

### Yapılacaklar
1. `PresenceUpdateSignal` için `lastSeen`'i nullable ayrıştır
   (`_dtOrNull`: yok/≤0 → `null`). `_presenceSignal`'da da `<= 0` → `null`.
2. `_peerSubtitle`: `lastSeen` 2000 öncesiyse yok say (savunma).
3. Presence asimetrisini araştır: A→B `presence_subscribe` ve sunucunun
   `presence_update` yanıtı (logcat'e içerik değil yalnız
   `isOnline/hasLastSeen` yazan SC-DIAG eklenebilir).

### Testler
- Birim: `PresenceUpdateSignal.fromJson({... lastSeen yok ...}).lastSeen == null`.

---

## Bulgu 10 — Gönderen kendi mesajından sonra en alta kaymıyor (DÜŞÜK)

### Gözlem
Sohbet en altta değilken dosya/anket gönderince ekran yerinde kalıyor,
`En yeni mesaja git` rozeti `2` (kendi mesajları) gösteriyor.

### Kök neden (doğrulandı)
`lib/src/features/chat/chat_screen.dart` ~:722–745: `added = nextCount -
previousCount` gönderen ayrımı yapmıyor; `shouldFollow` yalnız `_nearBottom`.
Metin gönderiminde `_onComposerTap` kaydırıyor (~:1001), ama ek/anket
gönderiminde böyle bir kaydırma yok.

### Yapılacaklar
1. Yeni eklenen mesajlardan `isOutgoing` olan varsa `shouldFollow = true`.
2. `added` yalnız gelen (`!isOutgoing`) mesajları saysın.

### Testler
- Widget: listede yukarıdayken giden mesaj eklenince `maxScrollExtent`'e
  gidiliyor, rozet 0.

---

## Bulgu 14 — Tek gösterimlik dosya "fotoğraf" diye etiketleniyor (DÜŞÜK)

### Kök neden (doğrulandı)
`chat_message_details.part.dart` ~:36 — tek gösterim balonu türden bağımsız
`l10n.view_once_photo`.

### Yapılacaklar
MIME'a göre: `image/*` → `view_once_photo`, `video/*` → `view_once_video`,
diğer → `view_once_file` ("Tek gösterimlik dosya"). Metin için Bulgu 13
madde 3.

---

## Bulgu 15 — Tek gösterim anahtarı ankette yok sayılıyor (DÜŞÜK)

### Gözlem
Giriş çubuğunda `Tek gösterim` açık → Ek ekle → Anket → Oluştur. Anket normal
gidiyor; anahtar `checked=true` kalıyor, sonraki metin beklenmedik şekilde
tek gösterimlik gidebilir.

### Kök neden (doğrulandı)
`lib/src/features/chat/chat_chrome.part.dart` ~:686–687 anahtar yalnız metin
gönderiminde okunup sıfırlanıyor; anket/ek akışları anahtarı ne kullanıyor ne
sıfırlıyor.

### Yapılacaklar
- Anahtar açıkken Ek menüsünde Anket'i devre dışı bırak (ipucu: "Anketler
  tek gösterimlik gönderilemez"), **ya da** anket gönderiminde anahtarı
  sıfırla ve SnackBar ile bildir. Galeri/Dosya akışında, anahtar açıksa
  `MediaPreviewScreen`'e `initialViewOnce: true` geçir (tutarlılık).

---

## Bulgu 16 — Tek gösterim ekranı korumayı kendisi zorlamıyor; "1" düğmesinin etiketi yok (DÜŞÜK)

### Gözlem
- Debug derlemede tek gösterim görüntüleyicisi `ekran korumalı` diyor ama
  `adb exec-out screencap` içeriği yakaladı.
- Medya önizlemesindeki tek gösterim düğmesi erişilebilirlik ağacında yalnız
  `1`; açık/kapalı durumu yok.

### Kök neden (doğrulandı)
- `android/app/src/debug/AndroidManifest.xml:14`
  `com.securechat.DEBUG_ALLOW_SCREEN_CAPTURE` → `MainActivity.kt` ~:534–550
  `applyScreenProtectionPolicy` FLAG_SECURE'ı debug'da kaldırıyor (bilinçli
  QA ayarı; release etkilenmez).
- `lib/src/platform/native_bridge.dart:36` `enableScreenProtection()` var
  ama hiçbir ekran çağırmıyor. Tek gösterim görüntüleyicileri
  (`media_viewer_screen.dart`, `chat_screen.dart` ~:1365) korumayı
  zorlamıyor.
- `lib/src/features/chat/media_preview_screen.dart` ~:113–117 düğme yalnız
  `Tooltip` + `InkWell`; giriş çubuğundaki eşdeğerinde
  (`chat_chrome.part.dart` ~:609–618) `Semantics(label, toggled)` var.

### Yapılacaklar
1. Native'e `enableScreenProtectionForced` / `releaseForcedScreenProtection`
   ekle (debug istisnasını yok sayar). Tek gösterim görüntüleyicileri
   `initState`'te zorla, `dispose`'ta debug politikasına geri dön.
2. `media_preview_screen.dart` düğmesini
   `Semantics(label: l10n.view_once, button: true, toggled: _viewOnce, excludeSemantics: true)`
   ile sar.

---

## Bulgu 7 — Rehber araması tam numarayı bulmuyor (DÜŞÜK)

### Gözlem
Rehber sekmesinde `532` → QaBeta bulunuyor; `5321000413` → `Sonuç bulunamadı`
(kayıtlı numara `+90 532 100 04 13`, boşluklu).

### Kök neden (doğrulandı)
- `lib/src/features/contacts/contacts_screen.dart` ~:74–83
  `contact.phoneNumber.contains(_query)` — ham dize karşılaştırması.
- `lib/src/features/contacts/recipient_picker_screen.dart` ~:145–150 aynı
  desen (`item.detail.toLowerCase().contains(_query)`).

### Yapılacaklar
`normalizePhoneDigits` (`lib/src/auth/phone_privacy.dart:5`) ile hem sorgu
hem numara rakama indirgensin; sorgu en az 3 rakam içeriyorsa rakam
karşılaştırması, değilse ad karşılaştırması. İki ekranda ortak yardımcı.

---

## Bulgu 4 — İsimsiz kişilerin avatarı anlamsız (DÜŞÜK)

### Kök neden (doğrulandı)
`lib/src/widgets/avatar.dart:27–48` `initialsOf` bilinçli olarak rakam da
kabul ediyor ("+90 532…" → `9`); UUID → `33`.

### Yapılacaklar
Ad hiç harf içermiyorsa (yalnız rakam/işaret) ya da UUID desenindeyse
baş harf yerine `Icons.person` göster. Bulgu 3 düzelince UUID durumu zaten
kalkar.

---

## Bulgu 11 — Alınan dosyalar yerelde şifresiz (ÜRÜN KARARI)

### Gözlem
`adb shell run-as com.securechat.app.debug` ile
`files/media/received_files/1791806666623_qa_ikili_300k.bin` okunabildi
(orijinalle aynı sha256). Tek gösterimlik içerik ise diskte kalmıyor (doğru).

### Durum
- Yazma: `lib/src/media/file_transfer_manager.dart` ~:740
  `'${_filesDirectory.path}/received_files'`.
- Hafifletenler: uygulama özel dizini; `AndroidManifest.xml:20–22`
  `allowBackup="false"`, `fullBackupContent="false"`.
- Risk: root, adli imaj, kötü niyetli debug erişimi. Veritabanı SQLCipher ile
  şifreli olduğu halde medya düz.

### Seçenekler (karar sonrası)
1. Dosyaları DB anahtarından türetilmiş anahtarla (AES-GCM, dosya başına
   nonce) şifreli yaz; görüntülerken belleğe ya da geçici dosyaya çöz,
   kapanınca sil. Paylaş/Uygulamayla aç için geçici, kısa ömürlü kopya.
2. Mevcut haliyle bırak, belgeye "medya at-rest şifrelenmez" diye yaz.

---

## Ek A — Cihaz test yardımcıları

`ui.sh` (ekrandaki metinleri ve tıklanabilir alanların merkezlerini yazar):

```bash
# Kullanim: ui.sh <device>
D=$1
adb -s $D shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
adb -s $D shell cat /sdcard/ui.xml > /tmp/ui_$D.xml
python3 -I - "$D" <<'PY'
import re, sys
d=sys.argv[1]
x=open(f'/tmp/ui_{d}.xml',encoding='utf-8',errors='replace').read()
for m in re.finditer(r'<node[^>]*?>', x):
    t=m.group(0)
    text=re.search(r'text="([^"]*)"',t); desc=re.search(r'content-desc="([^"]*)"',t)
    cls=re.search(r'class="([^"]*)"',t); b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',t)
    clickable='clickable="true"' in t
    label=(text.group(1) if text else '') or (desc.group(1) if desc else '')
    if not label and not clickable: continue
    x1,y1,x2,y2=map(int,b.groups()) if b else (0,0,0,0)
    print(f'{"TIK" if clickable else "   "} ({(x1+x2)//2},{(y1+y2)//2}) {(cls.group(1).split(".")[-1] if cls else "?"):14} {label[:50]}')
PY
```

Faydalı ölçümler:

```bash
adb -s <d> shell dumpsys audio | grep -m1 "Active communication device"   # ses rotası
adb -s <d> shell dumpsys telecom | grep "Pending route"                    # Telecom rotası
adb -s <d> logcat -d | grep -E "setDisconnected|-> ACTIVE|onConnectionChange"
adb -s <d> shell "run-as com.securechat.app.debug ls -la files/media"      # yerel dosyalar
```

Koordinatlar (1080x2340, klavye kapalı): alt sekmeler y=2098
(Sohbet 135, Arama 405, Rehber 675, Ayarlar 945); sohbet ⋮ (1012,175);
Ek ekle (90,2112) → Kamera 168 / Galeri 416 / Dosya 663 / Anket 911 @ y=1902;
Tek gösterim anahtarı (838,2112); medya önizleme "1" (832,2120), Gönder
(973,2109). Klavye açıkken diyaloglar yukarı kayar; her adımda dökümle.

## Ek B — Bu testte doğrulanıp çalışan akışlar

Birebir metin (iki yön, okundu), birebir sesli ve görüntülü arama, grup kurma,
grup mesajı, grup sesli araması (zamanında cevapla), grup görüntülü araması,
fotoğraf/dosya (birebir + grup, sha256 eşleşmesi), anket (oy değiştirme
dahil, birebir + grup), tek gösterimlik metin/fotoğraf/dosya (birebir) ve
fotoğraf (grup).

## Ek C — Test edilmeyenler (yeni oturumda kapsanabilir)

- Uygulama arka planda / ekran kilitliyken bildirim ve gelen arama (FCM +
  ConnectionService).
- Sesin gerçekten duyulması (insan kulağı).
- 3+ kişilik grup araması, SFU (Janus) geçişi — canlıda kapalı, iki cihaz var.
- Sesli mesaj, kamera çekimi, video gönderimi, süreli mesajlar.
- Sunucu logu (SSH master test sırasında düştü). Bulgu 8a'nın canlı log
  doğrulaması bu yüzden yapılamadı.
