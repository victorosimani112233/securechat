# SecureChat Kriptografik İnceleme Raporu

**Tarih:** 2026-08-26  
**İnceleme kapsamı:** `flutter_securechat/server_hardened/` sunucu ve bot kodu,
`flutter_securechat/lib/` Flutter istemcisi, ilgili testler ve wire sözleşmeleri  
**Kaynak taban commit'i:** `35b6c6fee0ad6a5b930b0a41395235fb33a29334`  
**İncelenen durum:** Yukarıdaki commit ile birlikte 2026-08-26 tarihli çalışma
ağacındaki kripto düzeltmeleri. Çalışma ağacı temiz olmadığı için bu rapor yalnız
taban commit'i değil, test edilen güncel dosya içeriğini tarif eder.  
**Brief:** `docs/CRYPTO_REVIEW_BRIEF.md`

**2026-09-17 uygulama güncellemesi:** Signed-prekey yaşam döngüsü, AEAD key
ID/nonce bütçesi, bot private-key AAD bağı, SecretSource TOCTOU ve backup
Argon2id bulguları aşağıda kapatıldı. Official Rust libsignal V2 geçişi için
ayrı tasarım ve sınırlar `../docs/MODERN_LIBSIGNAL_MIGRATION.md` içindedir.
2026-09-17'de resmi Sealed Sender + HMAC indeksli anonim mailbox relay'i de
uygulandı. Bu, sonraki mesajlarda sender credential'ini relay'den kaldırır;
ilk authenticated capability değişimi ile IP/zaman korelasyonu nedeniyle
"operatör sosyal grafiği hiçbir koşulda göremez" bulgusunu tamamen kapatmaz.
Kapanış kapısı 438 Flutter, 1.179 signaling ve 190 bot testi, temiz analyze,
iOS/Codemagic statik audit ve üç ABI'li Android release AAB ile geçmiştir; Xcode
iOS binary/runtime kanıtı macOS dış kapısında kalır.

## Executive summary

İnceleme sonucunda standart kriptografik primitiflerin büyük kısmı doğru
parametrelerle kullanılıyor: AES-256-GCM 96 bit nonce ve 128 bit tag ile,
HMAC-SHA256 blind indexlerde, Ed25519 ise JDK sağlayıcısı üzerinden kullanılıyor.
Signal Protocol akışları hazır kütüphaneye dayanıyor. İnceleme sırasında bulunan
uygulama kusurları için kod ve regresyon testleri eklendi; Wycheproof vektörleri
aynı JCA sağlayıcısında çalıştırıldı.

Bununla birlikte ürünün ilan edilen tehdit modelindeki üç temel garanti mevcut
mimariyle sağlanmıyor:

1. Tek sunuculu blind-RSA OPRF'nin private key'ini tutan operatör, telefon
   sözlüğünü kendi başına değerlendirip kayıtlı directory tokenlarıyla
   eşleştirebilir.
2. E-posta OTP, kayda yazılan telefon numarasının sahipliğini kanıtlamaz. İlk
   directory-token yazan hesap başka bir numarayı kendine bağlayabilir.
3. Sealed Sender sonraki doğrudan mesajlarda kimliği doğrulanmış göndereni
   relay'den kaldırır; fakat ilk authenticated capability/prekey bootstrap'ı,
   çağrı yönlendirmesi ve IP/zaman korelasyonu nedeniyle sunucu operatöründen
   tam sosyal grafik gizleme iddiası hâlâ doğru değildir.

Ek olarak ilk Signal teması TOFU'dur. Aktif/kötücül bir sunucu ilk prekey bundle'ı
değiştirirse istemci bunu bağımsız bir kanal veya key-transparency kaydıyla
algılayamaz. Sonraki identity değişiklikleri artık fail-closed olsa da ilk temas
garantisi değişmemiştir.

**Sürüm kararı:** Mesaj içeriği E2EE işlevi ve standart primitif kullanımı için
test kapıları geçiyor; ancak uygulama, yukarıdaki açık CRITICAL/HIGH mimari
bulgular çözülmeden “sunucu operatörüne karşı özel rehber”, “telefon kimliği
doğrulanmış hesap” veya “sunucudan gizli sosyal grafik” garantileriyle
yayınlanmamalıdır.

**Harici uzman kararı:** **Evet, zorunlu.** Novel directory protokolü, üretim
migrasyonu yapılmadan önce uygulamadan bağımsız bir kriptograf tarafından ve
protokol seviyesinde incelenmelidir. Mümkünse özel RSA tasarımı yerine
[RFC 9497](https://www.rfc-editor.org/rfc/rfc9497.html) ile uyumlu VOPRF/POPRF
ve operatör sözlüğünü gerçekten engelleyen, birbirinden bağımsız eşik sunucuları
veya uzaktan doğrulanmış TEE mimarisi kullanılmalıdır. VOPRF tek başına, private
key'i tutan operatörün sözlük çalıştırmasını engellemez.

## Garanti matrisi

| Garanti | Sonuç | Sınır/koşul |
|---|---|---|
| Sunucu mesaj içeriğini okuyamaz | Koşullu olarak tutuyor | Signal identity ilk temasta doğruysa, uç cihaz/anahtar ele geçirilmemişse ve trafik analizi içerik sayılmıyorsa |
| Offline queue ve bot private alanları DB kopyasına karşı gizlidir | Tutuyor | AEAD anahtarları DB ile birlikte alınmamalı; ciphertext key ID taşır ve her process-prefix altında `2^32` seal sınırı vardır |
| Her OPRF isteğinde telefon hash'i request'te görünmez | Tutuyor | Geçerli ve dürüst RSA anahtarı altında blind işlem için |
| Sunucu operatörü telefon sözlüğü çalıştıramaz | **Tutmuyor** | Operatör private OPRF key/HSM erişimiyle aynı tokenları üretir |
| Telefon numarası hesap sahibine doğrulanmış şekilde bağlıdır | **Tutmuyor** | Kayıt kanıtı e-posta OTP'dir, SMS/voice/telefon capability kanıtı yoktur |
| Sunucu sosyal grafiği öğrenemez | **Tutmuyor** | Capability değişiminden sonraki doğrudan mesajlarda Sealed Sender gönderen credential'ini gizler; ilk authenticated bootstrap, hedef mailbox eşlemesi, çağrı yolu ve IP/zaman korelasyonu kalır |
| İlk Signal teması aktif sunucu MITM'ine dayanıklıdır | **Tutmuyor** | TOFU var; safety-number onayı/key transparency yok |
| Sonraki Signal identity değişimi sessizce kabul edilmez | Tutuyor | İstemci ve bot yolları fail-closed; kullanıcı onay akışı ayrıca tamamlanmalı |
| Paralel Signal işlemleri ratchet state'i bozmaz | Tutuyor | İncelenen process içi per-peer/per-sender-key kilit kapsamı için |
| SFU çağrı media key'ini öğrenmez | Tutuyor | Anahtar yalnız direct Signal zarfında; katılımcı uç noktanın ele geçirilmesi kapsam dışı |
| JWT/service assertion tekrar kullanılamaz | Tutuyor | Redis replay store erişilebilir olmalı; hata halinde fail-closed |
| Yedek başka cihazda Signal private state klonlamaz | Tutuyor | Yeni v3 oluşturma ve eski v2 restore filtreleri için |

## Yöntem ve kanıt

- Özel OPRF'nin istemci/sunucu matematiği ayrı ayrı ve birlikte izlendi; grup
  aralığı, `gcd`, körleme, unblind, token türetme ve snapshot şekli kontrol
  edildi.
- Python ile JCA/Dart kodundan bağımsız deterministik OPRF KAT üretildi.
  `tools/crypto-audit/vectors/oprf_cross_language_kat.json` SHA-256 değeri
  `60a70404b766535c81f421c8528026ebd6a464168cdf0a7939b28a79ef7cdac9`.
- [C2SP Wycheproof](https://github.com/C2SP/wycheproof) commit'i
  `dac1dd4729fd1f8dd9e1e9f3dce51d783da6c166` olarak pinlendi. Aynı JCA
  sağlayıcısında 66 AES-GCM, 151 Ed25519, 170 HMAC-SHA1 ve 174 HMAC-SHA256,
  toplam 561 vaka çalıştırıldı.
- [CogniCrypt/CryptoAnalysis](https://github.com/CROSSINGTUD/CryptoAnalysis)
  5.0.1 pinli scanner/rules hash'leriyle advisory modda çalıştırıldı. Signaling
  için 49, bot için 27 uyarı elle sınıflandırıldı. Bunlar Ed25519 allowlist
  eksikliği, dışarıdan yüklenen anahtarların üretimini görememe, interprocedural
  GCM nonce takibini yapamama, raw-RSA OPRF'yi modellememe ve TURN için protokol
  gereği HMAC-SHA1'i genel amaçlı zayıf kullanım sanma kaynaklıdır. Araç
  bulgular varken de sıfır çıkış kodu verdiği için CI'da engelleyici değil,
  advisory'dir.
- CryptoGuard'ın resmi sürümü Java 8 bytecode/`JAVA_HOME` varsayımına bağlı;
  proje Java 17 bytecode ürettiği için bu çalışma için güvenilir bir “PASS”
  kaynağı olarak kullanılmadı.
- Tamarin/ProVerif modeli oluşturulmadı. Directory mimarisi değişmeden mevcut
  protokolü formel olarak kanıtlamak, sağlanmayan hedefleri düzeltmez.

## Bulgular

### [AÇIK] Tek sunuculu OPRF, anahtar sahibi operatöre karşı oblivious değil
- Severity: CRITICAL
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/PrivateDirectoryOprf.kt:43`, `:90`, `:186`
- Sınıf: oblivious-break, threat-model-mismatch
- Açıklama: Körleme tek bir istemci sorgusunun girdisini sunucudan gizler; fakat aynı sunucu RSA private key'i ve kayıtlı finalized tokenları tutar. Kodda `tokenForPhoneHash()` operatörün yapması gereken sözlük işlemini doğrudan gerçekleştirir. Bu, DB-only saldırgana karşı yararlı olsa da key sahibi honest-but-curious operatöre karşı hedefi sağlamaz.
- Somut senaryo: Operatör olası E.164 numaralarını SHA-256'ler, her birini private RSA operasyonundan geçirip `finalizeToken()` çağırır ve sonuçları `users.directory_token` ile join eder. Kayıtlı telefonlar ve UUID'ler açığa çıkar.
- Doğrulama: `tokenForPhoneHash()` çağrısının istemci körlemesi olmadan `fullDomainPoint -> privateOperation -> finalizeToken` zincirini üretmesi statik olarak doğrulandı; mevcut OPRF round-trip KAT aynı eşitliği kanıtlar.
- Öneri: En az iki gerçekten bağımsız, non-colluding eşik OPRF/PSI sunucusu veya uzaktan doğrulanmış ve key-export'u engellenmiş TEE kullanın. Key tutan tek operatörü tehdit modelinden çıkaracaksanız ürün iddiasını açıkça daraltın. Yeni protokol için versiyonlu token migrasyonu, key epoch ve harici kripto incelemesi zorunlu olsun.
- Güven: CONFIRMED

### [AÇIK] E-posta OTP telefon sahipliğini kanıtlamıyor
- Severity: CRITICAL
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt:434`, `:503`, `:511`, `:517`; `signaling-server/src/main/kotlin/com/securechat/signaling/UserRegistry.kt:66`, `:92`; `../lib/src/auth/auth_coordinator.dart:45`
- Sınıf: identity-misbinding, impersonation
- Açıklama: Registration grant yalnız e-posta OTP kontrolünden doğuyor. Telefon numarası istemcide seçiliyor ve kayıt sonrası authenticated hesap kendi finalized OPRF tokenını yazıyor; sunucu bu numaranın o hesaba ait olduğunu kanıtlayan bir capability görmüyor.
- Somut senaryo: Saldırgan kendi e-postasıyla OTP alır, kurbanın telefon numarasını istemcide girer ve kurban tokenını ilk yazan hesap olur. Rehber keşfi bu token için saldırganın UUID/prekey bundle'ına yönelir; gerçek kullanıcı da token uniqueness nedeniyle kaydı üstlenemez.
- Doğrulama: OTP request/verify payloadında telefon kanıtı olmadığı, `updateOwnDirectoryToken()` sahipliği yalnız authenticated UUID ve token uniqueness ile kontrol ettiği kaynak akışından doğrulandı.
- Öneri: SMS/voice OTP'yi registration grant, Signal identity public key ve tek kullanımlık nonce'a kriptografik olarak bağlayın. SMS kullanılmayacaksa QR/invite capability gibi açıkça farklı bir kimlik modeli tasarlayın; “telefon hesabı” iddiasını kaldırın. Token claim yarışını atomik ve yeniden sahiplenme prosedürlü yapın.
- Güven: CONFIRMED

### [KISMEN AZALTILDI] Routing metaverisi sosyal grafiği hâlâ kısmen açığa çıkarıyor
- Severity: HIGH
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt:1121`, `:1150`, `:1202`; `signaling-server/src/main/kotlin/com/securechat/signaling/AnonymousMailboxStore.kt:17`, `:96`; `signaling-server/src/main/kotlin/com/securechat/signaling/WebSocketRoutes.kt:502`; `../lib/src/crypto/anonymous_mailbox.dart:142`, `:417`
- Sınıf: metadata-disclosure, threat-model-mismatch
- Açıklama: Official libsignal Sealed Sender, ilk authenticated capability değişiminden sonraki doğrudan mesajlarda gönderen JWT/UUID'sini anonim relay isteğinden kaldırır. Relay yalnız HMAC indeksli hedef mailbox ile write capability'yi işler ve teslimat zarfına sabit `senderId=sealed` yazar. Bununla birlikte mailbox kaydı ve ilk capability/prekey bootstrap'ı authenticated'dır; sunucu hedef mailbox'ı kullanıcıya çözebilir. Çağrı sinyallemesi ile kaynak IP, zaman ve padding kovası da operatöre görünür.
- Somut senaryo: Operatör sonraki bir anonim doğrudan mesajın sertifikalı gönderen UUID'sini relay isteğinden okuyamaz; fakat aynı istemcinin authenticated bootstrap trafiğini, relay kaynak IP/zamanını, çözülen hedef hesabı ve çağrı olaylarını korele ederek olası ilişki grafiği çıkarabilir. Directory eşlemesi elde edilirse kalan grafik telefonlara da bağlanabilir.
- Doğrulama: `/api/v2/sealed-sender/messages` JWT kabul etmeden mailbox write capability ile yetkilendirir; `AnonymousMailboxStore` ham capability yerine amaç ayrımlı HMAC indeksleri saklar; istemci iç kimliği official sender certificate doğrulamasından sonra açar. Authenticated WebSocket yolu `SEALED:v1` zarflarını downgrade olarak reddeder. İlk capability endpoint'i, mailbox kaydı, çağrı yolu ve IP tabanlı rate limit ise korelasyon yüzeyinin sürdüğünü doğrular.
- Öneri: Sealed Sender relay'inin önüne operatörden bağımsız oblivious ingress/mix katmanı koyun; ilk capability ve prekey bootstrap'ını private discovery ile birleştirin. Trafik şekillendirme/cover traffic ve çağrılar için ayrı metadata-minimizing yönlendirme tasarlayın. Bunlar tamamlanana kadar ürün iddiasını içerik gizliliği ve azaltılmış gönderen metaverisiyle sınırlandırın.
- Güven: CONFIRMED

### [AÇIK] İlk Signal teması TOFU ve aktif sunucu MITM'ine açık
- Severity: HIGH
- Konum: `../lib/src/crypto/crypto_protocol_store.dart:79`, `:92`; `../lib/src/crypto/signal_protocol_crypto_service.dart:109`, `:136`; `bot-api/src/main/kotlin/com/securechat/botapi/signal/PgSignalProtocolStore.kt:82`, `:107`
- Sınıf: key-substitution, TOFU
- Açıklama: İlk görülen peer identity key güvenilir kabul ediliyor. Sonraki farklı identity artık fail-closed; ancak ilk bundle için sunucudan bağımsız doğrulama, safety-number kabulü veya append-only key transparency yok.
- Somut senaryo: Kötücül sunucu ilk prekey isteğinde saldırgan identity/signed-prekey bundle'ı döndürür, iki ayrı Signal oturumu kurar ve mesajları iki uç arasında yeniden şifreler. Kullanıcı ilk pinin sahte olduğunu anlayamaz.
- Doğrulama: Boş identity store için `isTrustedIdentity()` true döner; bot `pinIfAbsent()` ile ilk anahtarı pinler. Identity-change regresyonları yalnız sonraki değişimi reddeder.
- Öneri: Kullanıcıya doğrulanabilir safety number/QR akışı ekleyin ve kabul durumunu kimlik anahtarına bağlayın. Ölçekli çözüm olarak imzalı, append-only key transparency logu, inclusion/consistency proof ve gossip kullanın. Bot kimlikleri önceden provision edilmiş pinle dağıtılmalı.
- Güven: CONFIRMED

### [AÇIK] OPRF keyId self-hash'i verifiability veya kalıcı pin sağlamıyor
- Severity: HIGH
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/PrivateDirectoryOprf.kt:63`, `:72`; `../lib/src/contacts/private_contact_discovery.dart:107`, `:112`, `:268`, `:350`
- Sınıf: key-substitution, split-view, unverifiable-oprf
- Açıklama: İstemci `keyId == SHA-256(SPKI)` kontrolü yapıyor ve config'i yalnız process içinde cache'liyor. Bu, verilen modulus ile verilen keyId'nin tutarlı olduğunu gösterir; anahtarın önceki/diğer istemcilerle aynı olduğunu veya sunucunun değerlendirmeyi doğru yaptığını göstermez.
- Somut senaryo: Sunucu hedef istemciye ayrı bir RSA modulus/keyId sunar, split-view yaratır veya seçilmiş modulusla girdiye bağlı davranış gözler. Uygulama yeniden başlatılınca kalıcı pin olmadığı için yeni anahtar sessizce kabul edilir.
- Doğrulama: Config parse kodu self-hash kontrolünden sonra `_cachedConfig` alanına yazar; disk üzerinde imzalı commitment/previous-key zinciri yoktur.
- Öneri: RFC 9497 VOPRF ile proof doğrulaması, imzalı key epoch, kalıcı pin, transparency log ve gossip ekleyin. Modulus/key üretimini bağımsız audit edin. Bunun tek-operatör dictionary bulgusunu tek başına çözmediğini tasarımda belirtin.
- Güven: CONFIRMED

### [AÇIK] Snapshot farkları yeni gerçek kaydı işaretleyebilir
- Severity: MEDIUM
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/DirectorySnapshotCache.kt:47`, `:84`, `:96`, `:102`, `:106`
- Sınıf: temporal-linkability, metadata-leak
- Açıklama: Decoy seed'i `real.size until target` indeksinden türetiliyor ve aynı indexte stabildir. Aynı padding kovasında gerçek kullanıcı sayısı `n`den `n+1`e çıkınca eski decoy index `n` kaybolur ve bir deterministik gerçek label eklenir. Ardışık snapshot farkı yeni gerçek labelı ayırt edebilir.
- Somut senaryo: Authenticated saldırgan snapshot'ı sık aralıkla indirir. Tek kayıt eklendiğinde bir stable decoy labelın kaybolup yeni labelın geldiğini görür; OPRF tahminleri veya dış zaman bilgisiyle yeni hesabı eşler.
- Doğrulama: `for (index in real.size until target)` ve deterministik `blindIndex(... index)` formülü üzerinde `n -> n+1` farkı elle üretildi; mevcut shape testleri zamansal iki snapshot saldırısını kapsamıyor.
- Öneri: Her snapshot epoch'unda tüm decoy setini ve sıralamayı yeniden randomize edin; gerçek entry labellarını da epoch'a bağlı, istemcinin kendi tokenıyla çözebileceği şekilde yeniden tasarlayın. Polling görünürlüğünü azaltmak için anonim erişim ve epoch batching ekleyin; yeni tasarımı differencing testine bağlayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] OPRF körleme faktöründe modulo yanlılığı
- Severity: HIGH
- Konum: `../lib/src/contacts/private_contact_discovery.dart:139`, `:141`, `:151`, `:658`; `../test/private_directory_oprf_kat_test.dart:54`
- Sınıf: biased-randomness, oblivious-break
- Açıklama: Önceki kod modulus genişliğinde tek rastgele tamsayı üretip `% (modulus-3)` uyguluyordu. Modulus 2'nin kuvveti olmadığı için grup elemanlarının bazıları yaklaşık iki kat daha sık oluşabiliyordu. Private key sahibi sunucu, aday telefonlar için körleme köklerini hesaplayıp çoklu sorgularda likelihood sinyali biriktirebilirdi.
- Somut senaryo: Sunucu her aday hash için `r^e = blinded / H(phone)` değerini private exponent ile çözer ve çıkan `r`nin yüksek/düşük olasılık bölgesinde olmasını ölçer. Tek sorgu kesin çözüm vermese de tekrarlar aday ayrımı üretir.
- Doğrulama: Eski modulo dağılımı matematiksel olarak karşılaştırıldı. Yeni test önce modulusun kendisini RNG'den döndürerek reddedildiğini, sonra geçerli faktörün kabulünü ve iki tam genişlik tüketildiğini doğrular.
- Öneri: Uygulanan masked rejection sampling'i koruyun; `1 < r < N` ve `gcd(r,N)=1` şartlarını değiştirmeyin. KAT ve adversarial RNG testi CI'da kalmalı.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Registration API deterministic phone hash kabul ediyordu
- Severity: HIGH
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt:526`, `:528`; `signaling-server/src/main/kotlin/com/securechat/signaling/UserRegistry.kt:66`, `:77`, `:106`; `../lib/src/auth/auth_coordinator.dart:59`
- Sınıf: direct-identifier-disclosure, protocol-downgrade
- Açıklama: Telefon hash'i registration DTO/API sınırından kaldırıldı. Ayrıca kotlinx.serialization varsayılan olarak bilinmeyen alanı kabul edebildiği için registration parser `ignoreUnknownKeys=false` yapıldı; aksi halde eski `phoneHash` alanı sessizce taşınabiliyordu.
- Somut senaryo: Eski veya değiştirilmiş istemci `phoneHash` alanını kayıt isteğine koyar; sunucu/log/ara katman deterministic identifier görür ve OPRF gizliliği bypass edilir.
- Doğrulama: E2E test eski `phoneHash` içeren payloadın reddedildiğini ve yeni kaydın random `pending:<24B>` token ile snapshot dışında kaldığını doğrular.
- Öneri: Strict parser ve random pending tokenı koruyun. API şema testinde yasak alan adlarını mutasyonla göndermeye devam edin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Media key göndereni ve epoch'u yeterince bağlamıyordu
- Severity: HIGH
- Konum: `../lib/src/media/call_manager.dart:209`, `:218`, `:228`, `:265`; `../lib/src/media/call_media_key.dart:1`; `../lib/src/incoming/incoming_message_handler.dart`
- Sınıf: key-injection, replay, state-confusion
- Açıklama: Incoming `CALLKEY` artık authenticated Signal `senderId` ile işleniyor; yalnız mevcut coordinator kabul ediliyor. Eski epoch reddediliyor, aynı epoch/aynı key idempotent, aynı epoch/farklı key ise çağrıyı sonlandırıyor. Key-before-invite cache'i 16 kayıt ve iki dakika ile sınırlandı.
- Somut senaryo: Katılımcı veya replay yapan peer başka callId/epoch için anahtar enjekte ederek FrameCryptor key slotunu değiştirmeye çalışır. Eski davranış çağrının yanlış anahtarla sürmesine veya medya downgrade'ına yol açabilirdi.
- Doğrulama: Foreign sender/call, stale epoch, conflicting same epoch, key-before-invite TTL/limit ve state temizleme testleri eklendi ve geçti.
- Öneri: Authenticated sender bağını ve monoton epoch kuralını wire sözleşmesinin parçası tutun. Yeni protokol sürümünde call transcript hash'ini de anahtar mesajına bağlamayı değerlendirin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Media key kısmi dağıtımında E2EE fail-open kalabiliyordu
- Severity: HIGH
- Konum: `../lib/src/media/call_manager.dart:127`, `:172`, `:208`, `:242`; `signaling-server/src/main/kotlin/com/securechat/signaling/WebSocketRoutes.kt:496`
- Sınıf: partial-key-distribution, downgrade
- Açıklama: Coordinator anahtarı tüm katılımcılara direct Signal zarfıyla ulaştırmadan local FrameCryptor şifrelemesini etkinleştirmiyor ve E2EE capability ilan etmiyor. Rotasyonda tek bir delivery hatası çağrıyı bitiriyor. Sunucu invite içeriğinden recipient capability tahmin etmiyor; her katılımcı kendisininkini bildiriyor.
- Somut senaryo: Bir alıcıya anahtar gönderimi başarısızken coordinator yerelde şifrelemeyi açar veya sunucu capability'yi yanlış çıkarır; katılımcılar farklı güvenlik durumlarıyla aynı çağrıda kalır.
- Doğrulama: Failure-injection testleri ilk dağıtım/rotasyon hatasında E2EE'nin ilan edilmediğini ve çağrının sonlandığını doğrular.
- Öneri: Bu all-or-nothing davranışı koruyun. Gelecekte grup üyeliği transcript'i ve key confirmation ekleyerek tüm uçların aynı epoch'u kurduğunu doğrulayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Signal identity değişimi otomatik session reset ile kabul ediliyordu
- Severity: HIGH
- Konum: `../lib/src/crypto/signal_protocol_crypto_service.dart:116`, `:136`, `:173`, `:202`; `../lib/src/chat/security_notice_service.dart`
- Sınıf: identity-key-replacement, MITM
- Açıklama: `UntrustedIdentityException` yakalandığında peer identity/session silip yeniden kurmak yerine güvenlik bildirimi oluşturuluyor ve hata tekrar fırlatılıyor. Otomatik recovery bu durumu resetlenebilir session arızası saymıyor.
- Somut senaryo: Sunucu veya ele geçirilmiş hesap yeni identity bundle döndürür. Otomatik silme, mevcut güven pinini kaldırarak saldırgan anahtarını yeni ilk kullanım gibi kabul ettirebilirdi.
- Doğrulama: Identity değişimi testinde eski pin korunuyor, mesaj reddediliyor ve security notice üretiliyor.
- Öneri: Fail-closed davranışı koruyun; eski/yeni safety number gösteren açık kullanıcı onayı eklenmeden pini silmeyin. İlk temas bulgusu ayrıca çözülmeli.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Paralel Signal işlemleri ratchet state yarışına açıktı
- Severity: HIGH
- Konum: `../lib/src/crypto/signal_protocol_crypto_service.dart:14`, `:116`, `:182`, `:202`, `:236`, `:277`
- Sınıf: concurrency, ratchet-state-corruption
- Açıklama: Direct send/decrypt/session-establish işlemleri peer başına; SenderKey işlemleri group/sender başına async mutex ile seri hale getirildi. Önceden iki concurrent operation aynı session recordu okuyup farklı state'i son yazanla ezebilirdi.
- Somut senaryo: Aynı alıcıya 64 paralel mesaj iki ratchet adımını aynı başlangıç state'inden üretir; kaydedilen chain state ile wire mesaj sırası ayrışır ve mesajlar çözülemez veya key reuse oluşabilir.
- Doğrulama: 64 paralel direct mesaj regresyonu ve bot `RatchetConcurrencyIntegrationTest` geçti.
- Öneri: Lock anahtarını device ID eklenirse device seviyesine taşıyın; çok process/isolated worker mimarisinde DB transaction/advisory lock eklemeden process-local mutex'e güvenmeyin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Yedek ve logout Signal private state'i yeniden kullanabiliyordu
- Severity: HIGH
- Konum: `../lib/src/backup/backup_service.dart:67`, `:148`, `:205`; `../lib/src/auth/auth_coordinator.dart:100`, `:121`; `../lib/src/services/key_material_store.dart:46`
- Sınıf: key-cloning, state-reuse
- Açıklama: Backup v3 identity private key, prekey, signed prekey, session, sender key, pending key ve crypto state tablolarını dışarı çıkarmıyor. Eski v2 restore sırasında da bu alanlar filtreleniyor. Logout/clear-auth protocol state'i temizliyor; secure storage hata durumunda sessiz reset yapmıyor ve iOS Keychain girdisi this-device ile sınırlandı.
- Somut senaryo: Şifreli backup başka cihaza restore edilerek aynı identity/ratchet state iki cihazda klonlanır veya logout sonrası yeni hesap eski sessionları kullanır.
- Doğrulama: Crafted v2 private-state restore testi ve v3 oluşturma testi yasak tabloların gelmediğini; auth testleri protocol state temizliğini doğrular.
- Öneri: Backup schema allowlist'ini koruyun. Identity transferi istenirse genel DB yedeği yerine iki cihaz arasında ayrı, kullanıcı onaylı ve tek kullanımlık device-link protokolü tasarlayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Prekey upload hatası ve lokal/sunucu sayaç ayrışması sessiz kalabiliyordu
- Severity: MEDIUM
- Konum: `../lib/src/auth/auth_api.dart:162`, `:171`; `../lib/src/crypto/pre_key_maintenance_service.dart:30`, `:75`; `signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt:762`
- Sınıf: prekey-exhaustion, state-divergence
- Açıklama: Upload artık non-2xx yanıtta hata veriyor. Maintenance yalnız lokal sayaçla karar vermek yerine authenticated sunucu status endpointini kontrol ediyor ve upload başarısızsa yeni lokal prekeyleri geri alıyor.
- Somut senaryo: Ağ/proxy uploadı reddederken istemci lokal havuzu dolu sanır; sunucu havuzu tükenir ve yeni X3DH oturumları kurulamaz.
- Doğrulama: “server low/local high”, upload rollback ve gereksiz üretmeme testleri geçti.
- Öneri: Sunucu count metriğini alarm üretmek için kullanın ve upload transactionını idempotent batch ID ile güçlendirin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Signed prekey rotasyonu üretim yaşam döngüsüne bağlı değil
- Severity: MEDIUM
- Konum: `../lib/src/crypto/pre_key_manager.dart:59`, `:115`; `../lib/src/crypto/pre_key_maintenance_service.dart:30`; `bot-api/src/main/kotlin/com/securechat/botapi/signal/BotIdentityBootstrap.kt`
- Sınıf: key-lifecycle, stale-key
- Açıklama: V1 ve modern V2 istemci bakım akışı signed prekeyi 7 günde
  döndürüyor. Yeni key server ACK gelmeden pending kalıyor; belirsiz hata aynı
  private/public materyali yeniden deniyor. Eski keyler gecikmiş mesajlar için
  30 gün saklanıyor. Bot aynı state machine'i startup ve 6 saatlik bakımda
  çalıştırıyor.
- Somut senaryo: Uzun ömürlü signed prekey private key daha sonra ele geçirilirse, key'in gereğinden uzun yayımlanması eski bundle kayıtları üzerindeki saldırı penceresini büyütür.
- Doğrulama: İstemci exact-retry/retention testleri ile bot gerçek PostgreSQL
  entegrasyon testi 8 günlük rotasyon hatası, aynı pending key retry'ı ve 31
  günlük eski key temizliğini doğrular.
- Öneri: 7/30 günlük değerleri ve publish-before-prune sırasını koruyun;
  sunucu published key ID ayrışmasını operasyon alarmına bağlayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Service assertion replay tüketimi doğrulamadan önce/atomik olmadan yapılabiliyordu
- Severity: HIGH
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/ServiceAccounts.kt:66`; `signaling-server/src/main/kotlin/com/securechat/signaling/ServiceAssertionReplayStore.kt:10`, `:19`; `signaling-server/src/main/kotlin/com/securechat/signaling/ServiceAssertion.kt:96`
- Sınıf: replay, verification-order
- Açıklama: Assertion signature, scope ve provisioned subject doğrulandıktan sonra UUID `jti` Redis `SET NX EX` ile atomik tüketiliyor. Redis hatası fail-closed. Replay key'i ayrıca blind index ile saklanıyor.
- Somut senaryo: Aynı geçerli service assertion paralel iki istekte kullanılır veya sahte token önce nonce'u tüketerek geçerli isteği DoS eder.
- Doğrulama: Paralel integration testi yalnız bir tüketimin başarılı olduğunu; invalid signature/scope testleri jti'nin tüketilmediğini doğrular.
- Öneri: Bu doğrulama sırasını ve atomik Redis primitive'ini koruyun. Cluster topology'de tüm instance'ların aynı Redis namespaceini kullandığını deployment testinde doğrulayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Ed25519 doğrulayıcı artık imza sonuna eklenen baytları kabul etmiyor
- Severity: MEDIUM
- Konum: `bot-api/src/main/kotlin/com/securechat/botapi/auth/EdDsaJwtVerifier.kt:143`, `:159`; `signaling-server/src/main/kotlin/com/securechat/signaling/ServiceAssertion.kt:96`; `signaling-server/src/test/kotlin/com/securechat/signaling/WycheproofKatTest.kt`
- Sınıf: non-canonical-signature, parser-differential
- Açıklama: Wycheproof, kullanılan JDK sağlayıcısının geçerli 64 byte Ed25519 imzasına trailing zero eklendiğinde bir vakayı kabul ettiğini gösterdi. Her iki uygulama doğrulama öncesi imza uzunluğunu tam 64 byte olarak şart koşuyor.
- Somut senaryo: Aynı imzanın `sig || 0x00` biçimi bazı katmanlarda geçerli, bazılarında geçersiz sayılır; cache/replay/audit canonicalization farkları oluşur.
- Doğrulama: Wycheproof Ed25519 tcId 37 ve özel trailing-byte regresyonu düzeltmeden önce kabulü, düzeltmeden sonra reddi gösterdi.
- Öneri: Exact-length kontrolünü JCA çağrısından önce tutun; compact parserda alternatif Base64/canonical encodingleri de reddetmeye devam edin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Zayıf ve cross-purpose secret konfigürasyonları yeterince reddedilmiyordu
- Severity: HIGH
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/SecretPolicy.kt:7`, `:15`; `signaling-server/src/main/kotlin/com/securechat/signaling/PurposeSeparatedSecrets.kt:49`, `:54`, `:57`, `:68`; `bot-api/src/main/kotlin/com/securechat/botapi/BotApiConfig.kt:114`, `:117`, `:183`
- Sınıf: weak-key, key-reuse, configuration
- Açıklama: JWT/TURN/metrics/Janus sırları en az 32 UTF-8 byte, sekiz sembol çeşitliliği ve NUL yasağıyla; AEAD/HMAC key'leri tam 32 byte Base64 ve sekiz byte çeşitliliğiyle doğrulanıyor. Canonical comparison tüm değerler için olası 32-byte Base64 decode'u da karşılaştırarak aynı key materyalinin farklı metin biçiminde/amaçta tekrarını yakalıyor.
- Somut senaryo: Bir 32-byte AEAD key'in Base64 metni JWT secret olarak kopyalanır veya `AAAA...` gibi düşük çeşitlilikli key deploymenta girer; tek key sızıntısı birden çok primitive'i kırar.
- Doğrulama: Eşdeğer Base64 cross-purpose, tekrar-byte encryption key ve zayıf metrics/Janus/bot token testleri reddi doğruladı.
- Öneri: Bu kontroller yalnız düşük entropi için fail-closed tabandır; entropy ölçümü değildir. Deployment secretlarını CSPRNG ile üretin, secret manager/HSM'den yükleyin, key version ve rotation runbook ekleyin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Random GCM nonce için anahtar başına kullanım bütçesi yok
- Severity: LOW
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/ServerPrivacy.kt:149`, `:154`, `:178`; `bot-api/src/main/kotlin/com/securechat/botapi/delivery/BotQueuePrivacy.kt:58`, `:63`, `:79`; `bot-api/src/main/kotlin/com/securechat/botapi/signal/KeyEncryptor.kt:20`
- Sınıf: nonce-reuse, key-lifecycle
- Açıklama: Yeni envelope'lar key ID taşır ve nonce'u process başında üretilen
  64-bit CSPRNG prefix ile monoton 32-bit counterdan oluşturur. Aynı prefix
  altında `2^32` seal'den sonra işlem fail-closed durur. Eski envelope'lar
  yalnız decrypt/migration için okunur; FCM token kayıtları yeni sürüme tembel
  ve atomik olarak taşınır.
- Somut senaryo: Aynı AEAD key'iyle milyarlarca kayıt üretildiğinde iki nonce çakışır; GCM keystream ilişkisi ve authentication key hakkında bilgi sızabilir.
- Doğrulama: Queue, bot private-key ve FCM testleri key ID, legacy read,
  counter sınırı, paralel nonce benzersizliği ve migration yollarını kapsar.
- Öneri: Deployment secret rotasyonunda key ID'yi benzersiz tutun. Çok yüksek
  restart sayılı tehdit modelinde process-random prefix yerine DB/HSM tabanlı
  crash-safe global prefix allocator değerlendirin.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Bot identity/prekey private kayıtlarında AAD purpose/row bağı yok
- Severity: LOW
- Konum: `bot-api/src/main/kotlin/com/securechat/botapi/signal/KeyEncryptor.kt:20`; `bot-api/src/main/kotlin/com/securechat/botapi/signal/BotIdentityBootstrap.kt:119`; `bot-api/src/main/kotlin/com/securechat/botapi/signal/PgSignalProtocolStore.kt:155`, `:165`, `:231`, `:249`, `:262`
- Sınıf: missing-AAD, ciphertext-substitution
- Açıklama: V3 private-key envelope key ID ile birlikte
  `purpose || stable-row-id` AAD'sine bağlıdır. Identity, one-time prekey ve
  signed-prekey farklı purpose kullanır; farklı satıra taşıma tag doğrulamasını
  bozar. V2/legacy kayıtlar read-only uyumlulukla açılıp aynı DB işlemi içinde
  V3'e yazılır.
- Somut senaryo: DB yazma yetkili saldırgan bir prekey private ciphertextini başka prekey ID'sine veya identity alanına kopyalar. AEAD tag geçer; public/private mismatch servis arızası veya yanlış key material yüklenmesi üretir.
- Doğrulama: Cross-purpose, cross-row, key-ID ve legacy lazy-migration unit ve
  PostgreSQL entegrasyon testleri geçer.
- Öneri: Legacy okuma sayacı sıfıra ulaşıp tüm production kayıtları V3
  olduğunda boş-AAD decrypt yolunu ayrı migration ile kaldırın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] TURN credential stable pseudonym taşıyordu
- Severity: MEDIUM
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/TurnCredentialService.kt:63`, `:136`, `:170`
- Sınıf: linkability, protocol-specific-HMAC
- Açıklama: TURN username içindeki istemci etiketi stable blind index yerine credential başına 16 random byte opaque tag oldu. Secret refresh monotonic zaman, beş dakika stale grace ve fail-closed davranışla sınırlandı. Production yalnız `turns:` kabul ediyor. HMAC-SHA1 coturn REST wire uyumluluğu için kasıtlıdır, genel amaçlı imza değildir.
- Somut senaryo: Stable etiket farklı TURN allocationlarını aynı kullanıcıya bağlardı; relay gözlemcisi zaman içinde kullanıcı hareketini izleyebilirdi.
- Doğrulama: Ardışık credentialların farklı tag ürettiği test edildi. RFC 2202 HMAC-SHA1 KAT sonucu `thcxhlUFcmTii8C2+zeMjvFGvgA=` ile doğrulandı.
- Öneri: Random etiketi koruyun; coturn log retentionını sınırlandırın. Protocol değişirse SHA1'i yeni genel amaç için yeniden kullanmayın.
- Güven: CONFIRMED

### [DÜZELTİLDİ] SecretSource kontrol ve okuması arasında TOCTOU penceresi var
- Severity: LOW
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/SecretSource.kt:56`, `:59`, `:66`, `:67`; `bot-api/src/main/kotlin/com/securechat/botapi/SecretSource.kt:48`, `:51`, `:58`, `:59`
- Sınıf: TOCTOU, secret-file
- Açıklama: Secret dosyası `NOFOLLOW_LINKS` ile tek channel/descriptor üzerinden
  açılır; pre-open ve açılmış descriptor attribute'ları karşılaştırılır, okuma
  aynı descriptor üzerinden ve boyut sınırıyla yapılır. Parent dizinin owner
  dışı yazılabilir olması, symlink ve inode/file-key değişimi reddedilir.
- Somut senaryo: Secret dizinine rename yetkisi olan yerel saldırgan permission/symlink kontrolünden sonra dosyayı başka inode ile değiştirir ve servise kendi secretını yükletir.
- Doğrulama: Signaling ve bot testleri symlink, world/group permission,
  yazılabilir parent, oversized file ve check/open yarışındaki dosya değişimini
  reddeder.
- Öneri: Production secret mountunu immutable/read-only tutmaya devam edin;
  descriptor kontrolleri yanlış mount politikasının yerine geçmez.
- Güven: CONFIRMED

### [DÜZELTİLDİ] Backup KDF çevrimdışı parola tahminine karşı zayıf kalıyor
- Severity: MEDIUM
- Konum: `../lib/src/backup/backup_crypto.dart:15`, `:21`; `../lib/src/backup/backup_service.dart:234`, `:46`, `:102`
- Sınıf: weak-KDF, offline-bruteforce
- Açıklama: Yeni ELBK V4 backup anahtarı Argon2id ile 19 MiB memory, 2
  iteration ve parallelism 1 parametrelerinden türetilir. Salt ve KDF
  parametreleri authenticated header/AAD içindedir. V2/V3 PBKDF2 yalnız eski
  yedeği açıp V4'e taşıma uyumluluğu için okunur; yeni PBKDF2 yedek üretilmez.
- Somut senaryo: Saldırgan backup blobunu kopyalar ve GPU/ASIC üzerinde düşük entropili sekiz karakterli parolaları offline dener; uygulamanın deneme sayacı devreye girmez.
- Doğrulama: V4 round-trip, yanlış parola, header/KDF parametre tamper, legacy
  V2/V3 decrypt-only ve private Signal state dışlama testleri geçer.
- Öneri: 19 MiB tabanını düşürmeyin; cihaz sınıfı yükseldikçe benchmark ile
  memory/time maliyetini artırın ve kullanıcıya yüksek entropili recovery key
  seçeneği ekleyin.
- Güven: CONFIRMED

### [DOĞRULANDI] AES-GCM/HMAC parametreleri ve ana AAD sınırları doğru
- Severity: INFO
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/ServerPrivacy.kt:149`, `:154`, `:156`, `:178`, `:180`; `bot-api/src/main/kotlin/com/securechat/botapi/delivery/BotQueuePrivacy.kt:58`, `:63`, `:65`, `:79`, `:81`
- Sınıf: primitive-validation
- Açıklama: Queue ve bot private envelope'ları AES-256-GCM, 12-byte
  prefix+counter nonce ve 128-bit tag kullanıyor. Queue ciphertext
  recipient/purpose AAD'sine, bot private kayıtları purpose/row AAD'sine
  bağlıdır; blind index HMAC-SHA256 ve namespace ayıracı NUL ile ayrılmıştır.
- Somut senaryo: Ciphertext başka recipient/purpose'a taşındığında AAD değişir ve GCM authentication başarısız olur; ciphertext/tag truncation da reddedilir.
- Doğrulama: Tamper/cross-recipient/cross-purpose testleri ile 66 Wycheproof AES-GCM ve 174 HMAC-SHA256 vakası geçti. Anahtar tekrar/bütçe ve bot boş-AAD istisnaları ayrı bulgulardır.
- Öneri: Envelope version/purpose doğrulamasını ve 128-bit tag'i koruyun; yeni consumer eklerken zorunlu AAD API kullanın.
- Güven: CONFIRMED

### [DOĞRULANDI] Raw RSA/NoPadding özel grup operasyonunda padding oracle oluşturmuyor
- Severity: INFO
- Konum: `signaling-server/src/main/kotlin/com/securechat/signaling/PrivateDirectoryOprf.kt:178`, `:180`, `:186`, `:200`; `../lib/src/contacts/private_contact_discovery.dart:158`, `:198`, `:229`
- Sınıf: raw-rsa, group-validation
- Açıklama: `RSA/ECB/NoPadding` burada plaintext encryption/decryption değil, sabit genişlikli RSA grup exponentiation primitive'i olarak kullanılıyor. Girdi tam modulus genişliğinde, `1 < x < N` ve `gcd(x,N)=1`; çıktı sabit genişliktedir. PKCS#1 padding parse/status oracle olmadığı için Bleichenbacher sınıfı encryption oracle bulunmadı.
- Somut senaryo: Kötücül istemci 0, 1, N, yanlış genişlik veya non-unit gönderir; private operation çağrılmadan reddedilir.
- Doğrulama: Boundary/rogue-input testleri, çapraz dil KAT ve grup eşitliği geçti. Full-domain expansion modulus genişliğinden en az 128 bit fazla materyali reduction öncesi üretir; kalan modulo bias ihmal edilebilir düzeydedir.
- Öneri: Bu değerlendirme yalnız primitive kullanımına aittir; tek-operatör obliviousness ve verifiability bulgularını çözmez. Özel tasarımı standart ve proof üreten OPRF ile değiştirin.
- Güven: CONFIRMED

### [DOĞRULANDI] Ed25519/JWT doğrulama sırası ve replay bağları test edildi
- Severity: INFO
- Konum: `bot-api/src/main/kotlin/com/securechat/botapi/auth/EdDsaJwtVerifier.kt:143`, `:159`, `:168`; `signaling-server/src/main/kotlin/com/securechat/signaling/ServiceAssertion.kt:96`, `:126`, `:137`
- Sınıf: signature-validation, jwt
- Açıklama: Bot JWT yolu alg/kid/imza doğrulamasından sonra aud ve zaman penceresini, sonra raw body hash'i, en son atomik jti replay tüketimini kontrol ediyor. Service assertion compact formatı exact signature, subject/scope, `exp > iat` ve kısa lifetime şartlarını uyguluyor.
- Somut senaryo: Geçersiz body hash taşıyan signed JWT, nonce'u tüketip sonraki geçerli isteği engellemeye çalışır; verification-order nedeniyle replay store'a ulaşamaz.
- Doğrulama: Bh-before-nonce, alg confusion, wrong kid/aud, skew/expiry, compact parser, trailing signature ve 151 Wycheproof Ed25519 vakası geçti.
- Öneri: Verification order testini davranış sözleşmesi olarak koruyun; yeni claim kontrollerini imza doğrulamasından önce yan etkili hale getirmeyin.
- Güven: CONFIRMED

### [DOĞRULANDI] Kripto RNG yollarında tahmin edilebilir PRNG bulunmadı
- Severity: INFO
- Konum: `signaling-server/src/main`, `bot-api/src/main`, `../lib/src`
- Sınıf: insecure-rng
- Açıklama: Kotlin kripto yolları `java.security.SecureRandom`, Flutter kripto yolları `Random.secure()` kullanıyor. `Math.random` veya seed'lenebilir `Random()` kripto anahtar/nonce/token üretiminde bulunmadı.
- Somut senaryo: Tahmin edilebilir seed ile nonce, OTP veya key üretimi aranmıştır; incelenen üretim yollarında böyle bir kaynak yoktur.
- Doğrulama: Kaynak taraması ve çağrı noktası incelemesi yapıldı; OPRF random sampler adversarial deterministic RNG testiyle ayrıca sınandı.
- Öneri: Test fixture RNG'lerini production dependency injection'a taşımayın; static RNG taramasını CI'da tutun.
- Güven: CONFIRMED

## Uygulanan test ve CI kapıları

| Kapı | Sonuç |
|---|---|
| `./gradlew test check --offline --no-daemon` | PASS; signaling 1.179 + bot 190 = 1.369 test, 0 failure/error; iki coverage gate PASS |
| `flutter test --no-pub` | PASS; 438 test |
| `flutter analyze --no-pub` | PASS |
| `sha256sum -c tools/crypto-audit/SHA256SUMS` | PASS; 5/5 pinli artifact |
| OPRF çapraz dil KAT | PASS; Kotlin ve Dart aynı sonuç |
| Wycheproof KAT | PASS; toplam 561 vaka |
| `tools/crypto-audit/run_cognicrypt_advisory.sh` | Tamamlandı; 76 advisory elle sınıflandırıldı |

CI için `.github/workflows/server-crypto.yml` eklendi. Workflow hash kontrolünü
`flutter_securechat/server_hardened/tools/crypto-audit` çalışma dizininde yapar,
ardından temiz runner üzerinde Gradle `test check` çalıştırır. Yerel airgapped
doğrulama yukarıdaki `--offline` komutuyla ayrıca geçmiştir. Pinli test
vektörlerini değiştiren her
PR, `SHA256SUMS` güncellemesini ve review gerekçesini birlikte taşımalıdır.

## Öncelikli sonraki adımlar

1. Telefon identity binding modelini seçin ve directory token claim'ini bu
   kanıta bağlayın. Bu olmadan directory sonucu doğru hesaba ait değildir.
2. Tek-operatör OPRF'yi threshold/TEE tabanlı standart protokolle değiştirin;
   key transparency, epoch ve migration tasarımını bağımsız kriptografa
   inceletin.
3. Uygulanan sealed sender + anonim mailbox katmanının önüne ayrı
   operator/bolgede oblivious ingress ekleyin; ilk capability bootstrap'ini
   private discovery ile birleştirin.
4. Safety-number onayı ve key transparency ile ilk Signal temasını doğrulayın.
5. Snapshot temporal differencing bulgusunu epoch-randomized ve bağımsız
   incelenmiş bir snapshot tasarımıyla kapatın.
