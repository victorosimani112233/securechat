# SecureChat Sunucu İnceleme Raporu

**İnceleme tarihi:** 18 Ağustos 2026
**Kapsam:** kök `signaling-server` / `bot-api`, üretim adayı
`flutter_securechat/server_hardened`, migration'lar, Redis/PostgreSQL veri
sınırları, WebSocket/HTTP protokolü, private directory, FCM/APNs, TURN/Janus,
bot API ve deployment zinciri.
**Değişiklik politikası:** Bu inceleme sırasında sunucu davranışına veya sunucu
kaynak koduna dokunulmadı. Yalnız bu rapor eklendi. Testlerin ürettiği geçici
`build/` çıktıları kaynak değişikliği değildir.

## 1. Yönetici özeti

**Karar: mevcut haliyle production release HOLD.**

`server_hardened` veri minimizasyonu açısından kökteki sunucudan belirgin biçimde
ileri: mesaj geçmişi ve grup grafiği PostgreSQL'e yazılmıyor, offline kuyruk
server-side AEAD ile kısa süreli tutuluyor, push tokenları opaque index + AEAD
ile korunuyor, legacy plaintext kontrol mesajları reddediliyor, migration'lar
ham telefon/e-posta/grup/audit ilişkilerini kaldırıyor ve retention bozulduğunda
trafik fail-closed kapanıyor. Bunlar korunması gereken doğru kararlar.

Buna rağmen yayın öncesi kapanması gereken kritik sınırlar var:

1. Canlı uçtaki route seti hardened kaynakla uyuşmuyor; private directory ve
   sürüm uçları 404 dönüyor. Hangi image/commit'in canlı olduğu kanıtlanamıyor.
2. Telefon kimliği e-posta OTP'sine bağlı değil. Herhangi bir e-postayı
   doğrulayan ilk kişi, henüz kayıtlı olmayan herhangi bir telefon hash'ini
   sahiplenebilir; bu rehber tabanlı kimlik taklidine dönüşebilir.
3. Refresh-token iptali, silinen kullanıcı işareti, registration-token tüketimi
   ve bot emergency stop yalnız RAM-only Redis'te. Redis restart'ı veya
   `allkeys-lru` eviction, iptal edilmiş uzun ömürlü kimlik bilgilerini yeniden
   geçerli hale getirebilir.
4. Janus SFU yolunda uygulama-katmanı medya E2EE'si (SFrame/frame cryptor)
   bulunmadı. DTLS-SRTP Janus'ta sonlandığı için SFU process'i medya gizliliği
   sınırının içindedir. Ayrıca client-facing Janus için uygulanmış katılımcı
   yetkilendirmesi yok.
5. Bot, normal kullanıcı JWT'lerini imzalayan aynı HS256 secret'ı taşıyor ve
   istediği UUID adına access token üretebiliyor. Bot ihlali tüm kullanıcıların
   taklit edilebilmesi anlamına gelir.
6. Fresh V14 şemasında `phone_hash` kolonu yokken bot bootstrap hâlâ bu kolona
   INSERT yapıyor; temiz production kurulumu bot tarafında başlamaz.
7. Hardened Compose yalnız `internal: true` ağa bağlı; buna karşılık signaling
   dış PostgreSQL, SMTP, Firebase ve Janus'a erişmek zorunda. Verilen topology
   bu bağımlılıklarla çalışabilir bir egress yolu göstermiyor.
8. Bot public/admin listener'ları Unix socket kullandığını iddia ediyor ama
   gerçekte container içi `127.0.0.1` TCP'ye bind oluyor; Compose port veya
   socket sidecar/mount sağlamıyor. Bot API dışarıdan kullanılamaz.
9. Bot grup allow-list'i yalnız `group:<token>` değerini doğruluyor; request'in
   verdiği `recipientUserIds` üyelik veya kişi allow-list'i ile doğrulanmıyor.
10. Hesap silme DB commit'inden sonra yapılan Redis/cache/token/socket
    temizliğinde hata alırsa hesap DB'den silinmişken credential/socket kalabilir
    ve istemci 500 alır.

Bu raporda **P0**, production'a çıkışı durduran; **P1**, P0'lardan hemen sonra
kapatılması gereken yüksek risk; **P2**, hardening/bakım borcu anlamındadır.

## 2. İncelenen hedefler ve canlı durum

| Hedef | Kaynak durumu | Migration | Sonuç |
|---|---:|---:|---|
| Kök `signaling-server` | 21 Kotlin dosyası | V1-V3 | Referans/legacy; production gizlilik garantisi yok |
| Kök `bot-api` | 32 Kotlin dosyası | signaling V1-V3'e bağlı | Referans/legacy |
| `server_hardened/signaling-server` | 30 Kotlin dosyası | V1-V14 | İncelenen production adayı |
| `server_hardened/bot-api` | 41 Kotlin dosyası | signaling V1-V14'e bağlı | İncelenen production adayı |

Hardened README açıkça kök sunucuların production artefaktı olmadığını söylüyor:
`server_hardened/README.md:3-6`. Buna rağmen iki ayrı kaynak ağacının aynı repoda
bulunması yanlış artefaktı build/deploy etme riskini yükseltiyor.

### 2.1 Canlı anonim sözleşme kontrolü

18 Ağustos 2026'da bağlı telefonun HTTPS tüneli üzerinden, token veya kullanıcı
verisi göndermeden yapılan kontrolde:

| İstek | Sonuç |
|---|---:|
| `GET /health` | 200, `{"status":"ok"}` |
| `GET /api/v1/latest-version` | 404 |
| `GET /api/v1/directory/config` | 404 |

Hardened kaynakta bu iki API sırasıyla `HttpRoutes.kt:210` ve
`HttpRoutes.kt:226` içinde mevcut. Dolayısıyla canlı route seti bu kaynakla
uyuşmuyor. Bu gözlem yalnız route uyumsuzluğunu kanıtlar; canlı image'ın tam
hangi commit olduğunu tek başına kanıtlamaz.

`/health` sonucu da backend readiness kanıtı sayılmamalı: legacy Nginx dosyası
bu yolu upstream'e gitmeden sabit 200 döndürüyor (`infra/nginx/securechat.conf:
43-47`). Gerçek readiness için proxy'nin backend health sonucunu iletmesi ve
response'a doğrulanabilir build kimliği eklenmesi gerekir.

## 3. Korunması gereken güçlü kontroller

| Alan | Mevcut doğru davranış | Kanıt |
|---|---|---|
| Startup fail-closed | Production policy, privacy keyleri, OPRF, SMTP, DB ve Redis listener'dan önce doğrulanıyor | `Application.kt:33-84` |
| WebSocket sınırı | 256 KiB frame ve UTF-8 byte kontrolü var | `Application.kt:101-108`, `WebSocketRoutes.kt:111-120` |
| Kimlik taklidi önleme | JWT `sub`, claimed user ile eşleştiriliyor; sender/timestamp server tarafından override ediliyor | `WebSocketRoutes.kt:78-97`, `277-305` |
| Plaintext fallback reddi | Legacy chat-control, grup notification ve linkable group fanout route edilmiyor | `WebSocketRoutes.kt:332-340`, `585-627` |
| Offline kuyruk | Recipient'e AAD bağlı AES-256-GCM, opaque HMAC key, kısa TTL ve per-user cap var | `ServerPrivacy.kt:130-187`, `ConnectionManager.kt:418-499` |
| Redis disk gizliliği | AOF ve RDB kapalı değilse startup reddediliyor | `RedisEphemeralPolicy.kt:11-21` |
| Private directory | Sabit 256'lık blind-RSA batch, production PKCS#11 zorunluluğu ve sealed snapshot var | `PrivateDirectoryOprf.kt:79-117`, `ProductionDeploymentPolicy.kt:15-18` |
| Kalıcı metadata azaltma | E-posta, encrypted phone, group graph, audit timeline, prekey timing ve raw push/session UUID kolonları kaldırılıyor | V4, V6, V8-V14 migration'ları |
| Push gizliliği | Push token opaque index + AAD bağlı v4 AEAD; payload yalnız generic wake | `FcmTokenStore.kt:11-18`, `FcmPushSender.kt:119-129` |
| Retention | Startup cleanup zorunlu; runtime cleanup hatasında privacy health kapanıyor ve socket'ler kapatılıyor | `PrivacyRetentionWorker.kt:17-84` |
| Secret/deploy hardening | Purpose separation, secret-file sınırı, digest pin, non-root, read-only FS, cap-drop, core/heap dump kapalı | `PurposeSeparatedSecrets.kt`, `deploy_privacy_stack.sh`, Dockerfile'lar |
| Migration güvenliği | V14, legacy raw ilişki kalmışsa sessiz veri silmek yerine migration'ı durduruyor | `V14__drop_legacy_identity_links.sql:8-44` |

Bu kontroller düzeltmeler sırasında gevşetilmemeli. Özellikle “legacy uyumluluk”
gerekçesiyle plaintext queue, plaintext grup kontrolü, ham telefon discovery
veya kalıcı grup grafiği geri getirilmemeli.

## 4. P0 — production release bloklayıcıları

### P0-01 — Canlı artefakt kaynağı ve route seti doğrulanamıyor

**Kanıt**

- Hardened target kendisini tek production hedefi olarak tanımlıyor
  (`server_hardened/README.md:3-6`).
- Kök hedef yalnız V1-V3, hardened hedef V1-V14 migration taşıyor.
- Canlıda hardened `/api/v1/directory/config` ve her iki yerel kaynakta bulunan
  `/api/v1/latest-version` 404 dönüyor.
- Mevcut Codemagic YAML'larında hardened server test/build/deploy kapısı
  referansı bulunmadı.

**Etki**

Mobil istemci private directory için doğru biçimde fail-closed kalır ve rehber
çalışmaz. Daha önemlisi, incelenen güvenlik garantilerinin canlıda var olduğu
söylenemez; yanlış Docker context/compose/image seçimi bütün privacy tasarımını
geçersiz kılabilir.

**Gerekli çözüm**

1. Tek canonical production server dizini ve tek CI pipeline belirle.
2. Image'a commit SHA, migration target, protocol version ve dependency lock
   digest'i içeren build manifest göm; secretsiz `/version` veya operator-only
   attestation endpoint'i sun.
3. Image'ı imzala; registry digest + commit + SBOM bağını release kaydında tut.
4. Root `infra/docker-compose.yml` ve root server için production CI/deploy'i
   teknik olarak reddet.

**Kabul testi:** temiz hostta yalnız signed hardened digest deploy edilir;
backend health, version, latest-version ve directory-config sözleşme testleri
geçer; çalışan container digest'i release manifest ile birebir eşleşir.

### P0-02 — Telefon kimliği sahipliği kanıtlanmıyor: first-claim impersonation

**Kanıt**

- E-posta OTP başarıyla yalnız generic `registration-grant` JWT üretir;
  telefon, directory token, user ID veya device public key bu grant'e bağlı
  değildir (`AuthService.kt:93-105`).
- `/users/register`, bu generic token ile request'in verdiği `userId` ve
  `phoneHash` değerini kaydeder (`HttpRoutes.kt:395-424`).
- Kayıtlı bir identity'nin ele geçirilmesi doğru biçimde reddediliyor
  (`HttpRoutes.kt:425-431`), fakat henüz kayıtlı olmayan numarada ilk talep eden
  kazanıyor.

**Etki**

Saldırgan herhangi bir e-posta hesabını doğrulayıp hedef telefonun normalize
hash'ini önceden kaydederse, hedef kişinin rehberindeki kullanıcılar saldırganın
UUID/prekey kimliğini keşfedebilir. Bu yalnız hesap açma suistimali değil,
rehber tabanlı E2EE kimliğinin yanlış kişiye bağlanmasıdır.

**Gerekli çözüm**

- Registration grant, gerçek telefon sahipliği kanıtına ve ayrıca `userId +
  device identity key + directory token/keyId` bağlamına kriptografik olarak
  bağlanmalı.
- Raw telefonun kalıcı tutulmaması ilkesi korunmalı. SMS/voice sağlayıcısı
  kullanılırsa sağlayıcının gördüğü metadata ve retention açıkça tehdit modeline
  eklenmeli; alternatif yüksek entropili QR/invite sahiplik modeli ürün kararı
  olarak netleştirilmeli.
- Claim işlemi DB transaction'ı içinde tek-kullanımlık, amaç/kimlik bağlı ve
  paralel replay'e kapalı olmalı.

**Kabul testi:** başka bir e-postayı doğrulayan saldırgan hedef numarayı claim
edemez; aynı grant farklı user ID, key veya phone identity için kullanılamaz;
concurrent claim testinde yalnız gerçek sahip başarılı olur.

### P0-03 — RAM-only Redis auth state'i restart/eviction sonrası güvenliği geri açıyor

**Kanıt**

- Refresh token TTL'si 60 gün (`AuthService.kt:36-41`).
- Token blacklist, deleted-user marker ve registration-token use marker yalnız
  Redis'te (`AuthService.kt:108-135`, `155-165`, `206-229`).
- Redis bilinçli biçimde persistence'sız ve `allkeys-lru` ile başlıyor
  (`deploy/compose.privacy.yml:27-36`).
- Bot emergency stop da TTL'siz tek Redis key'i (`EmergencyStopFlag.kt:11-19`).

**Etki**

Redis restart'ında veya bellek baskısında auth kayıtları kaybolabilir:

- logout/revoke edilmiş refresh token tekrar kullanılabilir;
- silinmiş kullanıcının token'ı, auth DB varlığını kontrol etmediği için tekrar
  refresh edilip yeni token üretebilir;
- henüz expire olmamış kullanılmış registration grant yeniden oynatılabilir;
- bot emergency stop kendiliğinden kalkabilir;
- `allkeys-lru`, servis restart'ı olmadan da bu sonuçları seçici üretebilir.

Redis bağlantı hatasında fail-closed davranmak, mevcut olmayan/evict edilmiş key'i
“iptal edilmemiş” sayma problemini çözmez.

**Gerekli çözüm**

1. Mesaj kuyruğu/rate limit gibi kaybı kabul edilebilir state ile auth safety
   state'ini ayrı Redis instance/policy'lere ayır.
2. Auth Redis'inde `noeviction` kullan; OOM'u uygulamada fail-closed ele al.
3. Refresh tokenları plaintext saklamadan, hash + token-family + rotation counter
   olarak durable ve transaction-safe tut. Reuse detection ekle.
4. Kullanıcı credential epoch/state'ini PostgreSQL'de tut; silinmiş kullanıcı
   veya eski epoch için access/refresh doğrulamasını reddet.
5. Emergency stop'u imzalı/durable operator state'i yap; Redis yalnız cache olsun.

**Kabul testi:** Redis flush/restart, maxmemory eviction ve failover chaos
testlerinden sonra revoked token, deleted user, consumed grant ve emergency stop
asla yeniden geçerli hale gelmez.

### P0-04 — Hesap silme atomik değil; DB silinmişken credential/socket kalabilir

**Kanıt**

- PostgreSQL silme transaction'ı `HttpRoutes.kt:471-507` arasında commit olur.
- FCM memory/store, registry, user revocation ve socket/queue temizliği ancak
  commit'ten sonra sırayla yapılır (`HttpRoutes.kt:508-516`).
- Bu adımlardan biri exception atarsa kalanlar çalışmaz ve genel catch 500 döner
  (`HttpRoutes.kt:517-520`).

**Etki**

Örneğin post-commit `fcmTokenStore.removeToken` hata verirse deleted-user marker,
socket ve Redis kuyruk temizliği yapılmayabilir. DB'de hesap yokken istemci
“silme başarısız” görür; eski token/socket bir süre yaşamaya devam edebilir.
P0-03 ile birleştiğinde Redis restart'ı bu kullanıcıyı tekrar authenticate
edebilir.

**Gerekli çözüm**

- Silme isteğini idempotent durable tombstone/saga yap.
- Yeni trafik için credential epoch'u iptal et ve socket'i kapat; ardından DB,
  push, bot session ve queue temizliğini outbox/worker ile retry et.
- Her adım tekrar çalıştırılabilir olmalı; “already deleted” başarı sayılmalı.
- Silme tamamlanmadan privacy health/authorization bu identity için fail-closed
  kalmalı.

**Kabul testi:** her cleanup adımından önce/sonra fault injection ve process
restart yapılır; kullanıcı tekrar authenticate olamaz, tüm kopyalar sonunda
silinir ve tekrar DELETE deterministik başarı döner.

### P0-05 — Janus SFU, çağrı içeriği için gerçek E2EE sınırı değil

**Kanıt**

- Grup katılımcı eşiği aşılınca Janus VideoRoom yaratılıyor
  (`WebSocketRoutes.kt:385-403`, `JanusOrchestrator.kt:208-247`).
- Kotlin ve Flutter medya kaynaklarında SFrame, WebRTC FrameCryptor, insertable
  stream veya eşdeğer uygulama-katmanı medya E2EE implementasyonu bulunmadı.
- Client-facing Janus authentication için kod yalnız “anonymous kabul etmeli
  veya token plugin'i kullanılmalı” diyor; uygulanmış capability yok
  (`JanusOrchestrator.kt:291-307`).
- Room ID, 31-bit `groupId.hashCode()` ile türetiliyor ve collision kontrolü yok
  (`JanusOrchestrator.kt:218`).

**Etki**

P2P/ TURN yolunda DTLS-SRTP iki uç arasında kalır ve TURN ciphertext relay eder.
SFU yolunda ise WebRTC oturumu Janus'ta sonlanır; ayrı medya-E2EE yoksa Janus
host/process'i ses ve görüntü güven sınırına girer. Public Janus URL'sine erişen
yetkisiz taraf için participant-bound join credential da kanıtlanmamıştır.

**Gerekli çözüm**

- Tercih edilen: Signal ile dağıtılan per-call/per-participant keylerle SFrame
  veya desteklenen native FrameCryptor medya E2EE'si; join/leave sırasında key
  rotation ve eski üye dışlama testi.
- Bu hazır olana kadar SFU'yu production'da kapat ve yalnız P2P/mesh sınırını
  açıkça destekle; performans sınırını UI'da dürüstçe göster.
- Janus/proxy için kısa ömürlü, callId/room/participant/device bağlı tek-kullanımlık
  capability; anonymous join yok.
- Random 64-bit/Janus-generated room ID + collision check; admin/API secret client'a
  asla verilmemeye devam edilmeli.

**Kabul testi:** Janus host packet/process incelemesi plaintext media çıkaramaz;
non-participant ve eski participant join/decrypt edemez; collision ve credential
replay testleri geçer.

### P0-06 — Bot, bütün kullanıcıları taklit edebilen shared JWT signing secret taşıyor

**Kanıt**

- Bot config, signaling ile aynı `JWT_SECRET`'ı yükler
  (`BotApiConfig.kt:29-37`, `70-73`).
- `BotJwtMinter.issueAccessToken(userId)` çağrısı verilen herhangi bir subject
  adına geçerli normal access token üretir (`BotJwtMinter.kt:18-36`).
- Signaling, token subject'in DB'de kayıtlı olduğunu ayrıca doğrulamaz.

**Etki**

Bot container/secret ihlali yalnız bot mesajlarına değil, herhangi bir kullanıcı
UUID'si adına WebSocket açma, gerçek socket'i düşürme, prekey değiştirme ve mesaj
route etme yetkisine dönüşür. Bu blast radius, bot'u tüm kullanıcı auth kökü yapar.

**Gerekli çözüm**

- Bot'tan user-token signing secret'ını tamamen kaldır.
- Signaling'in ayrı public key ile doğruladığı service identity veya mTLS + token
  exchange kullan. Token scope yalnız sabit bot subject, gerekli endpoint'ler ve
  kısa TTL olmalı; başka `sub` seçilememeli.
- Prekey upload ve WS route service account type/scope kontrolü yapmalı.

**Kabul testi:** bot'ın tüm secret'ları ele geçirilmiş varsayımında victim UUID
adına access/refresh token üretmek veya victim WS açmak mümkün değildir.

### P0-07 — Fresh V14 bot bootstrap şemayla uyumsuz ve yarım-state kalabiliyor

**Kanıt**

- V13 `users.phone_hash` kolonunu `directory_token` olarak yeniden adlandırıyor
  (`V13__private_contact_directory.sql:7-8`).
- Bot first-run hâlâ `INSERT INTO users(user_id, phone_hash, ...)` çalıştırıyor
  (`BotIdentityBootstrap.kt:84-97`).
- Identity row commit edildikten sonra prekey persist/upload ayrı adımlarda
  yapılıyor (`BotIdentityBootstrap.kt:100-142`). Sonraki açılış yalnız
  `bot_identity` varlığına bakıp bootstrap'ı atlıyor (`:47-69`).

**Etki**

Temiz V1-V14 deployment'ta bot bootstrap SQL hatasıyla durur. Daha eski şemada
identity commit'i sonrası prekey/upload hatası olursa kalıcı yarım-state oluşur;
restart bunu “zaten kayıtlı” sayar ve onarmaz.

**Gerekli çözüm**

- Bot/service identity için final şemayla uyumlu, rehber snapshot'ına girmeyen
  açık bir account type/provisioning modeli tasarla.
- Bootstrap'ı durum makineli ve reconcile edilebilir yap: identity, local prekeys,
  signaling upload ve readiness ayrı doğrulansın; yarım adım restart'ta tamamlansın.
- DB kısmı tek transaction; remote upload başarısızsa hazır kabul edilmesin.

**Kabul testi:** boş DB'ye V1-V14 + `ensureRegistered()` iki kez; her aşamada
fault injection/restart; sonunda tek bot identity, doğru prekey bundle ve çalışan
WS elde edilir.

### P0-08 — Hardened Compose bağımlılıklarına ağ yolu göstermiyor

**Kanıt**

- Bütün servisler yalnız `securechat-internal` ağına bağlı
  (`deploy/compose.privacy.yml:3-17`).
- Ağ `internal: true` (`:132-134`).
- PostgreSQL Compose içinde değil; signaling ayrıca SMTP, Firebase ve external
  Janus URL'lerine ihtiyaç duyuyor (`:52-80`). Janus servisi de bu Compose'ta yok.

**Etki**

Dokümante edilen stack, ayrı managed PostgreSQL'e ve internet/özel ağdaki
SMTP-FCM-Janus'a erişemez. Config doğru olsa bile startup veya OTP/push/call
çalışmaz. Operatörün sonradan elle ikinci ağ eklemesi audit edilen topology'yi
geçersiz kılar.

**Gerekli çözüm**

- Redis/signaling/bot için iç ağ ile kontrollü egress'i ayır.
- PostgreSQL/SMTP/Firebase/Janus için açık allow-list'li egress proxy/firewall veya
  ayrı purpose network tanımla; inbound erişimi genişletme.
- DNS, TLS verify-full, certificate rotation ve outage davranışını Compose/runbook
  içinde test et.

**Kabul testi:** sıfır manuel network değişikliğiyle gerçek benzeri environment'ta
DB migration, SMTP OTP, FCM/APNs wake ve Janus control bağlantısı geçer; başka
egress hedefleri reddedilir.

### P0-09 — Bot public/admin API deployment'ta ulaşılamıyor

**Kanıt**

- Public ve admin listener gerçekte sırasıyla container içi
  `127.0.0.1:8091/8092` dinliyor; Unix socket “Task 13” olarak bırakılmış
  (`PublicListener.kt:15-40`, `AdminListener.kt:19-54`).
- Hardened Compose bot için yalnız health port config'i veriyor; public/admin
  port mapping, sidecar veya host socket bind mount yok
  (`deploy/compose.privacy.yml:97-130`).

**Etki**

Bot public send ve admin CLI yolları aynı container dışından erişilemez. Bu bir
hardening tercihi değil, deployment işlev boşluğudur.

**Gerekli çözüm**

- Gerçek Unix domain socket'i doğrudan Netty native transport ile uygula veya
  ayrı, minimal ve hardened proxy sidecar kullan.
- Socket tmpfs/bind mount, UID/GID/mode, peer credential, public/admin ayrımı ve
  host erişim modeli Compose'ta açık olsun.
- Admin token'a ek olarak local peer/OS authorization uygula.

**Kabul testi:** hosttaki yetkili CLI socket üzerinden çalışır; yetkisiz UID,
network peer ve public socket'ten admin route erişimi reddedilir.

### P0-10 — Bot grup allow-list'i gerçek alıcıları yetkilendirmiyor

**Kanıt**

- Allow-list yalnız request'in `recipientRef` değerini karşılaştırıyor
  (`AllowListChecker.kt:9-19`).
- Grup request'indeki en çok 256 UUID biçimsel olarak doğrulanıyor fakat group
  membership veya kişi allow-list'i kontrol edilmiyor
  (`SendPipeline.kt:100-118`, `216-240`).
- Tüm üyelere aynı outer `messageId` ve clear `messageType` gidiyor
  (`SendPipeline.kt:230-283`).

**Etki**

Bir API client yalnız izinli bir `group:<opaque-token>` bilerek request'e istediği
UUID'leri koyabilir; bot bu kişilere mesaj yollar. Aynı outer ID grup fanout'unu
signaling katmanında doğrudan linkler ve clear message type içerik kategorisini
açığa çıkarır.

**Gerekli çözüm**

- Server'da kalıcı grup grafiği oluşturmadan device-signed, kısa ömürlü group
  send capability kullan; capability group token, bot client, recipient set
  commitment, epoch ve expiry'ye bağlı olsun.
- Alternatif geçici sınır: her recipient ayrıca `user:<uuid>` allow-list'inde
  bulunmadan group send reddedilsin.
- Canonical message ID/type inner E2EE payload'a taşınsın; her recipient için
  bağımsız random outer ID kullanılsın.

**Kabul testi:** allowed group token + yetkisiz UUID kombinasyonu fail-closed;
membership epoch/replay/removed member testleri geçer; outer frame'ler ortak
group/message discriminator taşımaz.

### P0-11 — Bot Signal identity doğrulaması her anahtarı güvenilir sayıyor

**Kanıt**

- `saveIdentity` kalıcı peer identity yazmıyor, `getIdentity` null ve
  `isTrustedIdentity` koşulsuz true dönüyor
  (`PgSignalProtocolStore.kt:81-100`).
- Prekey bundle tamamen signaling endpoint'inden alınıyor
  (`PreKeyBundleFetcher.kt:35-72`).

**Etki**

Signaling/DB/internal network ele geçirilirse recipient prekey/identity
değiştirilebilir ve bot uyarı/ret olmadan saldırgan anahtarına şifreler. Signal
transport kullanmak tek başına authenticated E2EE sağlamaz; identity pin/rotation
politikası gerekir.

**Gerekli çözüm**

- Recipient identity'yi blind recipient index altında AEAD ile kalıcı TOFU pinle.
- Değişikliği otomatik kabul etme; device-signed rotation proof veya açık
  operator/device onayı iste. Session'ı identity epoch'una bağla.

**Kabul testi:** ilk identity pinlenir; server ikinci farklı identity sununca
mesaj gönderimi fail-closed olur; geçerli rotation proof ile kontrollü geçiş olur.

### P0-12 — WebSocket query token'ı proxy/access loglarında credential sızdırabilir

**Kanıt**

- Signaling query `token` veya Authorization header kabul ediyor
  (`WebSocketRoutes.kt:52-55`).
- Bot access JWT'yi doğrudan URL query'sine ekliyor
  (`SignalingWsClient.kt:81-90`).
- Hardened deployment reverse proxy config'i içermiyor. Legacy Nginx config'inde
  `/ws` proxy var fakat access log kapatma/redaksiyon yok
  (`infra/nginx/securechat.conf:49-63`).

**Etki**

Query string reverse proxy, WAF, load balancer, APM, browser history veya hata
telemetrisine girebilir. Sızan access token 1 saate kadar hesap yetkisi verir.
Container `logging:none` host proxy logunu korumaz.

**Gerekli çözüm**

- Production'da query token kabulünü kaldır; mobil/bot istemciler yalnız
  `Authorization: Bearer` kullansın.
- Proxy access logunu kapat veya path/status gibi identity-free alanlara özel
  formatla; query/header asla yazılmasın.
- WS handshake e2e testinde proxy log/capture secret scanner çalıştır.

**Kabul testi:** query token ile bağlantı reddedilir; başarılı header bağlantısı
sonrasında proxy/container log, metric ve trace çıktısında JWT/userId yoktur.

## 5. P1 — yüksek öncelikli bulgular

| ID | Bulgu ve etki | Kanıt | Önerilen kapanış |
|---|---|---|---|
| P1-01 | Aynı kullanıcı reconnect olduğunda eski socket'in `finally` bloğu yeni socket'i map'ten silebilir. Capacity kontrolü mutex dışında; reddedilen yeni socket de `finally` ile mevcut socket'i kaldırabilir. | `ConnectionManager.kt:45-70`, `WebSocketRoutes.kt:97-142` | Session generation/token kullan; `remove(userId, exactSession)` compare-and-remove; `addConnection` açık sonuç dönsün; capacity check/replace tek lock altında olsun. |
| P1-02 | Signaling rate limiter `remove → count → add` atomik değil; aynı milisaniye member'ları çakışıyor. Concurrent istekler limit aşabilir. | `RateLimiter.kt:36-85` | Tek Redis Lua script veya transaction; random unique member; cost ve retry-after aynı atomik işlemde. |
| P1-03 | OTP `HGETALL → compare → DEL/HINCR` atomik değil. Paralel doğru denemeler bir OTP'den birden fazla grant üretebilir; cooldown da check/create yarışı içeriyor. | `OtpService.kt:31-88`, `HttpRoutes.kt:332-343` | Lua ile tek-kullanımlık compare-and-delete/attempt increment; OTP request cooldown NX reservation. |
| P1-04 | Refresh rotation `verify → blacklist → mint` atomik değil; paralel refresh aynı eski token'dan iki yeni family çıkarabilir. | `HttpRoutes.kt:525-543`, `AuthService.kt:139-165` | Durable refresh family'de atomic consume+rotate, reuse detection ve bütün family revoke. |
| P1-05 | Ktor trusted proxy plugin'i yok; `origin.remoteAddress` host Nginx arkasında proxy IP olabilir. Tüm kullanıcılar aynı OTP/WS quota'yı paylaşabilir. | `HttpRoutes.kt:319,376,397,526`, `WebSocketRoutes.kt:57`; legacy proxy `X-Forwarded-*` set ediyor | Yalnız bilinen proxy CIDR'larından forwarded header kabul eden açık trust boundary; proxy ve app rate limit contract testi. |
| P1-06 | OTP/register/refresh/prekey/FCM ve bot `/v1/send` için global body ceiling yok. Bot tüm body'yi RAM'e alıyor; prekey count/key boyutları sınırsız. | `HttpRoutes.kt:325,382,405,527,568,601,669`; `SendPipeline.kt:52-55` | Proxy + app byte limit; strict JSON; liste/adet/base64 decoded-size cap; content type; timeout ve endpoint rate limit. |
| P1-07 | Prekey upload identity, signed key ve OTPK'leri üç ayrı transaction'da yazıyor; fetch de identity/signed/consume işlemlerini tek transaction snapshot'ında yapmıyor. Mixed veya yarım bundle oluşabilir. | `HttpRoutes.kt:566-590`, `PreKeyStore.kt:44-153,160-209` | Tek DB transaction + account row lock; serializable/repeatable-read sınırı; schema size/check constraints; DB hatasını 404 gibi gizleme. |
| P1-08 | Normal message routing recipient'in UUID/registered user olduğunu doğrulamıyor. Saldırgan çok sayıda sahte recipient için opaque Redis key yaratabilir; yalnız per-key cap var, global/account cap yok. | `WebSocketRoutes.kt:629-654`, `ConnectionManager.kt:165-184,432-499` | UUID + active account validation/capability; sender/global queue byte-key quotas; Redis memory budget ve OOM fail-closed testi. |
| P1-09 | Her authenticated kullanıcı arbitrary target'a presence subscribe olabilir; contact/capability/consent kontrolü yok. Target map ve lastSeen/hide setleri process ömrü boyunca büyüyebilir. | `WebSocketRoutes.kt:311-329`, `ConnectionManager.kt:39-149` | Pairwise presence capability/consent, per-user subscription cap, UUID/account validation, empty-key cleanup ve bounded expiry. |
| P1-10 | FCM credential init hatası yutuluyor; health yalnız env path varlığını “enabled” sayıyor. Push readiness kanıtlanmıyor. | `FcmPushSender.kt:51-66`, `HttpRoutes.kt:183-200` | Production init fail-fast veya readiness false; Firebase canary/credential validation; health gerçek initialized state'i kullansın. |
| P1-11 | Push builder yalnız AndroidConfig kuruyor; explicit APNsConfig/content-available/priority yok. iOS background wake davranışı kanıtlanmış değil. | `FcmPushSender.kt:104-132` | APNs data-only config, token/platform modeli, iOS terminated/background integration testi ve privacy-safe payload audit'i. |
| P1-12 | Janus `pendingRequests` timeout/send failure'da temizlenmiyor; onClose/onError ve recursive catch çoklu reconnect başlatabilir; keepalive yok. | `JanusOrchestrator.kt:78-159` | Tek generation/mutex reconnect loop, jitter backoff, `finally { pending.remove }`, session keepalive, readiness ve bounded maps. |
| P1-13 | `GroupCallSessionStore` concurrent map içinde thread-safe olmayan mutable set taşıyor; `start` overwrite edebilir, participant/call cap yok ve 4 saat expiry yalnız erişimde temizleniyor. | `GroupCallSessionStore.kt:24-60,103-120,171-175` | Immutable CAS/actor veya per-call lock; `putIfAbsent`; participant/global call cap; periyodik expiry. |
| P1-14 | Server-generated bazı call/ACK JSON'ları string interpolation ile kuruluyor; `callId` yalnız uzunluk, `messageId` doğrulanmıyor. JSON injection/malformed frame mümkün. | `WebSocketRoutes.kt:350-356,438-445,572-580` | Typed serializable response/buildJsonObject; UUID/opaque token allow-list; bütün server JSON'larında serializer. |
| P1-15 | `file_transfer` quota UTF-8 byte yerine karakter sayıyor; çok byte'lı karakterler limiti düşük gösterir. | `WebSocketRoutes.kt:641-650` | Daha önce hesaplanan UTF-8 `byteSize` veya payload decoded byte count kullan. |
| P1-16 | Flyway checksum/schema drift doğrulaması kapalı ve baseline 0 beklenmeyen mevcut şemayı kabul edebilir. | `Database.kt:65-75` | `validateOnMigrate(true)`, explicit expected target V14/final-schema contract, repair için ayrı operator runbook. |
| P1-17 | Bot grup fanout sequential; kısmi başarıdan sonra hata idempotency reservation'ını siler. Retry daha önce teslim edilen üyelere duplicate yollar. | `SendPipeline.kt:230-240`, `173-195` | Durable per-recipient outbox/state; idempotency sonucu partial recipient durumlarını tutmalı; retry yalnız eksikleri işlemeli. |
| P1-18 | Bot outbound queue `RPOP` ile önce silip yalnız `WebSocket.send()==true` sonucuna güveniyor; server ACK yok. Process/socket kaybında 202 verilmiş mesaj kaybolabilir. | `OutboundQueue.kt:36-68`, `SignalingWsClient.kt:63-78,99-103` | Message-level server ACK + processing/inflight queue + visibility timeout; ACK sonrası delete. Dokümandaki “ACK-after-send” ifadesini buna kadar garanti sayma. |
| P1-19 | Bot WS reconnect global `connected` flag ve eski listener'larla yarışabilir; 5 sn timeout sonrası eski socket açık kalabilir. | `SignalingWsClient.kt:81-145` | Connection generation, exact-socket callback, eski socket cancel, tek reconnect owner ve header auth. |
| P1-20 | Aynı recipient'a concurrent bot send'leri aynı ratchet state'i ayrı DB connection'larıyla load/modify/store edebilir. | `SendPipeline.kt:246-269`, `PgSignalProtocolStore.kt:276-339` | Recipient/device başına serial executor/lock; transaction + optimistic version/CAS; concurrent ratchet property testi. |
| P1-21 | Bot health yalnız DB/Redis'i ölçüyor; identity, signaling WS, queue drain ve privacy migration readiness'i göstermiyor. | `HealthListener.kt:29-57` | Liveness/readiness ayrımı; readiness'e identity, migration, WS ve queue pressure ekle. |
| P1-22 | Hardened Compose healthcheck ve CPU/RAM limitleri içermiyor. JVM `MaxRAMPercentage` container limiti yoksa host RAM'ine göre çalışır. | `compose.privacy.yml:3-134`, Dockerfile'lar | Per-service memory/CPU limit, start/readiness healthcheck, dependency condition, OOM/queue pressure testi. |
| P1-23 | SecretSource runtime'da owner/mode kontrol etmiyor; Compose short secret syntax container içi UID/GID/mode garantisini göstermiyor. Host preflight group/world mode'u kontrol ediyor ama owner'ı kontrol etmiyor. | `SecretSource.kt:51-60`, `deploy_privacy_stack.sh:26-44`, `compose.privacy.yml:82-95` | Secret-manager/Compose mount ownership integration testi; allowed owner UID, mode ve filesystem doğrulaması; HSM vendor provider/image attestation. |
| P1-24 | Identity-free audit sayaçları metrics'e bağlanmıyor; fixed ERROR + Docker logging none nedeniyle auth saldırısı/retention dışı olaylar görünmeyebilir. | `AuditLog.kt`, `BotAuditLog.kt`, logback dosyaları, `compose.privacy.yml:15-16` | Kimlik/timestamp içermeyen bounded counters'ı authenticated metrics/alert'e bağla; fatal readiness ve aggregate anomaly alarmı; privacy bütçesi tanımla. |
| P1-25 | Build script testleri çalıştırmadan fatJar/image üretebiliyor; Codemagic'te hardened server release gate görünmüyor. | `build_privacy_images.sh:21-38` | Build öncesi fresh 64-test + static gate + schema/bootstrap/e2e integration; provenance attestasyonu olmadan image push/deploy reddi. |

## 6. P2 — orta/düşük hardening ve bakım borcu

| ID | Bulgu | Öneri |
|---|---|---|
| P2-01 | Private directory snapshot her authenticated hesaba tüm registry'yi O(N) döndürüyor; toplam kullanıcı sayısını açığa çıkarıyor, bellekte tüm user registry tutuluyor. | Versioned/padded shards veya private-set protocol; response/cpu cap, pagination tasarımı trafik gizliliğini bozmadan yapılmalı. |
| P2-02 | OPRF sorgusu account başına 8192 aday/gün; e-posta hesap farming ve atomik olmayan limiter ile online telefon enumeration ölçeklenebilir. | Sybil-resistant quota/cost, abuse gate ve bağımsız kriptografi/protokol incelemesi; custom blind-RSA'yı standart/incelemiş PSI/OPRF yaklaşımıyla karşılaştır. |
| P2-03 | Public `/health` dependency ve uptime ayrıntısı döndürüyor; legacy Nginx ise sahte sabit 200 döndürüyor. | Ayrı minimal liveness ve operator-only readiness; proxy backend sonucunu iletsin. |
| P2-04 | `/api/v1/sfu/room/{groupId}` yalnız auth istiyor; active-call participant kontrolü yok. | Call capability/participant doğrulaması; endpoint mümkünse kaldırılıp yalnız authenticated call control içinden dağıtım. |
| P2-05 | TURN default'u hardcoded IP ve yalnız `stun:`/`turn:` URI döndürüyor; `turns:`/TLS alternatifi ve rotation operasyonu yok. | Production'da explicit host zorunlu, UDP/TCP/TLS URI seti, cert/domain rotation ve relay privacy testi. |
| P2-06 | Admin rotate yorumu “atomic” diyor ama önce revoke, sonra ayrı create yapıyor; create hatası client'ı kilitler. | Tek DB transaction veya create-new → doğrula → atomik swap/revoke. |
| P2-07 | Admin client create'da `expiresInDays`, `perRecipientPerDay`, allow-list/name/body boyutları yeterince sınırlandırılmıyor. | Strict bounds, canonical allow-list parser, expiry 1..N gün, request byte cap ve negative/overflow testleri. |
| P2-08 | Idempotency NX başarısızken hemen GET null olursa kod reservation almadan `Fresh` döner. | Lua ile reserve/read atomik state machine; owner token ile store/release compare-and-set. |
| P2-09 | Nonce body hash kontrolünden önce tüketiliyor; hatalı/captured body geçerli token nonce'unu yakabilir. | İmza/claim/body hash doğrulamasından sonra atomic nonce consume; body boyutunu önce sınırla. |
| P2-10 | FCM push rate map'leri raw recipient UUID tutuyor ve eviction yok. | Opaque index + bounded TTL cache/Caffeine veya scheduled cleanup. |
| P2-11 | Kullanıcı token/identity kaybı için account recovery veya kontrollü device transfer akışı görünmüyor; mevcut identity conflict dönüyor. | Privacy hedefiyle uyumlu recovery/linked-device kararı; yoksa bunu bilinçli “recover edilemez” ürün sözleşmesi olarak açıkla. |
| P2-12 | AuthService dokümanı/logu access TTL'yi 30 gün diyor, gerçek değer 1 saat. | Yorum/logu gerçek 1h/60d modeline getir; config contract testle. |
| P2-13 | Güncel bağımlılık CVE/SBOM taramasının CI kanıtı yok. Verification metadata supply-chain bütünlüğüne yardım ediyor fakat vulnerability analizi değildir. | Offline mirror ile OSV/Trivy/Grype benzeri SCA, lisans raporu, CycloneDX/SPDX SBOM, image scan ve imza gate'i. Bulgular doğrulanmadan yalnız versiyona bakarak CVE iddiası yapılmamalı. |
| P2-14 | Gradle fresh testte deprecated feature uyarısı Gradle 9 uyumsuzluğunu bildiriyor. | `--warning-mode all`, Gradle/Kotlin/Ktor upgrade planı ve reproducible test. |
| P2-15 | Doküman offline socket “send” işlemini ACK gibi adlandırıyor; gerçek recipient/server ACK yok. | Teslimat durumlarını `queued-local`, `accepted-server`, `delivered-device` olarak ayır ve protokol kanıtı olmadan daha güçlü garanti yazma. |

## 7. Veri ve gizlilik envanteri

### 7.1 PostgreSQL

| Veri | Biçim | Retention / silme | Not |
|---|---|---|---|
| Account | random UUID, directory OPRF token/key ID, public identity material | hesap ömrü | Telefon/e-posta plaintext yok; UUID yine route kimliğidir |
| User prekeys | public identity, signed prekey, unused OTPK | aktif key; OTPK fetch'te delete | Upload/fetch transaction bütünlüğü P1-07 |
| FCM token | opaque user index + v4 AES-GCM, gün bucket'ı | varsayılan 30, üst 90 gün | Plaintext process RAM'de cache |
| API client | random kid, Ed25519 public key, encrypted name/allow-list, limit/expiry/revoke timestamps | aktif; revoke/expire sonrası 30/90 gün | created/updated zamanları operasyonel metadata |
| Bot identity/prekeys | public keyler + encrypted private keyler | aktif/rotation; consumed bot OTPK 1/168 saat | Master-key rotation/escrow runbook'u yok |
| Bot sessions | opaque recipient index + encrypted ratchet record | session/account ömrü | Identity pin ve concurrent ratchet eksik |
| Flyway history | migration version/checksum/timestamp | operasyon ömrü | `validateOnMigrate(false)` düzeltilmeli |

Final schema'da mesaj geçmişi, medya, rehber grafiği, group membership ve davranış
audit tablosu bulunmaması doğru gizlilik kararıdır.

### 7.2 Redis

| State | Yaklaşık ömür | Gizlilik | Güvenlik notu |
|---|---:|---|---|
| Offline mesaj | 15 dk varsayılan / 1 saat üst sınır | opaque key + server AEAD + client E2EE | Per-user cap var, global cap yok |
| Offline file | 5 dk / 15 dk | ayrı opaque/AEAD bucket | byte hesabı düzeltilmeli |
| OTP | 10 dk | e-posta ve OTP HMAC-blind | verify/cooldown atomik değil |
| Rate limit | endpoint window'u | identifier HMAC-blind | atomik değil; restart'ta kayıp kabul edilebilir |
| JWT/user revoke | token expiry / 60 gün | JTI/user HMAC-blind | **restart/eviction kaybı kabul edilemez** |
| Registration grant use | grant expiry | JTI HMAC-blind | restart replay riski |
| 1:1 call | 5 dk | pair HMAC-blind | multi-key update atomik değil |
| Bot nonce/idempotency/outbound | 2-15 dk varsayılan | opaque key + gerekli yerlerde AEAD | ACK/atomicity eksikleri var |
| Bot emergency stop | manuel clear'a kadar | içerik hassas değil | restart/eviction fail-open |

### 7.3 Process RAM

- Tüm user directory registry'si ve opaque tokenlar.
- Aktif socket/sender-recipient route ilişkisi.
- Presence subscriber grafiği, raw UUID last-seen/hide/foreground map'leri.
- Aktif grup call katılımcıları, call ID ve Janus room eşlemesi.
- Plaintext FCM token cache'i.
- Bot request süresince decrypted allow-list ve plaintext gönderim.
- Identity-free security counters.

RAM-only “persistence yok” demektir; “host/runtime saldırganı göremez” demek
değildir. Core/heap dump kapatılması doğru, fakat host swap, hypervisor snapshot,
debug privilege ve observability agent politikaları ayrıca doğrulanmalıdır.

### 7.4 Üçüncü taraf metadata sınırı

| Taraf | Görebileceği veri |
|---|---|
| SMTP sağlayıcısı | registration e-postası, OTP mail zamanı ve hedef adres |
| Firebase/Apple | cihaz push tokenı, generic wake zamanı, kaynak uygulama |
| TURN | uç IP'leri, pseudonymous credential, trafik zamanı/hacmi; P2P içeriği relay ciphertext'tir |
| Janus SFU | uç IP/room/katılım ve trafik metadata'sı; medya-E2EE eklenene kadar medya güven sınırının içindedir |
| Reverse proxy/WAF | IP, route, zaman, byte hacmi; query token kaldırılmazsa credential |
| PostgreSQL operator/backup | final schema metadata ve encrypted/blind-index kayıtlar |

## 8. Test ve doğrulama sonucu

### 8.1 Çalıştırılan kontroller

| Komut/kontrol | Sonuç |
|---|---|
| `server_hardened/` içinde `./gradlew :signaling-server:test :bot-api:test --offline --no-daemon --rerun-tasks` | **PASS**, 64 test, 0 failure, 0 error, 0 skip |
| Gerçek PostgreSQL 16 Testcontainers migration/privacy testleri | Yukarıdaki 64 test içinde **PASS**, skip yok |
| Kök/legacy ağacında `./gradlew -PincludeServer :signaling-server:compileKotlin :bot-api:test --offline --no-daemon --rerun-tasks` | **INFRA BLOCKED**: offline cache'te `org.jacoco.agent:0.8.11` bulunmadığı için `:bot-api:test` başlamadan dependency resolution durdu; uygulama/test sonucu değildir |
| `dart tool/audit_server_deployment_privacy.dart` | **PASS** |
| `test/server_privacy_gate_test.dart` | **PASS**, 12 test |
| `test/server_deployment_privacy_gate_test.dart` | **PASS**, 3 test |
| `test/final_differential_gate_test.dart` | **PASS**, 6 test |
| Canlı anonim route smoke | health 200; latest-version 404; directory-config 404 |

### 8.2 Testlerin kanıtlamadığı alanlar

64/64 sonucu kaynak hedefi için değerlidir fakat aşağıdakiler test edilmemiştir:

- Empty V1-V14 DB üzerinde gerçek `BotIdentityBootstrap.ensureRegistered()`.
- Redis restart/flush/eviction sonrası revoke/deleted-user/emergency semantics.
- Parallel OTP verify, refresh rotation, rate limiter ve idempotency yarışları.
- Aynı kullanıcı eski/yeni WebSocket reconnect yarışı ve MAX_CONNECTIONS sınırı.
- Request body fuzz/oversize ve sahte-recipient global Redis pressure.
- Gerçek reverse proxy üzerinden trusted client IP ve query/header secret leak.
- Gerçek Firebase + APNs background/terminated delivery.
- Gerçek Janus participant auth, session keepalive, reconnect ve medya-E2EE.
- Concurrent bot send ile Signal ratchet state bütünlüğü.
- Hesap silmenin her adımında fault injection/restart.
- Hardened Compose'un gerçek egress/secret ownership/resource/readiness davranışı.

Statik Dart kapıları önemli invariant'ları substring ile denetliyor; semantik
race, transaction sırası veya topology erişilebilirliğini kanıtlamıyor. Örneğin
test adı “ack-after-send” olsa da kodda gerçek server/device ACK'i yok; yalnız
`WebSocket.send()` sonrası Redis remove var.

## 9. Yarın için önerilen uygulama sırası

### Aşama 0 — Canlıyı tanımla ve release'i dondur

1. Çalışan container/image digest, startup command, sanitized env isimleri,
   proxy config ve DB Flyway target'ını salt-okunur çıkar.
2. Canlının root mu hardened mı olduğunu build manifest ile kesinleştir.
3. Private directory route gelene kadar istemcideki fail-closed davranışı koru;
   legacy `/users/check` fallback ekleme.
4. Legacy Nginx static `/health` sonucunu readiness göstergesi olarak kullanma.

### Aşama 1 — Kimlik ve auth safety

1. P0-02 telefon sahipliği modelini karara bağla.
2. P0-03 durable refresh/token epoch/revocation ve Redis ayrımını uygula.
3. P0-04 idempotent delete saga/outbox uygula.
4. P0-06 shared bot JWT secret'ını kaldır.
5. Query JWT'yi kaldır ve trusted proxy sınırını kur.

### Aşama 2 — Çağrı gizliliği

1. Medya-E2EE tamamlanana kadar Janus SFU'yu kapat.
2. Participant-bound Janus capability/proxy doğrulaması uygula.
3. Random room ID, call-store concurrency, reconnect, keepalive ve cleanup'ı
   tamamla.

### Aşama 3 — Bot correctness ve authorization

1. Fresh V14 bootstrap ve reconcile state machine.
2. Group recipient capability/allow-list.
3. Recipient identity pin/rotation.
4. Recipient başına ratchet serialization.
5. Per-recipient durable outbox + gerçek signaling ACK.
6. Gerçek Unix socket listener/deployment.

### Aşama 4 — Abuse/input/concurrency

1. Lua tabanlı atomic signaling/bot rate limit, OTP, refresh ve idempotency.
2. Global body/list/key boyut sınırları.
3. Prekey transaction/snapshot bütünlüğü.
4. WebSocket generation compare-and-remove.
5. Presence capability ve bounded RAM state.

### Aşama 5 — Production rehearsal

1. Ayrılmış internal + controlled-egress topology.
2. Gerçek PostgreSQL/Redis/SMTP/FCM/APNs/Janus bağımlılıklarıyla disposable
   staging.
3. V1-V14 fresh ve V13→V14 populated migration rehearsal + restore rehearsal.
4. Chaos: Redis restart/eviction, DB failover, proxy restart, Janus/FCM outage,
   account-delete mid-flight.
5. Signed image/SBOM/provenance, secret/HSM ownership ve backup-retention gate.
6. Mobile Android+iOS E2E smoke: kayıt, private discovery, 1:1/grup mesaj,
   offline delivery, push, P2P call, SFU yalnız medya-E2EE sonrası.

## 10. Release kabul kriterleri

Production kararı için aşağıdaki maddelerin tamamı kanıtlanmalı:

- [ ] Canlı image digest hardened commit/build manifest ile eşleşiyor.
- [ ] Private directory ve latest-version route contract testleri canlıda geçiyor.
- [ ] Telefon identity first-claim saldırısı engellenmiş.
- [ ] Redis restart/eviction revoke/deletion/emergency state'ini geri açmıyor.
- [ ] Account deletion fault-injection ve retry testleri geçiyor.
- [ ] Bot başka kullanıcı adına token üretemiyor.
- [ ] Fresh V1-V14 bot bootstrap ve restart reconciliation geçiyor.
- [ ] Bot grup send gerçek recipient authorization uyguluyor.
- [ ] Bot recipient identity pinning ve concurrent ratchet testleri geçiyor.
- [ ] Query token reddediliyor; proxy loglarında identity/token yok.
- [ ] SFU ya kapalı ya da bağımsız doğrulanmış medya-E2EE + participant auth var.
- [ ] Hardened topology kontrollü egress ile sıfır manuel override çalışıyor.
- [ ] Bot public/admin Unix socket sınırı erişilebilir ve OS-level yetkili.
- [ ] Body/prekey/presence/queue global limitleri fuzz ve load testlerinde geçiyor.
- [ ] Flyway validation/final schema ve populated upgrade rehearsal geçiyor.
- [ ] FCM ve APNs gerçek cihaz background/terminated testleri geçiyor.
- [ ] CI fresh 64 Kotlin testi + Flutter privacy gates + image/SBOM scan'i
      attest ediyor.

## 11. Son değerlendirme

Sunucu tasarımının privacy-first yönü güçlü ve korunmaya değer; özellikle kalıcı
grup grafiğini/audit timeline'ını silme, opaque kısa ömürlü queue, private
directory OPRF, push-token AEAD ve retention fail-closed kararları sıradan bir
mesajlaşma backend'inden daha iyi. Ancak gizlilik yalnız veriyi DB'den silmekle
tamamlanmıyor: kimlik sahipliği, credential lifecycle, canlı trafik/presence,
SFU media boundary, bot yetki alanı ve gerçekten deploy edilen artefakt aynı
tehdit modeline dahil edilmeli.

Bu rapordaki P0 maddeleri kapanmadan “server mesaj içeriği tutmuyor” ifadesi doğru
olsa bile “üretim sistemi güvenli ve gizlilik garantileri canlıda geçerli” sonucu
çıkarılamaz.
