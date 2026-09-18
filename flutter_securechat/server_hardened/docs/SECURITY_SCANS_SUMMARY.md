# Güvenlik Taramaları Ortak Raporu — Strix + SonarQube

**Hedef:** SecureChat hardened server (`signaling-server` + `bot-api`, Kotlin/Ktor).
**Tarih:** 2026-08-25 (taramalar), bu belge birleşik özet.
**Yöntemler:** Strix (AI pentest — 3 mod) + SonarQube (statik analiz). Kod
dışarı gönderilmedi; hepsi yerel.

> Ayrı belgeler: `STRIX_SCAN_2026-08-25.md` (standart), `STRIX_WHITEBOX_2026-08-25.md`,
> `STRIX_DEEP_2026-08-25.md` (+ `STRIX_DEEP_RECON`), `SONARQUBE_2026-08-25.md`.
> Bağımsız kriptografik inceleme ayrıdır: `CRYPTO_REVIEW_2026-08-26.md`.

---

## 1. Sonuç özeti

| Araç / mod | Kapsam | Gerçek bulgu | Durum |
|---|---|---|---|
| Strix — **standart** (blackbox) | Canlı sunucuya aktif pentest | 1 (LOW) | ✅ düzeltildi |
| Strix — **whitebox** (kaynak) | 160 dosya kod incelemesi | 3 (2×MED, 1×LOW) | ✅ hepsi düzeltildi |
| Strix — **deep** (blackbox, interaktif) | Derin aktif pentest | 2 (MED, LOW) | ✅ hepsi düzeltildi |
| **SonarQube** (statik) | ~9.4k satır Kotlin | 0 gerçek (3 FP) | ✅ triyaj + temizlik |

**Toplam:** Strix'ten **6 gerçek bulgu** — hepsi kapatıldı, regresyon testi + (kritik
olanlarda) mutasyon doğrulaması eklendi. SonarQube **0 gerçek zafiyet** (3 uyarı
false-positive). Kırılamayan saldırılar aşağıda listeli.

Mevcut doğrulama (bu belge yazılırken): **520 Kotlin + 292 Flutter testi**, 0 hata,
coverage %76 satır / %56.5 dal, coverage-gate PASS, deployment audit PASS.

---

## 2. Strix — standart mod (blackbox, canlı hedef)

Kali sandbox konteynerinden `http://host.docker.internal:8080` (yerel dummy)
üzerine tam saldırı ağacı: JWT forgery, operatör-endpoint auth bypass,
WebSocket auth/impersonation, injection, rate-limit/DoS, oversized body/frame,
info disclosure, CORS/Host abuse, nuclei 7281 template + hedefli probing.

**Bulgu (tek):**
| # | Başlık | Severity | Durum |
|---|---|---|---|
| S1 | HTTP güvenlik başlıkları eksik (nosniff, X-Frame-Options, CSP, Referrer-Policy, Cache-Control) | LOW (3.1) | ✅ `SecurityHeaders` Ktor plugin eklendi; 3 e2e test |

**Kırılamayan** (denendi, savunuldu): operatör-endpoint gating, JWT `alg:none`
+ zayıf-sır crack (hashcat rockyou), WS query-token reddi + `userId==sub` +
tek-oturum, gövde tavanı 413 (okuma sınırı), WS frame 512KB → 1009, OTP
rate-limit, strict JSON (stack-trace yok), snapshot 256-padding, CORS yok,
swagger/git/env/admin yüzeyi yok.

---

## 3. Strix — whitebox mod (kaynak kodu incelemesi)

Kaynak (`.kt/.sql/...`, 214 dosya / ~24k satır) sandbox'a kopyalandı; nested ajan
semgrep + doğrudan okuma yaptı. Enjeksiyon/RCE/deserialization/SSRF/auth-bypass/
IDOR **bulunmadı**; SQL tamamen parametrize.

**Bulgular (3) — hepsi prekey/revocation:**
| # | Başlık | Severity | Fix | Durum |
|---|---|---|---|---|
| W1 | `GET /users/{id}/prekeys` rate-limit yok → hedefin one-time prekey havuzu boşaltılıp X3DH forward-secrecy düşürülebilir | MEDIUM (5.4) | `prekey_fetch` limit (120/saat) | ✅ + mutasyon doğrulaması |
| W2 | `/prekeys/refresh` validation atlıyordu + yazma yolları limitsiz/tavansız → `one_time_prekeys` sınırsız büyüme | MEDIUM (5.0) | refresh validation, `prekey_write` limit, hesap başına 1000 tavanı | ✅ + test |
| W3 | 10s process-yerel epoch cache → yatay ölçeklemede iptal edilmiş token diğer instance'larda ~10s geçerli | LOW (3.1) | Redis pub/sub cross-instance invalidation + subscriber | ✅ + 4 gerçek-Redis test |

---

## 4. Strix — deep mod (blackbox, interaktif)

İlk denemelerde nested ajan (Opus) Claude'un gerçek-zamanlı siber korumasına
(`[cyber]`) takıldı; **interaktif TTY**'de tam koştu. Chained/logic flaw, race,
JWT revocation edge-case, WS state-machine, OPRF enumeration test edildi.

**Bulgular (2):**
| # | Başlık | Severity | Fix | Durum |
|---|---|---|---|---|
| D1 | `POST /auth/refresh` tek rate-limit'siz credential endpoint'iydi (120/120 istek 401, 0×429) | MEDIUM (4.8) | `auth_refresh` limit (30/10dk per IP) | ✅ + test |
| D2 | Tamamlayıcı izolasyon başlıkları eksik (Permissions-Policy, COOP/COEP/CORP, HSTS) | LOW (3.1) | `SecurityHeaders`'a eklendi; HSTS reverse-proxy (TLS terminator) | ✅ + test |

Raporun "black-box'ta test edilemedi" dediği yüzeyler (WS per-message authz,
senderId spoof, prekey/fcm mass-assignment) whitebox testlerinde zaten kapalı —
ikinci lab kimliği alınamadığı için black-box'ta gözlemlenememiş.

---

## 5. SonarQube (statik analiz)

Yerel community 26.8, jacoco coverage import. Kotlin main+test, ~9.4k satır.

| Metrik | İlk | Triyaj + temizlik sonrası |
|---|---|---|
| Bugs | 0 (A) | **0 (A)** |
| Vulnerabilities | 3 | **0 (A)** — 3 false-positive |
| Security Hotspots | 0 | **0 (A)** |
| Code Smells (açık) | 50 | **25 (A)** |
| Coverage | ~%65 | ~%64 (Sonar sayımı) |

**3 "vulnerability" — hepsi false-positive** (kripto değiştirilmedi, bozardı):
- `PrivateDirectoryOprf` (×2, S5542): blind-RSA **OPRF** için `NoPadding`
  bilinçli — ham grup işlemi, padding OPRF'yi bozar.
- `TurnCredentialService` (S4790): TURN REST (coturn/RFC 8489) **protokol
  gereği** HMAC-SHA1; MAC olarak güvenli.
- Ayrıca 6× S6619 (`!!`) false-positive: compile kanıtladı ki Kotlin smart-cast
  propagate olmuyor, `!!` gerekli.

**Temizlenen gerçek smell'ler:** 3 dead `ts`, 14 boş best-effort `catch`
yoruma, 2 idiom (throw→error, if-throw→check). Kalan 25: duplicated-literal +
cognitive-complexity (maintainability, rating A — güvenlik değil).

---

## 6. Genel değerlendirme

Üç bağımsız Strix modu + SonarQube aynı yöne işaret etti: **kod güçlü
sertleştirilmiş.** Gerçek açıklar azdı (6, hepsi prekey/revocation/header
sınıfı), hepsi kapatıldı ve regresyon testine bağlandı. Statik analiz 0 gerçek
zafiyet gördü. Yaygın sınıflar (auth bypass, injection, IDOR, DoS, impersonation)
kapalı.

**Sınır:** Bu iki araç **implementasyon/deploy** katmanını denetler; **protokol
seviyesi kripto tasarımı** ayrı bağımsız incelemenin konusudur
(`CRYPTO_REVIEW_2026-08-26.md` — orada açık CRITICAL/HIGH mimari bulgular var,
örn. tek-sunuculu OPRF operatöre karşı oblivious değil). Strix + SonarQube o
mimari kararları kapsamaz.
