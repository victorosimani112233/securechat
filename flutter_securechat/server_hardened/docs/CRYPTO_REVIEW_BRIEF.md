# Kriptografik İnceleme Brief'i — SecureChat Server (Bağımsız Review İçin)

**Amaç:** Bu belge, SecureChat sunucu tarafının kriptografik tasarım ve
implementasyonunun **bağımsız** bir inceleyici (bu kodu yazmayan bir ajan/kişi)
tarafından denetlenmesi içindir. İnceleyici canlı sunucuya ihtiyaç duymaz —
inceleme statiktir: kaynak kod + protokol + wire format + test vektörü.

Kök dizin (aksi belirtilmedikçe tüm yollar buna görelidir):
`flutter_securechat/server_hardened/` (sunucu), `flutter_securechat/lib/`
(istemci).

> İnceleyiciye not: Yorumlar/dokümantasyon Türkçe, kod İngilizce. "Bilinçli
> tasarım" iddialarına **güvenme**, doğrula. Her bulguyu `dosya:satır` +
> somut senaryo + öneri ile raporla (§7 format).

---

## 1. Sistem ve threat model

WhatsApp benzeri, uçtan uca şifreli mesajlaşma. Sunucu **içeriği asla
göremez**; yalnız şifreli zarfları yönlendirir ve gizlilik-korumalı yardımcı
servisler (rehber keşfi, prekey dağıtımı, çağrı sinyalleşmesi) sunar.

**Saldırgan modeli (doğrulanacak güvenlik hedefleri):**
- **Sunucu = honest-but-curious / kısmen kötücül.** Sunucu operatörü DB, Redis,
  logları görebilir; mesaj içeriğini, sosyal grafiği, telefon rehberini
  **öğrenememeli**.
- **Ağ gözlemcisi** — TLS altında; ayrıca metadata minimizasyonu.
- **Kimlik doğrulamış kötücül istemci** — başkasını taklit edememeli, IDOR
  yapamamalı, başka kullanıcının anahtar havuzunu tüketememeli.
- **Rehber enumeration** — sunucu telefon numarası sözlüğü çalıştıramamalı;
  istemci de sunucudan tüm kullanıcı grafiğini çekememeli.

**Bu incelemenin KAPSAM DIŞI olanı:** ağ pentest, DoS, rate-limit (ayrı strix
taramaları yapıldı), UI. **Kapsam: yalnız kriptografi + protokol + anahtar
yönetimi.**

---

## 2. Kripto envanteri (incelenecek yüzeyler, öncelik sırasına göre)

### P0 — Özel/novel kripto (EN YÜKSEK RİSK, standart kütüphane değil)

**A. Blind-RSA OPRF — private contact discovery**
- Sunucu: `signaling-server/.../PrivateDirectoryOprf.kt`
- İstemci: `lib/src/contacts/private_contact_discovery.dart`
- Ne yapar: istemci telefon-hash'lerini kör (blind) eder → sunucu RSA private
  operasyonuyla değerlendirir → istemci unblind edip token türetir. Sunucu ham
  hash'i görmez; DB yalnız finalize token tutar.
- Kritik parçalar:
  - `fullDomainPoint()` (satır ~196) — hash-to-group (full-domain hash);
    counter-genişletme + `mod (modulus-1) + 1`, gcd kontrolü.
  - `privateOperation()` (satır ~182) — `RSA/ECB/NoPadding` (kasıtlı; şifreleme
    değil, ham grup işlemi). **Doğrula: padding yokluğu bu OPRF için doğru mu,
    yoksa Bleichenbacher/rogue-input riski var mı?**
  - `finalizeToken()` (satır ~218) — `SHA-256(domain || evaluated)`.
  - `sealUserId()` / `openUserIdForTest()` (satır ~98/128) — AES-GCM ile
    directory entry mühürleme; label + entry-key `SHA-256(domain||token)`'dan
    türer; AAD = `keyId || label`.
  - `decoyEntry()` (satır ~133) — dolgu kayıtları (kullanıcı sayısı gizleme).
  - Sabitler (satır ~235): RSA ≥ 3072-bit, e=65537, batch=256, token=32B.
- **İnceleyici soruları:**
  1. OPRF gerçekten oblivious mi? Sunucu blinded değerden telefon-hash'i
     çıkarabilir mi? İstemci unblind'ı doğru mu (kod istemcide)?
  2. Full-domain hash düzgün mü (bias, küçük alt-grup, gcd tuzakları)?
  3. `RSA/NoPadding` ile rogue/kötü blinded input grup dışına taşabilir mi?
     `evaluate()` (satır ~142) grup üyelik kontrolü yeterli mi
     (`value > 1 && value < modulus && gcd==1`)?
  4. Verifiability yok — istemci sunucunun doğru anahtarla değerlendirdiğini
     doğrulayamaz (keyId pinning dışında). Bu kabul edilebilir mi?
  5. Dolgu (`decoyEntry`) gerçek kayıttan ayırt edilebilir mi (label/zarf
     uzunluğu, dağılım)?
  6. Anahtar boyutu/exponent, HSM/PKCS#11 anahtar izolasyonu (fromPkcs11).

**B. Media E2EE anahtar dağıtımı (SFU)**
- İstemci: `lib/src/media/call_media_key.dart`,
  `lib/src/media/group_media_engine.dart` (FrameCryptor/KeyProvider)
- 32B AES-GCM anahtar, kuşak (epoch), her katılımcıya **direct Signal zarfıyla**
  dağıtılır (sunucudan geçmez). Wire: `CALLKEY:v1:<callId>:<epoch>:<b64>`.
- **İnceleyici soruları:** anahtar rotasyonu (üye giriş/çıkış), forward
  secrecy (kuşak arası), `keyIndex = epoch % 16` çakışması, foreign-callId
  reddi, KeyProvider `ratchetSalt` kullanımı.

### P1 — Standart primitiflerin doğru kullanımı

**C. Purpose-separated AEAD + blind index**
- `signaling-server/.../ServerPrivacy.kt` — `sealQueue/openQueue` AES-256-GCM
  (12B nonce `SecureRandom`, AAD = `queueAad(recipientId)`, prefix `OQ1:`),
  `blindIndex` HMAC-SHA256, purpose ayrımı (`PRIVACY_INDEX_KEY` ≠
  `OFFLINE_QUEUE_ENCRYPTION_KEY`).
- `signaling-server/.../FcmTokenCipher.kt` — FCM token AES-GCM.
- `bot-api/.../delivery/BotQueuePrivacy.kt` — AES-256-GCM (satır 59/75),
  HMAC-SHA256 blind index (satır 30), `sealPrivate/openPrivate` purpose-bound.
- `bot-api/.../signal/KeyEncryptor.kt` — session record AES-GCM (BOT_MASTER_KEY).
- **İnceleyici soruları:** nonce **benzersizliği** (12B random ile GCM nonce
  reuse olasılığı; sabit anahtarla ~2^32 mesajdan sonra riskli mi?), AAD
  binding yeterli mi (cross-purpose/cross-recipient karıştırma), tag boyutu
  (128 bit), anahtar ayrımı gerçekten enforce mü (PurposeSeparatedSecrets).

**D. JWT / imza**
- `signaling-server/.../AuthService.kt` — kullanıcı token HS256 (java-jwt);
  `credential_epoch` (`epc`) + `jti` gömülü; logout epoch rotasyonu.
- `bot-api/.../auth/EdDsaJwtVerifier.kt` — bot JWT Ed25519 (JDK native);
  doğrulama **sırası kritik**: alg=EdDSA → kid → imza → aud → iat/exp (≤iat+60,
  +5s skew) → **body-hash (bh) nonce'tan ÖNCE** → jti replay. `bh` =
  `base64url(SHA-256(raw body))` (`BodyHashValidator.kt`).
- `signaling-server/.../ServiceAssertion.kt` + `ServiceAccounts.kt` — Ed25519
  scoped assertion, compact format `sc1.<b64url(payload)>.<b64url(sig)>`, ≤120s.
- `bot-api/.../signal/BotServiceTokenMinter.kt` — Ed25519 assertion üretimi.
- **İnceleyici soruları:** HS256 sır entropisi/rotasyonu; Ed25519 raw↔X.509
  dönüşümü (EdDsaJwtVerifier X509_ED25519_PREFIX, satır ~60) doğru mu;
  doğrulama sırası her yolda tutarlı mı (bh-before-nonce iddiası);
  compact-format ayrıştırma injection'a açık mı; skew/exp pencereleri;
  nonce store atomikliği (`NonceStore` Redis SETNX).

**E. Signal Protocol kullanımı (bot)**
- `bot-api/.../signal/SignalEncryptor.kt` — `signal-protocol-java 2.8.1`
  (`org.whispersystems.libsignal`): `SessionBuilder` (X3DH) + `SessionCipher`.
- `bot-api/.../signal/PgSignalProtocolStore.kt` — session/identity/prekey store.
- `bot-api/.../signal/PeerIdentityStore.kt` — TOFU identity pinning
  (`SHA-256` fingerprint, satır 117).
- **İnceleyici soruları:** kütüphane **doğru** mu kullanılıyor (kendi kriptosunu
  uydurmuyor); identity pinning TOFU ilk-kullanımda MITM'e açık mı; session
  record şifreleme (KeyEncryptor) + concurrency (aynı recipient'a paralel
  encrypt ratchet state bozar mı — `RatchetConcurrencyIntegrationTest` var);
  prekey signature doğrulaması yapılıyor mu (X3DH güvenliği buna bağlı).

**F. İstemci tarafı (Flutter) Signal + store**
- `lib/src/crypto/signal_protocol_crypto_service.dart`,
  `libsignal_protocol_store.dart`, `pre_key_manager.dart`,
  `call_crypto_manager.dart`
- **İnceleyici soruları:** private key yalnız Android Keystore'da mı; SQLCipher
  DB anahtar yönetimi; prekey signature; identity change davranışı (safety
  number).

### P2 — Yardımcı / düşük risk
- `TurnCredentialService.kt` — HMAC-SHA1 (RFC 8489 / coturn **protokol
  zorunlu**; SonarQube S4790 false-positive olarak işaretlendi — doğrula).
- `SecretSource.kt` — secret yükleme (dosya izni, boyut, symlink).
- RNG: her yerde `java.security.SecureRandom` (doğrula: `Math.random`/`Random`
  kripto yolunda **yok**).

---

## 3. Her primitif için bilinen-tuzak checklist'i

**AES-GCM:** nonce benzersizliği (random 12B → birthday bound ~2^48 güvenli,
2^32 mesaj eşiği); nonce reuse = katastrofik (auth anahtarı sızar); tag 128-bit;
AAD ile bağlam bağlama; ciphertext üzerinde downgrade/truncation.

**HMAC blind index:** anahtar gizli mi; namespace/purpose ayrımı (cross-domain
çakışma); uzunluk-genişletme HMAC'te yok (OK) ama namespace injection
(`namespace   value`) ayrıştırması güvenli mi.

**RSA-OPRF (özel):** grup üyelik kontrolü; full-domain hash bias; NoPadding
rogue input; private key izolasyonu (HSM); anahtar rotasyonunda token
tutarlılığı.

**Ed25519 / EdDSA:** raw↔SPKI dönüşümü; malleability (Ed25519 non-malleable,
ama cofactor/canonical-S kontrolü kütüphanede mi); imza-öncesi domain
separation.

**JWT:** alg confusion (alg:none, RS↔HS); imza doğrulama claim'lerden önce;
exp/iat/aud/nonce; sabit-zamanlı karşılaştırma (`MessageDigest.isEqual`).

**KDF/anahtar türetme:** `SHA-256(domain||token)` yeterli bir KDF mi yoksa
HKDF gerekir mi; anahtar ayrımı; zeroization (`ByteArray.fill(0)` kullanımı —
`sealUserId` `key.fill(0)` yapıyor, doğrula).

**Sabit-zaman:** OTP/secret/token karşılaştırmaları constant-time mı
(`MessageDigest.isEqual`); OPRF/AEAD dallanması gizli veriye bağlı mı.

---

## 4. Çalıştırılacak açık-kaynak araçlar

Bağımsız inceleyici şunları çalıştırıp bulguları bu brief'e ekleyebilir:

1. **Google Wycheproof** (test vektörleri) — uygulamanın kullandığı **aynı JCA
   provider'a** AES-GCM / RSA / Ed25519 / HMAC vektörlerini besle; bilinen-bug
   ve edge-case'leri yakala. En yüksek değer/maliyet. Öneri: `test/` altına
   `WycheproofKatTest` olarak ekle.
2. **CryptoGuard** (Purdue, Java bytecode) — `signaling-server`/`bot-api` fat
   JAR'ları üzerinde; zayıf IV, ECB, hardcoded key, kötü RNG, sabit tuz taraması.
3. **CogniCrypt `HeadlessCryptoScanner`** (CrySL) — JCA kullanımını CrySL
   kurallarına karşı doğrula.
4. (opsiyonel, ağır) **Tamarin/ProVerif** — directory OPRF + auth protokolü için
   sembolik secrecy/authentication modeli.

> Not: SonarQube taraması zaten yapıldı (0 bug, 0 gerçek vuln; 3 kripto uyarısı
> false-positive işaretlendi — `docs/SONARQUBE_2026-08-25.md`). Bu review onu
> **tekrar etmez**, derinleştirir.

---

## 5. Referans: mevcut kripto testleri (inceleyici bunlara güvenmemeli, doğrulamalı)

- `PrivateDirectoryOprfTest` — OPRF round-trip, seal/open, decoy shape.
- `DirectorySnapshotPaddingTest` — dolgu ayırt-edilemezliği.
- `EdDsaJwtVerifierTest` (20) — JWT tüm ret yolları, bh-before-nonce.
- `ServiceAssertionTest`, `PurposeSeparatedSecretsTest`, `FcmTokenCipherTest`,
  `KeyEncryptorTest`, `BotQueuePrivacyTest`, `PeerIdentityPinIntegrationTest`,
  `RatchetConcurrencyIntegrationTest`, `SignalEncryptorSmokeTest`.

**İnceleyici görevi:** bu testlerin **assertion'larının yeterli** olup
olmadığını sorgula (mutasyon: primitifi boz, test kırmızı mı). Boş/zayıf test
= kapsanmamış kabul et.

---

## 6. Öncelikli inceleme sırası (öneri)

1. **PrivateDirectoryOprf** (özel kripto — en yüksek risk). İstemci unblind'ıyla
   birlikte end-to-end oblivious'luğu ve grup güvenliğini doğrula.
2. **AEAD nonce/AAD** disiplini (ServerPrivacy, BotQueuePrivacy, FcmTokenCipher,
   KeyEncryptor) — nonce reuse ve cross-purpose karışım.
3. **Ed25519 doğrulama zinciri** (EdDsaJwtVerifier, ServiceAssertion) — sıra,
   raw↔SPKI, replay.
4. **Signal kullanımı** (SignalEncryptor + store + TOFU pinning).
5. **Media E2EE anahtar dağıtımı** (call_media_key + group_media_engine).
6. Yardımcılar (TURN, SecretSource, RNG).

---

## 7. Bulgu raporu formatı (her bulgu için)

```
### <Kısa başlık>
- Severity: CRITICAL | HIGH | MEDIUM | LOW | INFO
- Konum: <dosya:satır>
- Sınıf: <örn. nonce-reuse, oblivious-break, alg-confusion, weak-KDF>
- Açıklama: <ne yanlış>
- Somut senaryo: <hangi girdi/durum → hangi kripto garanti bozulur>
- Doğrulama: <PoC / test vektörü / mutasyon adımı>
- Öneri: <somut düzeltme>
- Güven: CONFIRMED | PLAUSIBLE
```

Ek olarak bir **executive summary**: hangi garantiler tutuyor, hangileri
tutmuyor, ve "novel OPRF için harici uzman ISTER mi" kararı.

---

## 8. İnceleyiciye "hazır çalıştır" komutları

```bash
# derle (bulgu doğrulaması için)
cd flutter_securechat/server_hardened
./gradlew :signaling-server:compileKotlin :bot-api:compileKotlin --offline

# mevcut kripto testleri
./gradlew :signaling-server:test --offline --tests '*Oprf*' --tests '*Privacy*' --tests '*Assertion*'
./gradlew :bot-api:test --offline --tests '*EdDsa*' --tests '*KeyEncryptor*' --tests '*Ratchet*'

# fat JAR (statik araçlar icin)
./gradlew :signaling-server:fatJar :bot-api:installDist --offline
```

**Önemli:** üretim `main()` PKCS#11 HSM ister; inceleme için gerekmez.
Kriptografik mantık HSM'den bağımsız (HSM yalnız OPRF private key'i saklar);
inceleyici PKCS#8/software yolunu (`fromPkcs8Environment`) okuyarak aynı
matematiği doğrular.

---

Bu brief + kaynak + testler, bağımsız bir kriptografik incelemeyi tam
yürütmek için yeterlidir. Sonuç: bulgu raporu (§7) + hangi garantiler
kanıtlandı/kanıtlanamadı özeti.
