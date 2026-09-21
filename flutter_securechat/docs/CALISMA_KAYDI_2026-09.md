# Çalışma Kaydı — Eylül 2026

Dal: `qa/design-and-fixes-2026-09` · 44 commit · 412 test geçiyor

Bu belge dalda yapılanların kaydıdır. Aradan zaman geçtiğinde ya da yeni bir
oturumda devam ederken buradan okumaya başlayın. Her başlıkta **ne bozuktu**,
**neden öyleydi** ve **nasıl doğrulandı** yazılı; kod okunmadan kararların
gerekçesi anlaşılsın diye.

---

## 1 · iOS'ta mesaj veritabanı şifresiz yazılıyordu

**En kritik bulgu.** Düz SQLite, tanımadığı pragmaları hata vermeden yok
sayar — `PRAGMA key` dahil. Kütüphane çözümlemesinde iOS dalı olmadığı için
uygulama sistemin düz SQLite'ına düşüyordu ve açılış **başarılı görünüyordu**.

Doğrulanan davranış, düz `sqlite3` ile:

```
$ head -c 16 db
00000000: 5351 4c69 7465 2066 6f72 6d61 7420 3300   SQLite format 3.
$ strings db | grep -c GIZLI_MESAJ_ICERIGI
1
```

Üç katmanda kapatıldı:

| katman | ne yapar |
|---|---|
| Fail-closed denetim | Anahtar verilmeden önce `PRAGMA cipher_version` kontrol edilir. Sağlanamıyorsa depo **açılmaz** — düz metin yazmaktansa çalışmamak doğru davranış. |
| Gömülü SQLCipher 4.5.6 | `ios/SQLCipher` altında, Swift paketi olarak Runner'a bağlı. Sürüm Android ile (`net.zetetic:sqlcipher-android:4.5.6`) bilerek aynı. |
| Regresyon kapıları | `audit_ios_readiness.dart` zincirin her halkasını denetler. Her denetim kasten bozulup başarısız olduğu doğrulandı. |

### Yol boyunca çıkan üç ayrı hata

**`NDEBUG` eksikti.** Derleme `No member named 'zEnd' in 'struct EdupBuf'`
ile duruyordu. Sebep: `assert()` gövdeleri derleniyordu ve o gövdeler yalnız
`SQLITE_DEBUG` tanımlıyken var olan alanlara başvuruyor. Amalgamation
`NDEBUG`'ı kendi tanımlıyor (satır 14162) ama `<assert.h>` daha önce dahil
edilmişse geç kalıyor. Komut satırından verilince sıra sorunu kalkıyor.

**Semboller sistem `libsqlite3` ile karışıyordu.** AOT derlemelerinde açılışta
çökme:

```
EXC_BAD_ACCESS (code=1, address=0x0)
frame #1  libsqlite3.dylib`sqlite3_extended_result_codes + 108
frame #8  EncryptedRecordStore.open  encrypted_record_store.dart:77
```

Çağrı Apple'ın sistem SQLite'ındaydı. Sebep: SQLCipher statik bağlı ve Dart
ona `dlsym` ile ulaşıyor; `dlsym` yalnız **dışa aktarılmış** sembolleri görür
ve statik kütüphaneden gelenler varsayılan olarak dinamik sembol tablosuna
girmez. Bir kısmı girmiş bir kısmı girmemişti (`nm -gU | grep -c sqlite3_`
**73** dönüyordu; SQLCipher'ın genel API'si ~250 fonksiyon). `sqlite3_open_v2`
bizim kopyadan, `sqlite3_extended_result_codes` Apple'ınkinden çözülüyordu.

`-Wl,-export_dynamic` ile çözüldü. Yalnız AOT'de görülmesinin sebebi: debug
JIT farklı sembol çözümlemesi yapıyor ve karışım oluşmuyor.

**Dosyalar Xcode projesine kayıtlı değildi.** `UNNotificationSound` ve bundle
kaynakları uygulama paketinin **kökünde** aranır; klasör referansı eklenirse
dosyalar alt dizinde kalır ve bulunmaz.

---

## 2 · Depolama ölçeğe dayanmıyordu

Veritabanı tek bir JSON dosyasıydı: tamamı bellekte tutuluyor ve **her
değişiklikte tamamı yeniden şifrelenip diske yazılıyordu**.

SQLCipher üzerinde artımlı depoya geçildi (`EncryptedRecordStore`). Yalnız
değişen kayıtlar yazılır. **Budama yapılmadı — hiçbir mesaj silinmiyor.**

| geçmiş | önce | sonra |
|---|---|---|
| 50 | 7 000 µs | 270 µs |
| 500 | 32 000 µs | 215 µs |
| 1 000 | 57 000 µs | 192 µs |
| 2 000 | 120 000 µs | 181 µs |
| 5 000 | (10 dk'da bitmedi) | 157 µs |

Gerçek gelen mesaj akışı: **338 ms → 1 ms**. Maliyet artık geçmiş boyutundan
bağımsız.

Yeni native bağımlılık **eklenmedi**: `libsqlcipher.so` zaten APK'daydı.
`sqlite3` paketinin 3.x sürümü kendi ikililerini derleme kancasıyla getirir ve
bu, projenin bağımlılık doğrulama sistemini atlardı; 2.9.4 kütüphaneyi
dışarıdan alır.

Geçiş geri dönüşlü: eski `.securejson` dosyası **silinmez**.

---

## 3 · Mac'e taşıma

iOS geliştirme kullanıcının kendi Mac'ine taşındı (Apple Silicon, Xcode 27).
Codemagic bırakıldı.

Yol boyunca üç tekrar eden tuzak belgelendi ve denetime alındı:

- **Homebrew kurulumu `xcode-select`'i Command Line Tools'a çeviriyor.**
  iPhoneOS SDK'sı kayboluyor, `xcodebuild` çalışmıyor, `simctl` boş dönüyor —
  belirtiler sebebi hiç işaret etmiyor. `preflight_macos.sh` ilk sırada bunu
  denetliyor; bir kez doğru olması yetmiyor.
- **iOS platformu ile simülatör runtime ayrı indirmeler.** Runtime kurmak
  cihaz SDK'sını getirmiyor.
- **`flutter analyze` derleme çıktılarını tarıyordu.** iOS derlemesi SPM
  checkout'larını `build/` altına koyuyor ve orada Dart kaynağı da var. Kapı
  temiz ağaçta geçiyor, derlemeden **sonraki** her koşumda düşüyordu.

### Araçlar

| betik | ne yapar |
|---|---|
| `tool/preflight_macos.sh` | Hiçbir şey kurmaz; eksikleri listeler ve komutunu yazar |
| `tool/run_ios_device.sh` | Cihaz kurulumunu tek komuta indirir, beş koşulu sırayla doğrular |
| `tool/ios_personal_signing.sh` | Ücretsiz Apple ID ile imzalama (idempotent, `--restore` ile geri alınır) |
| `tool/build_sqlcipher_macos.sh` | Homebrew olmadan SQLCipher üretir |
| `tool/vendor_sqlcipher.sh` | Gömülü kaynağı pinlenmiş sürümden yeniden üretir |

`run_ios_device.sh` beş şeyi birden doğrular, çünkü herhangi biri yanlışsa
uygulama **tek bir mesaj** veriyor: "bağlantı kurulamadı".

---

## 4 · QA mock sunucusu

Gerçek sunucu erişilemez olduğunda cihaz testi tıkanıyordu. Mock sunucu zaten
vardı ve gerçek Signal protokolü konuşuyor; üç hatası düzeltildi:

- **TLS modunda yalnız loopback dinliyordu.** Düz HTTP dalı `anyIPv4`
  kullanıyordu, ikisi ayrışmıştı. Uygulama `https` zorunlu kıldığı için cihaz
  testi hep TLS dalına düşüyor — telefon hiç bağlanamıyordu.
- **Sertifika her çalıştırmada yenileniyordu**, yani pin eskiyordu. Pin
  derleme anında gömüldüğü için bu, yeniden kurmadan fark edilemiyordu.
- **Özel rehber modülü kapalıydı.** Kayıttan sonra `/api/v1/directory/config`
  501 dönüyordu; uygulama doğru davranıp güvensiz yedeğe düşmüyor ama ekranda
  **"kod hatalı veya süresi dolmuş"** yazıyordu. Belirti sebebi hiç işaret
  etmiyordu.

Doğrulama: `probe.dart` 17 sınamanın 15'ini geçiyor — gerçek X3DH oturumu,
PREKEY zarfı, sanal peer'in zarfı **çözmesi**, teslim/okundu bildirimleri,
çevrimdışı kuyruk ve yetki reddi dahil. Düşen ikisi botun otomatik cevap
vermemesiyle ilgili; şifre çözme çalışıyor.

---

## 5 · Tasarım ve arayüz

**Tasarım dili.** Derinlik, tipografi ölçeği, opak yüzeyler ve boş durumlar.
Arka plan deseni hareketli olduğu için yazının doğrudan desenin üzerine
oturması okunabilirliği bozuyordu.

**Açılır yüzeyler temaya bağlandı.** Diyaloglar, alt sayfalar ve menüler
varsayılan Material görünümündeydi. Çözüm tema seviyesinde — tek dosya
değişti, hepsi düzeldi. İki karar kasıtlı: yüzeyler **opak** (yarı saydam bir
diyalog altındaki hareketli deseni gösterir) ve Material 3 renk tonlaması
kapalı (yüksekliğe göre tonlama seçilmiş paleti kaydırıyordu).

**Seçim listelerine ortak biçim.** Her seçici ayrı yazılmıştı. Seçili durum
artık **üç işaretle** anlatılıyor: zemin, çerçeve, ikon. Tek küçük radyo
dairesi hızlı bakışta kaçıyordu.

**Ayar anahtarları canlı değişmiyordu.** Sayfalar yerel kopya tutup önce
kaydediyor, sonra ekranı güncelliyordu. Daha kötüsü: kaydetme **başarısız
olsa bile** anahtar yeni konumda kalıyordu — ekran kaydedilmemiş bir değeri
kaydedilmiş gibi gösteriyordu. Artık ayar akışı dinleniyor.

**"Mesaj içeriğini göster" gizliliğe taşındı** — kilit ekranında ne görüneceği
bir gizlilik kararı, ses tercihiyle ilgisi yok.

**Toplu mesaj ekranı.** Adı grup kurduğu izlenimi veriyordu; her alıcıya ayrı
mesaj gittiğini ve alıcıların birbirini görmediğini anlatan kart eklendi. Boş
mesajla "Gönder"e basınca hiçbir şey olmuyordu. "Tümünü seç" arama açıkken
**görünmeyenleri de seçiyordu** — kullanıcının göremediği bir sohbete mesaj
gitmesi demek.

---

## 6 · Bildirim sesleri

Önce dört tur sıfırdan sentez denendi ve hiçbiri beğenilmedi. Yöntem yanlıştı:
sentezin ölçülebilir özellikleri referansla eşleştirilebiliyor (harmonik
saflık, tepe seviyesi, zarf süreleri hepsi tutturuldu) ama "hoşa gidiyor mu"
bunlarla ölçülmüyor.

Doğru iş bölümü: **sesi insan seçer, araç hazırlar.**
`tool/package_notification_sounds.py` herhangi bir biçimi alıp mono 44.1 kHz
WAV'a çevirir, baştaki sessizliği kırpar, tepeyi −8 dBFS'e eşitler.

Seviye eşitlemesi önemli: listedeki sesler birbirine göre eşit yüksek olmalı,
yoksa seçim yapılırken en yüksek olan "daha iyi" sanılıyor.

**Lisans:** Apple'ın sistem sesleri telifli ve internette dolaşan "iOS
notification sound" dosyalarının büyük kısmı bunların kopyası. Eklenen her
sesin kullanım hakkı doğrulanmalı.

### Kablolama

**Android — her ses için ayrı kanal.** Android 8'den beri bir kanalın sesi
oluşturulduktan **sonra** kodla değiştirilemiyor. Tek kanalla gidilseydi ses
değiştirmek için kanalı silip yeniden kurmak gerekirdi, üstelik **aynı
kimlikle değil**: Android silinen kanalın ayarlarını hatırlıyor ve eski sesle
geri getiriyor. (WhatsApp'ın yüzlerce kanal biriktirmesinin sebebi bu.)

**iOS** — ses dosya adıyla verilir ve dosya paketin kökünde olmalıdır.

**Önizleme** — duymadan seçim yapılamaz. Önizlemeyi bildirimi çalanın aksine
**uygulama** çalıyor, yani platform kaynağına erişemiyor; aynı dosyalar ayrıca
Flutter varlığı olarak paketlendi. İki kopya farklı mekanizmalar için.

**Sistem seçicisi** — paketlenmiş sesler sınırlı bir liste; cihazdaki her sesi
seçebilmenin tek yolu sistemin kendi seçicisi.

**Kişiye özel ses** — sohbet başına. Alan zaten vardı
(`customNotificationUri`, Kotlin uygulamasından taşınmış) ama kullanılmıyordu.
Seçici iki yerde de **aynı bileşen**; ayrı yazılsalardı listeler ayrışırdı.

---

## 7 · Sunucu doğrulaması

`server_hardened` için `./gradlew test` **hiç çalıştırılmamıştı**. 21 test-only
artefakt doğrulama listesine eklendi (her biri yerel Gradle cache kopyası
repo1.maven.org'daki resmi kopyayla birebir aynı olduğunda;
`<trusted-artifacts>` kullanılmadı).

Sonuç: **73 test sınıfı, 1330 test, 0 hata, 0 atlanan.**

---

## Açık işler

| iş | durum |
|---|---|
| Çeviri boşlukları | Almanca/Arapça ~112/505 anahtar. Eksikler İngilizceye düşüyor, o dilleri seçen karışık dil görüyor. |
| FCM gerçek teslimat | Hiç doğrulanmadı; Firebase service account JSON bekliyor. |
| Cihazda imzalı çalıştırma | Ücretsiz hesapla denendi; push çalışmıyor ve imza 7 günde düşüyor. |
| Faz 2 sayfalama | Okuma hâlâ tümüyle belleğe yükleniyor. Ölçüldü: 1k mesaj 31 ms, 50k mesaj 632 ms (masaüstü). Uzak borç. |
| Mock sunucu bot cevabı | Şifre çözme çalışıyor, otomatik yanıt tetiklenmiyor. |

---

## Doğrulama durumu

```
flutter analyze                 temiz
flutter test                    412 test
dart tool/audit_ios_readiness   PASS
./gradlew test (server)         1330 test
verify_ios_on_macos.sh          geçti (bu projede ilk kez)
```

Son satır önemli: iOS kapısı — analiz, testler, denetimler, release derlemesi
ve **simülatörde Runner XCTest** — bu projede ilk kez baştan sona koşuldu.

---

## 20 Eylül ek çalışmaları

### Sohbet erişimi ve mesaj yaşam döngüsü

- Yıldızlı/aranan/medya mesajına kişi bilgileri ekranından dokununca sohbet
  açılıyor, sanallaştırılmış liste hedef mesaja kayıyor ve mesaj kısa süreli
  vurgulanıyor.
- Sohbet kilidi artık yalnız bir veritabanı bayrağı değil. İlk kilitlemede en
  az sekiz karakterli parola iki kez isteniyor; PBKDF2-HMAC-SHA256 ile
  120.000 tur, sohbet başına rastgele 32 bayt salt ve sabit zamanlı karşılaştırma
  kullanılıyor. Parolanın kendisi saklanmıyor; doğrulayıcı mevcut şifreli yerel
  durum deposunda tutuluyor.
- Rehberden sohbet açma kilidi atlamıyor. Birebir ve grup bilgi ekranlarında
  kilitleme/kilit açma aynı kurala bağlı. Eski sürümden gelen ve henüz uygulama
  parolası olmayan kilitler cihaz kimlik doğrulamasına geri düşüyor.
- Süreli mesaj ayarı şifreli kontrol olarak çevrimdışı kuyruğa girebiliyor ve
  açma/kapama değişikliği iki tarafta yerelleştirilmiş sistem mesajı olarak
  görünüyor. Açık sohbet en yakın `expiresAt` anında silme yapıyor; arka plan
  bakımı yedek güvence olarak kalıyor. Silinen son mesaj sohbet önizlemesini
  artık bayat bırakmıyor.

### Bildirim sağlamlaştırması

- Özel ses kaynağı Android tarafından `invalid_sound` ile reddedilirse bildirim
  kaybolmuyor; ayrı bir sessiz-özel-ses-yedek kanalında varsayılan sesle yeniden
  gösteriliyor. Diğer platform hataları teşhis katmanına ulaşmaya devam ediyor.
- Paket denetiminde 10 mesaj sesi ve 3 çağrı tonu olmak üzere 13 adet
  `elcim_*.wav` Android `res/raw` kaynağı bekleniyor.
- Release resource shrinker, Dart tarafında yalnız adla kullanılan sesleri ölü
  kaynak sanıp atıyordu. `res/raw/keep.xml` tüm `elcim_*` kaynaklarını koruyor;
  üretilen APK'nın AAPT kaynak tablosunda 13 sesin tamamı doğrulandı.

### Android şifreli çağrı uyandırması

- Android kurulumu 32 baytlık cihaz anahtarı üretiyor. Anahtar Android Keystore
  içindeki dışarı aktarılamayan AES anahtarıyla sarılıp özel tercihlere yazılıyor;
  kayıt sırasında yalnız TLS üzerinden sunucuya gönderiliyor.
- Sunucu FCM tokenı ve cihaz ipucu anahtarını `fcm_tokens.token` alanındaki aynı
  kullanıcı-blind-index AAD'li v5 AES-GCM zarfında saklıyor. Yeni PostgreSQL
  kolonu veya migrasyon yok; düz anahtar veritabanına yazılmıyor.
- Push sağlayıcısı hâlâ yalnız `securechat_wake_v2` ve sabit 42 karakterlik `k`
  alanını görüyor. `k`, yeni 12 bayt nonce ile AES-256-GCM şifrelenmiş tek
  karakterlik `c`/`m` sınıfıdır. Aynı tür iki push aynı ciphertext'i üretmez.
  Gönderici, sohbet, çağrı kimliği, medya türü ve zaman payload'a eklenmez.
- Yalnız `sdp_offer` ve `group_call_invite` çağrı ipucu üretir. `call_control`
  mesaj sınıfındadır; sonlandırma sinyali yanlışlıkla yeni çağrı ekranı açamaz.
- FlutterFire receiver uygulama receiver'ıyla değiştirilip üst sınıfa iletim
  korunmuştur. Native receiver ipucunu Flutter/Activity başlamadan çözer ve
  anonim `ConnectionService` gelen çağrı yüzeyini açar. Dart arka plan kuyruğu
  paralel çekilir; gerçek teklif çözülünce geçici çağrı aynı native kayıtta
  gerçek çağrıya yükseltilir. Erken cevap/red eylemleri sekiz öğelik sınırlı
  tampon üzerinden gerçek çağrı kimliğine aktarılır.

**Dağıtım sırası:** önce yeni sunucu, sonra Android uygulaması. Değişiklik
geriye uyumludur: eski istemci anahtar göndermezse sunucu `k` eklemeden genel
uyandırma yollar; yeni istemcinin ek kayıt alanını eski sunucu da bilinmeyen alan
olarak yok sayar. Anlık native çağrı yüzeyi için iki tarafın da güncel olması
gerekir.

### Bu turun doğrulaması

```text
flutter analyze --no-pub                         temiz
flutter test --no-pub                            444/444 geçti
./gradlew :signaling-server:test --no-daemon     geçti
./gradlew :app:compileDebugKotlin --no-daemon    geçti
temiz flutter build apk --release                geçti, 123.2 MB
AAPT raw ses kaynağı denetimi                    13/13 geçti
bağlı SM-S731B kurulum ve açılış                 geçti
```

Cihaza kurulan test APK'sı, cihazdaki mevcut uygulamanın verisini korumak için
aynı yerel Android debug sertifikasıyla ayrıca imzalandı. Dağıtım APK/IPA'sı
üretim anahtarıyla CI veya air-gapped imzalama ortamında imzalanmalıdır.

### 21 Eylül kapalı uygulama bildirim teşhisi

- Bağlı Samsung cihazda bildirim izni, yüksek öncelikli mesaj kanalı, FCM
  receiver, batarya muafiyeti ve uygulama standby durumu doğrulandı.
- Uygulama arka plandayken FCM receiver ve Flutter background service çalıştı;
  `NotificationManager` mesaj bildirimini başarıyla yayımladı. Panelde gerçek
  `FCM-TEST` bildirimi görüldü. Telefon sessiz modda olduğu için ses çıkmadı.
- Sunucunun normal mesajlar için Android FCM `TTL=0` kullanması ayrı bir
  güvenilirlik açığıydı: anlık teslim edilemeyen wake-up doğrudan siliniyordu.
  Mesaj push TTL'i artık şifreli Redis kuyruk TTL'iyle aynı; çağrı TTL'i düşük
  gecikme ve bayat çağrı yüzeyi oluşturmamak için 30 saniye olarak kaldı.
- `group_call_invite` Android önceliği `NORMAL` yerine `HIGH` yapıldı.

### 21 Eylül kapalı uygulama araması ve sohbet çağrı kayıtları

- Bağlı `SM-S731B` üzerinde uygulama süreci `am kill` ile kapatıldı; paket
  force-stop durumuna geçirilmedi. Canlı arama FCM'i `10:05:29`'da receiver'ı
  ve Flutter background service'i başlattı. Native tanı sonucu kesin olarak
  `wake_no_hint` oldu: çalışan sunucu `securechat_wake_v2` payload'ına şifreli
  `k` tür ipucunu eklemiyor. Telefon izni, FCM teslimatı ve uygulama uyandırması
  bu denemede çalıştı; `ConnectionService` bu eksik alan nedeniyle tasarım
  gereği çağrılmadı.
- Receiver'ın daha önce sessizce döndüğü `k yok`, yerel anahtar yok, geçersiz
  ipucu, mesaj ipucu ve çağrı ipucu yollarına yalnız sabit durum kodları eklendi.
  Anahtar, token, ciphertext, kullanıcı veya çağrı kimliği loglanmıyor.
- Push anahtarı üretimi ve kayıt isteği de sessiz hata yutmuyor. Başarı yalnız
  `hint_submitted`, hata yalnız işlem adı ve hata sınıfıyla loglanıyor; ayrıntı
  mevcut şifreli yerel tanı deposuna gidiyor.
- Canlı aramayı düzeltmek için sunucunun en az `3e6e2b9` içeren sürüme deploy
  edilmesi ve alıcı uygulamanın bir kez açılarak cihaz ipucu anahtarını yeniden
  kaydetmesi zorunlu. Eski sunucu yeni `pushHintKey` alanını yok saydığı için
  yalnız APK güncellemesi yeterli değil.
- Sohbet ekranı artık ayrı bir sahte mesaj üretmeden mevcut yerel `callLogs`
  akışını mesajlarla zaman sırasına göre birleştiriyor. Her çağrı kaydı sesli /
  görüntülü türünü, gelen / giden yönünü, cevapsız / reddedildi / meşgul /
  başarısız sonucunu, cevaplanan aramada süreyi ve saatini gösteriyor.
- `CallSession.createdAt`, aramanın cevaplandığı an yerine gerçek başlatılma
  zamanını çağrı geçmişine yazıyor. Çağrı sekmesi ile sohbet içindeki kayıt aynı
  tekil `CallLogEntity` kaynağını kullanıyor.

Bu ek turun odak doğrulaması:

```text
flutter analyze --no-pub                                      temiz
push + media + chat UI odak testleri                          36/36 geçti
flutter test --no-pub                                         445/445 geçti
temiz flutter build apk --release                             geçti, 123.3 MB
bağlı SM-S731B güncelleme kurulumu                            geçti
bağlı cihaz kapalı süreç canlı FCM tanısı                     wake_no_hint
```
