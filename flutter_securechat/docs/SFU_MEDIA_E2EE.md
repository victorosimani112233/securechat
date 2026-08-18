# SFU Medya Uctan Uca Sifrelemesi — Tasarim ve Uygulama Sartnamesi

Bu belge `SERVER_REVIEW_2026-08-18.md` P0-05 bulgusunun kalici cozumudur.
Sunucu tarafinda yapilanlari, istemci tarafinda yapilacaklari dosya ve API
seviyesinde tanimlar.

**Durum:** Sunucu yarisi tamam. Istemci yarisi, uygulama test dalgasi bittikten
ve Flutter agacina dokunma izni verildikten sonra baslar.

---

## 1. Problem

Grup aramasi katilimci esigini asinca Janus SFU devreye giriyor. SFU yolunda
WebRTC oturumu Janus'ta **sonlaniyor**: DTLS-SRTP orada cozuluyor. Kaynak
agacinda SFrame, FrameCryptor veya esdeger bir uygulama-katmani medya
sifrelemesi yok. Sonuc: Janus host/process'i ses ve goruntu icin guven
sinirinin **icinde**.

Bu, urunun "sunucu icerigi goremez" iddiasiyla celisir. P2P/TURN yolunda
celiski yoktur; TURN yalniz ciphertext relay eder.

## 2. Hedef mimari

WhatsApp ve Signal'in yaptigi: SFU bir **ciphertext yonlendiricisi**ne
indirgenir. Katilimcilar RTP payload'ini uclarda sifreler, RTP header'lari
acik kalir; SFU paketi yonlendirebilir ama icerigi okuyamaz.

Kazanim iki yonludur:

| | Mesh (bugun) | SFU + medya E2EE |
|---|---:|---:|
| Goruntulu tavan | ~6 | 32 |
| Sesli tavan | ~10 | 32 |
| Cihaz basina encode | N-1 | 1 |
| Cihaz basina upload | N-1 akis | 1 akis |
| Sunucunun medyaya erisimi | yok | yok |

Mesh'te her PeerConnection kendi encoder'ini calistirir; ortak local stream
kullanilsa bile encode paylasilmaz. 32 kisilik bir aramada her telefonun 31
ayri video encode etmesi gerekirdi — bu yuzden mesh ile o olcege cikilamaz.

## 3. Kritik tasarim notu — anahtar dagitimi sunucudan gecmez

Grup uyeligi **cihazda** tutulur; sunucu kalici grup grafigi tutmaz. Bu
mimari burada dogrudan bir guvenlik avantaji saglar:

- Medya anahtarini kime verecegine **istemci** karar verir.
- Kotu niyetli bir sunucu Janus odasina katilimci ekleyebilir, fakat o
  katilimciya anahtar gitmez; yalniz ciphertext alir.

Sonuc: **Janus token auth bir gizlilik kontrolu degil, abuse/DoS
kontroludur.** Onceligi buna gore degerlendirilmelidir.

## 4. Sunucuda yapilanlar (tamamlandi)

### 4.1 Yetenek-kapili SFU promosyonu

`GroupCallSessionStore.ActiveCall` artik katilimci basina medya sifreleme
yetenegini tutar (`mediaE2eeParticipants`). `mediaEndToEndEncrypted` ancak
**tum** katilimcilar bildirdiginde true olur.

`SfuPolicy.canPromote(mediaEndToEndEncrypted)`:

- Tum katilimcilar frame sifrelemesi bildiriyorsa → SFU'ya gecilebilir,
  operator kabul beyani gerekmez (medya zaten guven sinirinin disinda).
- Biri bile bildirmiyorsa → gecis yalniz acik kabulle
  (`SFU_MEDIA_BOUNDARY_ACK`) mumkundur.
- `SFU_ENABLED` hic acilmamissa → hicbir kosulda gecilmez.

Yetenek bildirimi wire'da `group_call_invite` ve `group_call_join_request`
frame'lerindeki opsiyonel `mediaE2ee` boolean alanidir. Alan yoksa `false`
kabul edilir: **eski istemci sessizce SFU'ya gecirilmez.**

### 4.2 Katilimci tavani

`SfuPolicy.meshCapacity(callType)` → VIDEO 6, VOICE 10.
`SfuPolicy.MAX_PARTICIPANTS` → 32.

Tavan moda baglidir: SFU'ya gecilemiyorsa mesh tavani, gecilebiliyorsa
protokol tavani uygulanir. Kontrol per-group lock altindadir; iki es zamanli
katilim tavani birlikte asamaz. Tavan dolunca katilim `GROUP_CALL_CAPACITY_
REACHED` sayaciyla reddedilir — sessiz bozulma yerine ongorulebilir ret.

### 4.3 Concurrency ve room ID

- `ActiveCall.participants` immutable oldu; tum degisiklikler per-group lock
  altinda kopya uzerinden yapilir. Onceki `MutableSet` concurrent map icinde
  thread-safe degildi.
- Janus room ID artik `groupId.hashCode()` degil, aktif odalarla cakismayan
  62-bit rastgele deger. Eski deger 31 bitlik ve grup routing tokenini bilen
  biri tarafindan onceden hesaplanabilirdi.

Kanit: `GroupCallCapacityTest` (7 senaryo), `SfuPolicyTest` (6 senaryo).

## 5. Istemcide yapilacaklar

### 5.1 Bagimlilik — yukseltme gerekmiyor

Pinli `flutter_webrtc 1.6.0` su siniflari zaten expose ediyor:

- `FrameCryptor` — frame sifreleme/cozme
- `FrameCryptorFactory` — cryptor uretimi
- `KeyProvider`, `KeyProviderOptions` — paylasilan anahtar
- `Algorithm`, `KeyDerivationAlgorithm` — algoritma ve ratchet secimi

Supply-chain kilidi (`pubspec.lock` 129 paket SHA-256, Gradle verification
manifestleri) **yeniden uretilmeyecek**. Bu, isin en buyuk riskini dusuruyor.

### 5.2 Anahtar modeli

```
callMediaKey : 32 byte, cagri basina rastgele
keyEpoch     : 0'dan baslayan tamsayi, her uyelik degisiminde artar
```

- Anahtari **cagriyi baslatan** uretir.
- Her katilimciya **ayri direct Signal zarfi** icinde gonderilir. Bu yol
  zaten var: grup mesaji `GROUPROUTE:v3` ile tam bunu yapiyor.
- Zarf icerigi (onerilen): `CALLKEY:v1:<callId>:<epoch>:<base64 key>`.
- Sunucu yalniz ordinary `encrypted_message` gorur; anahtari veya epoch'u
  goremez.

### 5.3 Rotasyon kurallari

| Olay | Yapilacak | Neden |
|---|---|---|
| Yeni katilimci | epoch+1, yeni anahtar tum uyelere dagitilir | Yeni uye onceki frame'leri cozememeli |
| Katilimci ayrildi | epoch+1, yeni anahtar **kalan** uyelere dagitilir | Ayrilan sonraki frame'leri cozememeli |
| Cagri bitti | anahtar bellekten silinir | Kalici anahtar tutulmaz |

Yeni anahtar dagitimi tamamlanmadan gonderen tarafin epoch'u artirilmaz;
aksi halde alicilar cozemez.

### 5.4 Dosya bazinda is listesi

**`lib/src/core/signal_message.dart`**

- `GroupCallInviteSignal` ve `GroupCallJoinRequestSignal` siniflarina
  `final bool mediaE2ee` alani eklenir; `toJson` icinde `mediaE2ee` olarak
  yazilir, `fromJson` icinde eksikse `false` okunur.
- Sunucu bu alani zaten opsiyonel okuyor; eski sunucu ile de uyumludur.

**`lib/src/media/group_media_engine.dart`**

- `FrameCryptorFactory` ile publisher/subscriber PeerConnection'lari icin
  cryptor kurulur.
- Yeni API yuzeyi:
  - `Future<void> enableMediaEncryption({required Uint8List key, required int epoch})`
  - `Future<void> rotateMediaKey({required Uint8List key, required int epoch})`
  - `Future<void> setParticipantKey(String participantId, Uint8List key, int epoch)`
- Her `RTCRtpSender` icin sender cryptor, her `RTCRtpReceiver` icin receiver
  cryptor olusturulur ve `KeyProvider` paylasilir.
- Cryptor'lar `_disposeConnection` yolunda kapatilir.

**`lib/src/media/call_manager.dart`**

- Cagri baslatilirken anahtar uretilir ve `mediaE2ee: true` ile invite
  gonderilir.
- `_bindSfu` ve `_subscribeToSfuFeed` cagirilmadan **once** cryptor kurulmus
  olmalidir; aksi halde ilk frame'ler acik gider.
- Uyelik degisikliginde rotasyon tetiklenir.
- Anahtar dagitimi mevcut encrypted-message yolundan gecer; yeni bir wire
  tipi eklenmez.

**`lib/src/crypto/` (degisiklik yok)**

- Anahtar dagitimi mevcut `SendMessageUseCase` / Signal session yolunu
  kullanir. Yeni kripto primitive'i eklenmez.

### 5.5 Fail-closed davranis

- Cryptor kurulamiyorsa (platform destegi yok, API hatasi) istemci
  `mediaE2ee: false` bildirir ve mesh'te kalir. **Sessizce sifresiz SFU'ya
  gecilmez.**
- Anahtar dagitimi bir aliciya ulasmadiysa o alici aramaya alinmaz.
- Epoch uyusmazliginda frame cozulemez; kullaniciya "yeniden baglaniliyor"
  gosterilir, acik medyaya dusulmez.

## 6. Janus tarafi

### 6.1 Zorunlu

- `record: false` kalmali. Frame sifreliyken kayit anlamsizdir ve gizlilik
  acisindan da istenmez.
- Transcoding kullanilmaz; SFU yalniz forward eder.

### 6.2 Opsiyonel — token auth (abuse kontrolu)

Bolum 3'teki nedenle bu bir gizlilik kontrolu degildir; yetkisiz kisinin oda
kaynaklarini tuketmesini engeller.

- `janus.jcfg` icinde `token_auth = true`.
- Sunucu Admin API `add_token` ile katilimci basina kisa omurlu token
  uretir, yalniz o katilimciya `SfuRoomInfo` icinde verir; ayrilista
  `remove_token` yapar.
- Istemci join isteginde token'i gonderir (tek alan).

**Bu adim istemci degisikligiyle birlikte devreye alinmalidir.** Once
acilirsa mevcut istemcilerin hicbiri Janus'a baglanamaz.

## 7. Dogrulama plani

Kod incelemesi bu is icin yeterli kanit degildir. Gereken:

1. **Paket yakalama.** Janus host'unda RTP payload'i yakalanir; plaintext
   ses/goruntu cikarilamamali. VP8 keyframe imzasi gorunmemeli.
2. **Cikarilan uye testi.** Aramadan cikarilan katilimci, cikarildiktan
   sonraki frame'leri cozememeli (epoch rotasyonu calisiyor).
3. **Yeni uye testi.** Sonradan katilan, katilmadan onceki frame'leri
   cozememeli.
4. **Fallback testi.** Bir istemci `mediaE2ee: false` bildirdiginde arama
   mesh'te kalmali; SFU'ya gecmemeli.
5. **Olcek testi.** En az 8 katilimci ile SFU yolunda ses/goruntu kalitesi
   ve cihaz sicakligi olculmeli.
6. **Cihaz matrisi.** En az iki gercek cihaz; tercihen `soak-test-checklist`
   OEM matrisinden ikisi.

## 8. Sira ve tahmini efor

| Adim | Nerede | Tahmin |
|---|---|---|
| 1. FrameCryptor API'sinin iki platformda dogrulanmasi | Flutter | 0,5 gun |
| 2. `group_media_engine` cryptor entegrasyonu | Flutter | 2 gun |
| 3. Anahtar uretimi/dagitimi/rotasyonu | Flutter | 2-3 gun |
| 4. Signal codec `mediaE2ee` alani | Flutter | 0,5 gun |
| 5. Widget/unit testleri | Flutter | 1 gun |
| 6. Janus token auth (sunucu + config + istemci alani) | Sunucu + Janus | 1 gun |
| 7. Cihaz + paket yakalama dogrulamasi | Cihaz | 1-2 gun |

Toplam: yaklasik 8-10 is gunu, cihaz turu dahil.

## 9. Bu is yapilana kadar gecerli durum

- SFU varsayilan **kapali**; grup aramalari mesh'te.
- Pratik tavan: yaklasik 6 goruntulu, 10 sesli katilimci. Tavan asilirsa
  arama sessizce bozulmaz, katilim reddedilir.
- Medya hicbir sunucudan gecmez; gizlilik iddiasi bu haliyle dogrudur.
- Bedeli olcek: WhatsApp'in 32 kisilik sinirina bu yolla cikilamaz.
