# SonarQube Analizi — Hardened Server (2026-08-25)

Yerel SonarQube (community 26.8, kod disari gonderilmedi) + jacoco coverage
import. `sonar-project.properties` iki modulun Kotlin main+test kaynaklari.

## Ozet (triyaj sonrasi)

| Metrik | Deger | Rating |
|---|---|---|
| Bugs | 0 | A |
| Vulnerabilities | 0 (3 false-positive triyaj edildi) | A |
| Security Hotspots | 0 | A |
| Code Smells | 50 | A (maintainability) |
| Coverage | %65.2 | — |
| Duplication | %1.4 | — |
| Satir (ncloc) | 9.441 | — |

## 3 "vulnerability" — hepsi false-positive

SonarQube baglam-korumasiz kripto kurallari uc satiri isaretledi; ucu de
bilincli/protokol-zorunlu tasarim, gercek zafiyet degil. SonarQube'de
`falsepositive` olarak gerekce ile isaretlendi:

1. **PrivateDirectoryOprf.kt:188,190 — S5542 "secure padding"** — bu bir
   blind-RSA **OPRF**; sifreleme degil, ham grup islemi. OAEP padding OPRF
   matematigini bozardi. Kod yorumu zaten aciklar.
2. **TurnCredentialService.kt:156 — S4790 "weak hash"** — TURN REST
   credential mekanizmasi (coturn use-auth-secret / RFC 8489) protokol
   geregi HMAC-SHA1'dir; HMAC-SHA1 MAC olarak guvenli, coturn uyumu icin
   zorunlu.

Kripto DEGISTIRILMEDI (OPRF + TURN uyumu bozulurdu).

## 50 code smell — maintainability (rating hala A)

En cok: 14x bos blok (S108, cogu best-effort `catch`), 5x gereksiz `!!`
(S6619), 3x kullanilmayan `ts` degiskeni (S1481), birkac yuksek cognitive
complexity (S3776, buyuk route handler'lar). Guvenlik degil; opsiyonel
temizlik.

Dashboard: http://localhost:9000 (proje: securechat-server-hardened).

## Temizlik + triyaj sonrasi (guncel)

| Metrik | Deger | Rating |
|---|---|---|
| Bugs | 0 | A |
| Vulnerabilities | 0 (3 FP triyaj edildi) | A |
| Security Hotspots | 0 | A |
| Code Smells (acik) | 25 | A |
| Coverage | ~%64 | — |

Temizlenen (gercek smell): 3 kullanilmayan `ts` degiskeni (S1481), 14 bos
best-effort `catch` blogu yoruma cevrildi (S108), 2 idiom (throw->error,
if-throw->check; S6532). Kalan 25 acik: duplicated literal (S1192),
cognitive complexity (S3776, buyuk route handler'lar — guvenlik-kritik,
refactor riskli), 1 fail-closed `else true` (dogru).

False-positive isaretlenen: 6x S6619 (`!!`/`?:`) — Kotlin smart-cast
`fieldsValid` val sinirindan propagate olmadigi icin `!!` derleme icin
GEREKLI (compile ile dogrulandi); 3x kripto (blind-RSA OPRF NoPadding,
protokol-zorunlu TURN HMAC-SHA1).
