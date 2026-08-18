# Autonomous Kotlin -> Flutter Migration Playbook

Bu belge, Kotlin/Android uygulamasinin Flutter/Android+iOS hedefine eksiksiz,
bakimi kolay ve guvenli bicimde tasinmasi icin ana calisma sozlesmesidir.
`MIGRATION_TRACKER.md` anlik durumu, bu belge ise nasil calisilacagini belirler.
Kullanici yeni bir oncelik vermedikce calisma bu kurallarla ve tracker'daki ilk
uygulanabilir acik kalemden otonom olarak devam eder.

Fiziksel Android davranislarinin kanit seviyesi ve siradaki cihaz turu
`DEVICE_PROD_READINESS_TRACKER.md` icinde tutulur. Bu matriste `NOT RUN`,
`PARTIAL` veya `BLOCKED` olan bir davranis yalniz host testi ya da kaynak
incelemesiyle tamamlanmis ilan edilmez.

## 1. Ana hedef ve tamamlanma tanimi

Hedef yalniz ekranlari benzetmek veya APK uretmek degildir. Kotlin kaynak
agacindaki her kullanici ozelligi, domain karari, hata davranisi, guvenlik
invariant'i, veri semasi, network/wire sozlesmesi, background isi ve native
entegrasyon icin Flutter production yolunda gercek bir karsilik bulunmalidir.

Bir davranis ancak su kosullarin tamami saglandiginda tasinmis sayilir:

1. Kotlin kaynak ve cagri zinciri dosya seviyesinde bulunmustur.
2. Basarili akis kadar timeout, iptal, tekrar deneme, process restart, bozuk veri,
   izin reddi ve yetkisiz istek davranisi da belirlenmistir.
3. Flutter karsiligi production composition root'a baglidir; yalniz testte veya
   kullanilmayan bir dosyada bulunmasi yeterli degildir.
4. Kullanici arayuzu gercek state/service ile calisir; bos callback, sahte veri,
   sessiz no-op ve `UnsupportedError` yoktur.
5. Android ve iOS davranisi ayri ayri ele alinmistir. Ortak Dart kodu kullanmak
   platformun native sorumlulugunu ortadan kaldirmaz.
6. Veri/wire uyumlulugu gereken yerde Kotlin fixture veya source contract ile
   capraz test vardir.
7. Guvenlik invariant'lari fail-closed test edilir; plaintext veya zayif
   fallback eklenmez.
8. Analyze, hedef testler, tam test paketi ve riskle orantili build kapilari
   gecer.
9. Karar, sapma ve kanit ilgili dokumanlara islenmistir.

Mac olmadan yapilamayan fiziksel iOS build, signing ve entitlement kaniti
`EXTERNAL BLOCKER` olabilir. Bu durum iOS kaynak kodunu, plist/entitlement
tasarimini, plugin secimini ve lifecycle davranisini ertelemek icin kullanilmaz.

## 2. Yetki ve otonom calisma kurali

Kullanici mevcut Kotlin kaynaklarina dokunmadan yeni Flutter agacinda gerekli
duzeltme, refactor, test, dokuman ve build araci eklemeye izin vermistir.

Her iterasyonda:

1. Tracker'daki ilk `IN PROGRESS` kalem secilir; yoksa ilk `OPEN` kalem acilir.
2. Kotlin kaynak, Flutter karsilik, testler ve production composition birlikte
   okunur.
3. Eksik davranis veya mimari borc kucuk, geri alinabilir paketlere ayrilir.
4. Uygulama ve hedef test ayni pakette eklenir.
5. Hedef test/analyze ile hizli geri bildirim alinir.
6. Modül sonunda tam test ve platform build kapilari calistirilir.
7. Tracker ve migration notes gercek sonuca gore guncellenir.
8. Kullanici komutu beklemeden sonraki uygulanabilir kaleme gecilir.

Yalniz su durumlarda kullanici girdisi beklenir: production credential/secret,
geri donulemez veri islemi, urun davranisini kokten degistiren bir tercih,
harici hesap/sozlesme veya fiziksel cihaz gereksinimi. Bunlar disinda makul ve
belgeli varsayimla ilerlenir.

## 3. Degistirilemez koruma sinirlari

- Kotlin/Android kaynak agaci referanstir; Flutter tasimasi icin degistirilmez.
- Kullaniciya ait mevcut dirty worktree dosyalari korunur.
- Mesaj sifreleme basarisizsa plaintext fallback kesinlikle yapilmaz.
- Client icine JWT signing secret, database password, service-account private
  key, Janus admin secret veya master API key konmaz.
- Migration kaynak veriyi silmez; once salt-okunur export, dogrulama ve atomik
  commit yapar. Destructive migration kullanilmaz.
- Kimlik/prekey/session/sender-key binary kayitlari zorunlu olmadikca yeniden
  uretilmez.
- Token, plaintext mesaj, telefon, raw user ID veya medya icerigi loglanmaz.
- Testi gecirmek icin production guvenlik kontrolu gevsetilmez.
- Platform kisiti sahte basari veya no-op ile gizlenmez.

## 4. Clean code ve mimari kurallari

### 4.1 Katman yonu

Bagimlilik akisi su yondedir:

`UI -> application/use-case -> domain contract -> infrastructure/platform`

- Widget'lar dogrudan HTTP, dosya sistemi, crypto primitive veya native channel
  calistirmaz.
- Use-case/application servisi is kurali ve transaction sinirini sahiplenir.
- DAO yalniz persistence sorumlulugunda kalir; UI metni veya network karari
  uretmez.
- Network istemcisi route, auth header, timeout ve parse sorumlulugunu kapsar;
  domain kararini vermez.
- Native bridge kucuk ve typed tutulur; Android/iOS sonuc semantigi Dart'ta
  normalize edilir.
- `AppContainer` yalniz composition root'tur. Is kurali veya uzun runtime
  algoritmasi burada bulunmaz.

### 4.2 Sinif ve dosya sorumlulugu

- Bir sinifin degismek icin tek baskin nedeni olmalidir.
- Bir dosya birden fazla bagimsiz lifecycle/state machine tasiyorsa bolunur.
- Buyuk dosya tek basina hata degildir; ancak 600+ satir veya cok sayida
  bagimsiz private akis review tetikler. Refactor davranis testleriyle once
  sabitlenir, sonra mekanik olarak yapilir.
- Ortak davranis kopyalanmaz; ama tek kullanim icin gereksiz interface/factory
  katmani da eklenmez.
- Public API isimleri domain dilini kullanir. `Manager`, `Helper`, `Utils`
  yalniz gercek kapsam aciksa kabul edilir.
- Mutable global state yoktur. Cache/in-flight birlestirme sahipli ve cleanup'li
  bir serviste tutulur.

### 4.3 Hata ve async kurallari

- Beklenen domain hatalari typed result/exception olarak ifade edilir.
- Guvenlik/parsing hatasi sessiz basariya donusturulmez.
- Fire-and-forget is yalniz sahipli `unawaited` kullanimiyla ve hata/lifecycle
  politikasi belirliyse kabul edilir.
- Stream subscription, timer, socket, recorder, renderer ve controller her
  terminal yolda kapatilir.
- Retry idempotent olmali; ayni ciphertext/message ID gerektiren yerde yeniden
  encrypt edilmez.
- Timeout her network/native sinirinda aciktir. Iptal state'i kullaniciya ve
  persistence'a tutarli yansir.

### 4.4 Test edilebilirlik

- Saat, randomness, network, filesystem ve native boundary gereken yerde
  enjekte edilir.
- Test fake'i production davranisini yeniden yazmaz; yalniz boundary'yi taklit
  eder.
- Private metoda gore degil dis davranis/invariant'a gore test yazilir.
- Golden/snapshot tek basina davranis kaniti sayilmaz.

## 5. Kotlin -> Flutter diferansiyel inceleme yontemi

Her Kotlin kaynak icin asagidaki sorular cevaplanir:

1. Bu dosya production graph'ta kullaniliyor mu?
2. Kullaniciya veya dis sisteme gozlenebilir davranisi nedir?
3. Hangi veri alanlarini okur/yazar; default/null/enum semantigi nedir?
4. Hangi thread/lifecycle/background kosulunda calisir?
5. Hangi guvenlik kararini uygular?
6. Android'e ozel kismi nedir; iOS karsiligi veya bilincli sapma nedir?
7. Flutter hedef dosyasi ve production caller'i hangisidir?
8. Bunu kanitlayan test ve build nedir?

`SOURCE_AUDIT.md` dosya eslemesini tutar. Bir linkin resolve olmasi yeterli
degildir; ikinci geciste davranis maddeleri ve production caller da dogrulanir.
Generator yalniz envanter alarmidir, insan incelemesinin yerine gecmez.

## 6. Platform kurallari

### Android

- Keystore, Telecom, foreground service, WorkManager, notification channel,
  ContactsContract, FileProvider ve SQLCipher migration gercek cihaz semantigine
  gore ele alinir.
- Release manifest `debuggable`, backup, exported component, cleartext ve
  permission yuzeyi icin denetlenir.
- AAB R8/resource shrinking ve Flutter AOT obfuscation ile uretilir; Dart/R8
  symbol dosyalari private tutulur. Play ingestion icin R8/native symbol
  `BUNDLE-METADATA` tasiyan AAB de public dagitilmaz; cihaza teslim edilen
  native payload'in stripped oldugu ve server secret tasimadigi otomatik
  release auditiyle kanitlanir.

### iOS

- Keychain accessibility, protected data, CallKit, AVAudioSession, Contacts,
  local notification, BGTask ve app-switcher privacy davranislari korunur.
- Uzun sureli background WebSocket veya kesin zamanli background task vaat
  edilmez; push + foreground reconciliation tasarlanir.
- Her plugin/API icin iOS deployment target, Info.plist usage string,
  Background Modes ve gerekli entitlement birlikte denetlenir.
- Swift callback/channel isimleri Dart tarafiyla capraz test veya statik audit
  ile sabitlenir.
- Linux'ta iOS build gecti denmez. Mac geldiginde once no-codesign simulator,
  sonra signed device/TestFlight kapisi uygulanir.

## 7. Guvenlik kontrol listesi

### 7.1 Gizlilik üstünlük kurali

Gizlilik; geriye uyumluluk, analitik kolayligi, operasyonel rahatlik ve teslim
suresinden once gelir. Bir ozellik calisiyor olsa bile gereksiz veri uretiyor,
sunucuya aktariyor veya gereğinden uzun tutuyorsa tamamlanmis sayilmaz.

Her yeni veri alani veya protokol frame'i icin karar sirasi degistirilemez:

1. Veri yalniz cihazda tutulabiliyorsa server modeline, loga veya metric'e
   eklenmez.
2. Canli teslim icin gerekiyorsa recipient-specific E2EE zarf icinde ve yalniz
   route suresince islenir; server alan adi/icerik/tur yorumlamaz.
3. Offline teslim zorunluysa yalniz client ciphertext'i, opaque key + ayri
   server AEAD ile persistence-kapali RAM store'da en kisa TTL boyunca kalir.
4. Kalici server kaydi yalniz authentication, public E2EE bootstrap veya push
   wake gibi ozelligin calismasi icin kanitlanmis zorunluluk varsa kabul edilir.
   Alan bazinda amac, tehdit, retention, silme ve backup davranisi yazilmadan
   migration eklenmez.
5. Bir ozellik plaintext icerik, kalici sosyal grafik veya davranissal zaman
   cizelgesi gerektiriyorsa ozellik/protokol yeniden tasarlanir; eski istemci
   uyumlulugu icin privacy siniri gevsetilmez.

Her server degisikliginden sonra PostgreSQL semasi, tum Redis key aileleri,
process cache'leri, push provider payload'i ve log satirlari yeniden envanterlenir.
"Sifreli" tek basina saklama izni degildir; ciphertext'in iliski, boyut, zaman
ve retention metadata'si de ayni incelemeye tabidir.

- Mesaj, medya, yedek, rehber adi ve private key plaintext olarak sunucuya
  cikmaz. Sifreleme basarisizsa aktarim durur.
- Sunucu mesaj gecmisi degildir. Offline teslim icin zorunlu E2EE zarf yalniz
  sinirli boyut ve kisa, acikca yapilandirilmis TTL ile, persistence-kapali
  Redis RAM'de tutulabilir; teslimde atomik silinir. RDB/AOF aciksa veya bu
  durum startup'ta dogrulanamiyorsa listener fail-closed acilmaz.
- E2EE icerigi saklasa bile sender/recipient/group/timestamp/size metadata'sinin
  hassas oldugu kabul edilir. Wire alanlari ve loglar minimuma indirilir.
- Edit/delete/reaction/pin, receipt, typing ve disappearing timer typed
  frame'leri plaintext route edilmez. Kimlige bagli direct Signal payload'i
  sabit boyuta doldurulur; server legacy discriminator'i fail-closed reddeder.
- Telefon discovery'de adres-defteri SHA-256 listesi TLS icinde dahi server'a
  acik gonderilemez. Sorgu sabit boyutlu cover batch, blind-OPRF ve istemci
  tarafinda acilan sealed snapshot kullanir; eslesme/sosyal grafik server'da
  persist edilmez. DB tokeni tek basina sozluk saldirisina yetmemeli, OPRF key'i
  DB/backup/mobil bundle'dan ayri ve tercihen export edilemez HSM'de olmalidir.
- E-posta ve push token icin amac, TTL, erisim siniri ve hesap silme davranisi
  ayri ayri kanitlanir. Grup uyeligi ve behavioral audit server persistence'a
  hic yazilmaz. User one-time prekey atomik teslimde hemen silinir.
- IP subnet'i ve UUID “anonim” sayilmaz; pseudonymous veri olarak retention ve
  erisim kontrolune tabi tutulur.
- Production'da test OTP'si, backdoor credential veya gevsek auth modu yoktur.
- Crash/operasyon loglari plaintext mesaj, token, tam e-posta, telefon, raw
  envelope, dosya adi, grup adi veya gereksiz kullanici iliskisi icermez.
- Hesap silme PostgreSQL, Redis, memory cache, push ve offline file queue
  kopyalarinin tumunu kapsar; yalniz ana `users` satirini silmek
  yeterli degildir.

- Production server artefakti yalniz `server_hardened` agacindan uretilir. Kok
  Kotlin server, davranis referansi olsa da privacy release hedefi sayilmaz.
- Privacy-first retention varsayilanlari offline mesaj 15 dakika, file 5
  dakika, bot queue/idempotency 15 dakika, consumed bot prekey 1 saat, push 30
  gun, expired/revoked bot credential 30 gun ve TURN 10 dakikadir.
  Mesaj/file/bot queue Redis'i yalniz RAM'dedir. Daha
  uzun config acik risk kabuludur ve kod sert ust sinirlari asamaz.
- DB'de telefon discovery ve push-token account iliskisi raw/reusable degerle
  tutulmaz; directory icin blind-RSA finalized token, push icin amaca ayri HMAC
  blind index ve AAD-bagli AEAD kullanilir. Grup
  sosyal grafigi, behavioral audit timeline'i ve user-prekey kullanim timeline'i
  migration ile fiziksel olarak silinir ve runtime'da yeniden uretilmez.
- Bir gecis migration'i icin eklenen raw kimlik/metadata kolonu final semada
  nullable birakilmaz. Donusum tamamlanmamissa sonraki migration veri silmeden
  fail-closed durur; tamamlaninca legacy kolon ve index fiziksel olarak
  kaldirilir. Final PostgreSQL tablo/kolon allow-list testi yeni persistence
  alanlarini bilincli privacy review olmadan release'e sokmaz.
- `PRIVACY_INDEX_KEY`, offline, push, bot master ve bot queue anahtarlari
  bagimsizdir. Secret eksik/ayniysa, Redis persistence kapatilamiyorsa veya
  legacy private-row conversion dogrulanmazsa listener acilmaz.
- E2EE kaynak IP, timing, size, canli route ve TURN/Janus trafik iliskisini
  saklamaz. Dokumanda bu sinir acik kalir; DB encryption "zero metadata"
  olarak sunulmaz.

Baglayici server veri/retention sozlesmesi `SERVER_DATA_PRIVACY_AUDIT.md`
icinde tutulur. Bu sozlesme veya statik privacy release gate gerilerse ilgili
modül yeniden acilir ve release tamamlanmaz.

- Signal V3 direct/group wire uyumlulugu ve TOFU/identity-change davranisi.
- No-plaintext-fallback ve tamper fail-closed.
- HTTPS/WSS, system trust ve primary+backup SPKI pin.
- Access/refresh/registration token tip, expiry, rotation ve revocation.
- Server tarafinda subject tabanli authorization; body `userId` guvenilmez.
- Rate/frame/file byte limitleri ve abuse log redaksiyonu.
- Keystore/Keychain anahtari, encrypted persistence ve backup dislama.
- Notification/lock-screen/view-once metadata gizliligi.
- Path traversal, zip bomb, dosya boyutu ve MIME guven sinirlari.
- Release obfuscation/symbol ayrimi; endpoint/public pin sir kabul edilmez.
- Play Integrity/Apple App Attest yalniz server-verified risk sinyalidir; normal
  auth veya E2EE yerine kullanilmaz.
- Ucuncu taraf dependency cihaz plaintext/anahtarlarina erisebildigi icin
  supply-chain gizlilik siniridir: direct Pub surumleri exact, hosted lock
  girdileri SHA-256'li, Gradle wrapper ve Maven artefaktlari checksum'li olur.
  Git/path dependency, HTTP repo, `mavenLocal()`, effective JitPack veya
  wildcard verification bypass'i release'te kabul edilmez.
- Native plugin kendi repository'sini eklese bile settings seviyesindeki
  allow-list onceliklidir. Zorunlu dis artefakt reviewed local Maven deposuna
  byte hash ve lisansiyla vendor edilir; offline bundle bu depoyu tasir.
- Copyleft dahil tum dogrudan lisanslar envanterlenir ve uygulama icinden
  erisilebilir olur. Lisans yukumlulugu kriptografiyi daha zayif bir
  implementasyonla sessizce degistirme gerekcesi degildir.

## 8. Test ve build kapilari

### Her kucuk paket

- `dart format` degisen Dart dosyalari
- `flutter analyze`
- ilgili hedef test dosyalari

### Her modül kapanisi

- tam `flutter test`
- saf-Dart/Kotlin wire fixture varsa capraz test
- `android/gradlew assembleDebug --offline`
- native Android degisikliginde instrumentation testi
- release/security degisikliginde hardened AAB ve merged-manifest denetimi
- iOS dosyasi degisikliginde channel/plist/project statik audit; Mac mevcutsa
  `flutter build ios --no-codesign` ve Xcode test

Flaky test tekrar calistirilip yesil sayilmaz. Once neden bulunur; saat/network
beklentisi deterministik hale getirilir.

## 9. Dokuman ve kanit duzeni

- `MIGRATION_TRACKER.md`: tek anlik durum kaynagi.
- `MIGRATION_NOTES.md`: ne degisti, Kotlin'den neden sapildi, risk ve test.
- `FEATURE_MAP.md`: kullaniciya donuk ozellik durumu.
- `SOURCE_AUDIT.md`: 271 Kotlin/Java dosyasinin hedef/test eslemesi.
- `SERVER_CONTRACT_AUDIT.md`: Ktor route ve Signal discriminator paritesi.
- `ROOM_SCHEMA_MAP.md`: Room/SQLCipher sema ve binary migration kararlari.
- `ANDROID_RELEASE_SECURITY.md`: Play release tehdit modeli ve build akisi.
- `SUPPLY_CHAIN_AUDIT.md`: Pub/Gradle/SPM lock, repo, checksum ve lisans kaniti.
- `MACOS_IOS_BUILD.md`: daha sonra uygulanacak Mac/Xcode kapisi.

Her `DONE` satiri komut sonucu, test sayisi ve gerekiyorsa artefakt/checksum
kaniti tasir. Eski test sayilari tarihsel gunlukte kalabilir; ustteki son yesil
taban daima guncellenir.

## 10. Blocker ve bitis kurali

`EXTERNAL BLOCKER` yalniz kodla ilerlenemeyen dis gereksinimdir. Blocker'in
onundeki hazirlik kodu, test fixture'i, script ve dokuman tamamlanmadan bu durum
verilemez.

Gecis ancak:

- tum uygulanabilir tracker satirlari `DONE`,
- tum dis blocker'lar acik gereksinim ve calistirilabilir dogrulama scriptiyle
  belgeli,
- son diferansiyel audit `GAP=0`,
- Android hardened release ve izole air-gapped restore basarili,
- Mac geldiginde iOS build/runtime kapilari basarili

oldugunda tam bitmis sayilir. Bu noktaya kadar “tamamlandi” ifadesi yalniz
belirli modül veya platform kapsami icin kullanilir.

## 11. Siradaki otonom denetim dalgasi

Tamamlanan ikinci gecis dalgalari: clean architecture, async/resource ownership,
server veri minimizasyonu/metadata privacy ve dependency/license/supply-chain.

1. iOS Swift/Dart channel, plist, entitlement ve plugin static readiness audit'i.
2. Son davranissal diferansiyel audit ve hardened release kanit yenilemesi.
3. Mac elde edildiginde no-codesign simulator, signed device/TestFlight ve iOS
   air-gapped supplement kapisi.

Bu liste yeni bulgu cikarsa tracker'da atomik modüllere ayrilir ve kullanicidan
ayrica “devam et” komutu beklenmeden uygulanir.
