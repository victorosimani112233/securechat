# Rehber Kimligi ve Telefon Sahipligi — Durum, Yapilanlar, Yapilacaklar

Bu belge `SERVER_REVIEW_2026-08-18.md` P0-02 bulgusunun tam karsiligidir.
Rehber (private contact discovery) modulunun bugun nasil calistigini, hangi
sinirin acik oldugunu, sunucu tarafinda **ne yaptigimi** ve kapanis icin
**ne yapilmasi gerektigini** ayrintili yazar.

2026-08-26 kripto incelemesiyle Flutter ve sunucu sozlesmesi guncellendi.
Detayli bulgular `server_hardened/docs/CRYPTO_REVIEW_2026-08-26.md` belgesinde
yer alir.

---

## 1. Modul bugun ne yapiyor

Rehber keskfi uc bagimsiz parcadan olusur.

### 1.1 Blind-RSA OPRF ile aday degerlendirme

- Istemci rehberdeki numaralari cihazda E.164'e normalize eder ve SHA-256
  alir.
- Her hash 3072-bit blind-RSA OPRF public key'i ile koruliir (blind edilir).
- Istek her zaman **tam 256 elemanlik** sabit bir batch'tir; gercek girdiler
  rastgele cover degerleriyle karistirilir.
- Sunucu `POST /api/v1/directory/evaluate` ile batch'i degerlendirir ve
  finalize edilmis opaque tokenlari doner.

Sunucu bu adimda adres defteri hash'lerini **gormez** ve bir batch icindeki
gercek kisi sayisini ayirt **edemez**.

Bu garanti yalniz sorgu oblivious'ligidir. Ayni operator OPRF private key'ini
ve `users.directory_token` snapshot'ini birlikte gorebiliyorsa kendi telefon
sozlugunu degerlendirip kayitli telefon kimliklerini bulabilir. Honest-but-
curious operatora karsi bu hedef tek sunuculu tasarimla saglanmaz; attested TEE
veya non-colluding threshold OPRF/PSI gerekir.

Kod: `PrivateDirectoryOprf.kt`, istemci tarafi
`lib/src/contacts/private_contact_discovery.dart`.

### 1.2 Sealed snapshot ile eslesme

- `GET /api/v1/directory/snapshot` her hesaba **ayni** listeyi doner.
- Her kayit `label` (token turevi) + `sealedUserId` (token-AEAD ile
  muhurlenmis UUID) tasir.
- Yalniz o tokeni cihazinda ureten istemci ilgili label'i bulup UUID'yi
  acabilir.

Eslesme sonucu, gorunen ad ve telefon **yalniz cihazdaki sifreli
veritabaninda** tutulur. Sunucuda caller-contact sosyal grafigi yoktur.

Kod: `UserRegistry.privateDirectorySnapshot()`, `PrivateDirectoryOprf.sealUserId`.

### 1.3 Kayit sonrasi kimligin indekslenmesi

- `POST /api/v1/otp/verify` e-posta OTP'sini dogrular ve kisa omurlu bir
  **registration grant** doner.
- `POST /api/v1/users/register` yalniz `userId` ve registration grant alir;
  telefon hash'i API sinirini gecmez. Hesap rastgele, snapshot disi bir pending
  token ile acilir.
- Oturum acildiktan sonra istemci kendi hash'ini de 256'lik blind batch icinde
  degerlendirir ve yalniz finalize edilmis 32-byte OPRF token'ini
  `POST /api/v1/users/directory-token` ile gonderir.

Bu ucuncu parca P0-02'nin konusudur.

---

## 2. Acik sinir: e-posta OTP telefon sahipligini kanitlamaz

### 2.1 Somut senaryo

1. Saldirgan kendi e-postasiyla `/otp/request` + `/otp/verify` yapar. Bu
   adim tamamen mesrudur; saldirgan gercekten o e-postanin sahibidir.
2. Kayit sonrasi hedef kisinin normalize telefon numarasindan cihazda OPRF
   token'i uretip kendi authenticated hesabi icin talep eder.
3. Sunucunun elinde bu numaranin saldirgana ait olup olmadigini anlayacak
   **hicbir girdi yoktur**. Numara henuz kayitli degilse kayit basarili olur.

Sonuc:

- Hedef kisinin rehberindeki kullanicilar o numarayi cozdugunde saldirganin
  UUID'sini bulur.
- Prekey bundle saldirgandan gelir; E2EE oturumu **saldirganin anahtarina**
  kurulur.
- Gercek sahip sonradan kayit olmak istediginde `directory_identity_already_
  registered` alir ve kendi numarasini kullanamaz.

Bu, sahte hesap acma suistimalinden farklidir: rehber tabanli **kimlik
atfi** yanlis kisiye baglanir.

### 2.2 Neden mevcut kontroller yetmiyor

| Kontrol | Ne kanitlar | Bu senaryoyu durdurur mu |
|---|---|---|
| E-posta OTP | E-postanin saldirgana ait oldugunu | Hayir — saldirgan kendi e-postasini kullanir |
| Registration grant tek kullanimlik | Grant'in tekrar oynatilmadigini | Hayir — saldirgan taze grant alir |
| `users_register` rate limit | Hizli toplu denemeyi | Kismen — hedefli tek talebi durdurmaz |
| `DirectoryIdentityAlreadyRegisteredException` | Kayitli kimligin devralinmadigini | Hayir — bu kontrol yalniz **zaten kayitli** numaralar icin calisir |

Son satir onemlidir: mevcut kod kayitli bir kimligin devralinmasini dogru
sekilde reddeder. Acik olan **ilk talep** penceresidir.

### 2.3 Dogru dogrulanan kod referanslari

- `AuthService.issueRegistrationToken()` — grant `sub=registration-grant`
  tasir; telefon, userId, directory token veya cihaz anahtari ile hicbir
  bagi yoktur.
- `HttpRoutes.kt` `/api/v1/users/register` telefon girdisi almaz;
  `/api/v1/users/directory-token` finalize token alir.
- `UserRegistry.updateOwnDirectoryToken()` token cakismasini kontrol eder;
  telefon sahipligini kanitlayan bir girdi yoktur ve bu katman kanitlayamaz.

---

## 3. Sunucu tarafinda ne yaptim

Asagidakilerin tamami istemci protokolunu degistirmez.

### 3.1 Registration grant tuketimi kalici ve atomik hale getirildi

**Onceki durum.** Grant'in "kullanildi" isareti yalniz Redis'teydi
(`registrationTokenUseKey`, `SET NX EX`). O Redis bilerek persistence'siz ve
`allkeys-lru` calisir. Grant'in 15 dakikalik omru icinde bir restart veya
bellek baskisi isareti dusurebilir; tuketilmis bir grant yeniden
oynatilabilir hale gelir.

**Simdi.**

- `V18__durable_registration_grant_use.sql` ile `registration_grant_use`
  tablosu eklendi. Satir yalniz grant'in rastgele JTI'sinin keyed blind
  index'ini ve replay penceresinin bitisini tutar. Hesap, e-posta, telefon
  veya directory referansi **yoktur**.
- `AuthService.registrationGrantClaim()` yalniz dogrular; tuketmez.
- `RegistrationGrants.claimAccount()` grant tuketimini ve hesap kaydini
  **tek transaction** icinde yapar:
  - kayit basarili olursa grant kesin olarak yanar,
  - kayit reddedilirse (kimlik arada baskasi tarafindan alinmissa) grant
    tuketilmemis kalir ve kullanici yeniden deneyebilir,
  - ayni grant ile paralel istekler gelirse yalniz biri kazanir.
- `PrivacyRetentionWorker` suresi dolmus isaretleri temizler.

**Kanit.** `RegistrationGrantIntegrationTest` (gercek PostgreSQL):
tek hesap kaydi, cache kaybindan sonra replay reddi, reddedilen kaydin
grant'i yakmamasi, 8 paralel denemede tek kazanan, ve isaret satirinda
hesap referansi bulunmamasi + purge.

### 3.2 Snapshot dolgusu ve kalici kota (2026-08-20)

Iki ek sizinti kapatildi.

**Kullanici sayisi.** `/api/v1/directory/snapshot` her hesaba ayni listeyi
verir, dolayisiyla eleman sayisi dogrudan kayitli hesap sayisiydi. Kimlik
dogrulamis herhangi bir istemci — ornegin gunde bir kez ceken biri — sunucunun
buyuklugunu ve buyume hizini olcebiliyordu. Liste artik 256'lik kovaya
yuvarlanir. Dolgu kayitlari gercek kayitlardan ayirt edilemez: etiket 32 byte,
zarf 12+36+16 byte, ikisi de ayni bicimde base64url. Dolgu etiketi sunucu
anahtariyla turer, boylece rebuild'ler arasinda sabit kalir — her rebuild'de
degisen bir etiket, deterministik turemis gercek etiketlerin yaninda dolguyu
ele verirdi. Zarf ise gercek kayitlarda da her muhurlemede degistigi icin
yenilenir.

Ayni degisiklik istek basina O(N) muhurlemeyi de kaldirdi: liste zaten herkes
icin ayni oldugundan uyelik surumu degisene ya da 60 saniye dolana kadar
paylasilir.

**Kota.** OPRF degerlendirme kotasi yalniz Redis sliding window'undaydi. Redis
bu dagitimda kasten kalicisizdir (RDB kapali, bkz. `RedisEphemeralPolicy`);
restart ya da bellek baskisi tum sayaclari sifirliyordu. Yani enumeration'a
karsi konan gunluk sinir, beklenerek ya da Redis dusurulerek tekrar tekrar
denenebilir bir engeldi. Gunluk kota artik PostgreSQL'de `directory_quota`
tablosunda tutulur: satir hesabin blind index'ini, gun kovasini ve sayaci
tasir — ham `user_id` ya da istek zaman cizelgesi yok — ve iki gun sonra
retention worker tarafindan silinir. Kontrol tek atomik ifadedir; reddedilen
istek sayaci artirmaz, aksi halde sinira dayanan bir hesap kendini kalici
olarak kilitleyebilirdi.

Bunlarin ikisi de bolum 2'deki telefon sahipligi bosluguna dokunmaz; yalniz
enumeration maliyetini ve sunucu buyuklugu sizintisini kapatirlar.

### 3.3 Yan etkiler

- Redis artik auth guvenlik kararlarinin tek sahibi degil. P0-03 ile
  birlikte credential iptali de PostgreSQL'e tasindi; boylece "Redis kaybi
  guvenligi geri aciyor" sinifi tamamen kapandi.
- `users` tablosuna hicbir yeni kimlik iliskisi eklenmedi.

### 3.4 Bilincli olarak yapmadiklarim

| Fikir | Neden yapilmadi |
|---|---|
| E-posta -> hesap iliskisini DB'de tutup "her e-posta bir telefon" kurali | Kalici e-posta/hesap baglantisi yaratirdi. V4 e-posta kolonunu, V8 zaman damgalarini tam da bu yuzden silmisti; geri getirmek gizlilik sozlesmesinin ihlali olurdu |
| Sunucunun `userId`'yi kendi uretmesi | Istemci kendi UUID'sini local Signal identity'siyle birlikte kullaniyor; wire kontratini degistirir ve Flutter tarafina dokunmayi gerektirir. Ayrica P0-02'yi cozmez (sorun UUID secimi degil, telefon sahipligi) |
| Zorunlu commitment alani eklemek | Istemci gondermeden zorunlu kilmak production'i kirar; opsiyonel eklemek olu kod olur. Bolum 6'da istemci isi olarak tanimlandi |

---

## 4. Kalan acik risk

**Ozet: bir saldirgan halen, henuz kayitli olmayan herhangi bir telefon
kimligini kendi hesabina baglayabilir.**

Bu, sunucu kodu ile kapatilamaz. Sunucunun elinde numaranin istegi yapan
kisiye ait oldugunu gosteren hicbir kanit yoktur. Kapanis icin ya gercek bir
sahiplik kaniti ya da telefon disi bir kimlik baglama yolu gerekir.

Etkiyi sinirlayan mevcut gercekler:

- Saldirganin hedefin numarasini **bilmesi** gerekir (rehber keskfi bunu
  vermez; snapshot yalniz opaque label tasir).
- Numara zaten kayitliysa devralma reddedilir.
- Gercek sahip kayit olamadigini hemen fark eder (`conflict` yaniti).

Bu sinirlar riski daraltir, ortadan kaldirmaz.

---

## 5. Kapanis secenekleri

### Secenek A — Invite/QR capability (gizlilik acisindan en uygun)

Telefon kimligi yalniz yuksek entropili, tek kullanimlik bir davet
capability'si ile talep edilebilir. Daveti mevcut bir hesap veya operator
uretir.

- Yeni ucuncu taraf yok, yeni metadata yok.
- Sunucu tarafi: capability uretimi/dogrulamasi + `users/register` akisinda
  zorunlu kilma. Tahmini 1-2 gunluk sunucu isi.
- Bedel: davetsiz kendi basina kayit olunamaz.

### Secenek B — SMS/voice OTP

Gercek telefon sahipligi kaniti.

- Sunucu tarafi: SMS saglayici entegrasyonu, ikinci OTP akisi, grant'in
  telefon kimligine baglanmasi.
- Bedel: saglayici numarayi, zamani ve hedefi gorur. `SERVER_DATA_PRIVACY_
  AUDIT.md` ucuncu taraf tablosuna yeni satir girer; retention politikasi
  yazilmalidir. Ayrica birim maliyet.

### Secenek C — Simdilik kabul edilen risk

Telefon tabanli kayit mevcut haliyle kalir; risk dokumante edilir ve
kabul edilir.

- Sunucu tarafi is yok.
- Yayin oncesi `SERVER_DATA_PRIVACY_AUDIT.md` tehdit modeline acik bir
  madde eklenmelidir: "rehberde gorunen kimligin gercek numara sahibi
  oldugu kanitlanmaz".

**Not:** Hangi secenek secilirse secilsin, bolum 6'daki commitment baglama
isi ayrica degerlidir; secenegin ustune biner, yerine gecmez.

---

## 6. Istemci (Flutter) tarafinda yapilmasi gerekenler

> Tarihsel taslak: Asagidaki commitment onerisi uygulanmadi ve mevcut wire
> contract'i tarif etmez. Telefon hash'ini yeniden kayit istegine sokacagi ve
> telefon sahipligini yine kanitlamayacagi icin 2026-08-26 review'unda
> reddedildi. Mevcut contract bolum 1.3'tedir; kalan dogru cozum phone OTP veya
> platformca dogrulanmis numara sahipligi kanitidir.

### 6.1 Amac

Bu taslagin yazildigi tarihte grant hicbir seye bagli degildi. Sizan bir
bir grant, herhangi bir `userId` + `phoneHash` cifti icin kullanilabilir.
Commitment bunu kapatir: grant yalniz **onceden beyan edilmis** tek bir
talep icin gecerli olur.

### 6.2 Adimlar

1. **OTP dogrulama isteginde commitment gonder.**
   `POST /api/v1/otp/verify` govdesine yeni alan:

   ```
   claimCommitment = base64url( SHA-256(
       userId || 0x00 || phoneHash || 0x00 || identityPublicKey || 0x00 || directoryKeyId
   ) )
   ```

   - `userId`: istemcinin uretecegi UUID (kayittan once uretilmeli).
   - `phoneHash`: kayitta gonderilecek deger ile **birebir ayni**.
   - `identityPublicKey`: cihazin Signal identity public key'i (raw byte).
   - `directoryKeyId`: `GET /api/v1/directory/config` yanitindaki key id.

2. **Kayit isteginde ayni degerleri gonder.**
   `POST /api/v1/users/register` govdesi degismez; sunucu commitment'i
   ayni formulle yeniden hesaplar ve grant icindekiyle karsilastirir.
   Eslesmezse `403 registration_commitment_mismatch`.

3. **Identity key sirasi.** Bugun Signal identity kayittan sonra
   uretilebiliyorsa, uretim sirasi one alinmalidir: commitment identity
   key'i icerdigi icin OTP dogrulamasindan **once** var olmalidir.

4. **Hata yolu.** Commitment uyusmazliginda istemci sessizce yeniden
   denememelidir; kullaniciya kaydin reddedildigi gosterilmeli ve akis
   bastan baslatilmalidir.

5. **Geriye uyumluluk.** Sunucu tarafinda alan once opsiyonel olarak
   eklenmeli, istemci surumu yayildiktan sonra `PRIVACY_PRODUCTION_MODE`
   altinda zorunlu yapilmalidir. Zorunlu hale gelmeden once eski istemciler
   kayit olamaz duruma dusmemelidir.

### 6.3 Sunucu tarafinda karsilik gelen is

- `AuthService.issueRegistrationToken(commitment: String?)` — `cmt` claim'i.
- `registrationGrantClaim()` — `cmt` degerini disari verir.
- `/users/register` — commitment yeniden hesaplanir ve karsilastirilir;
  `RegisterRequest`'e `identityPublicKey` alani eklenir (bugun prekey upload
  ayri bir istekte geliyor).
- Zorunluluk `DIRECTORY_CLAIM_COMMITMENT_REQUIRED` ile kontrol edilir;
  production'da varsayilan `true` olmalidir.

Tahmini sunucu isi: yarim gun. Istemci isi ve surum yayilim suresi ayrica
planlanmalidir.

---

## 7. Rehber modulune dair diger acik maddeler

| ID | Konu | Durum |
|---|---|---|
| P0-01 | Canli uctaki `GET /api/v1/directory/config` 404 doner; calisan artefakt hardened kontratin gerisinde. Rehber production'da bu yuzden zaten kapali | Deployment kapisi |
| P2-01 | Snapshot her authenticated hesaba tum registry'yi O(N) doner; toplam kullanici sayisini acik eder ve registry RAM'de tam tutulur | P2 dalgasi |
| P2-02 | OPRF kotasi hesap basina 32 batch/gun (8192 aday). E-posta hesap farming ile online telefon enumeration olceklenebilir | P2 dalgasi |
| Tracker 35 | Export edilemeyen PKCS#11 HSM uzerinde OPRF key rotation/failover tatbikati; kesintisiz dual-key rotation henuz yok | EXTERNAL |

---

## 8. Karar bekleyen tek soru

Telefon sahipligi icin bolum 5'teki A / B / C seceneklerinden hangisi?

- Sunucu telefon hash'i almaz ve finalize OPRF token'ini yalniz authenticated
  hesaptan kabul eder; bu yine telefon sahipligi kaniti degildir,
- P0-02 `SERVER_HARDENING_PROGRESS.md` icinde **EXTERNAL** olarak acik
  kalir,
- Bolum 3'teki sertlestirmeler yururluktedir ve hangi secenek secilirse
  secilsin gecerliligini korur.
