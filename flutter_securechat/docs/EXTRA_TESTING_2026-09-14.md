# Ek Test Setleri — Statik / Yük / Chaos / Fuzz (2026-09-14)

Kripto KAT (Wycheproof) ve mevcut suite'e ek olarak dört yüksek-değer test
seti çalıştırıldı. Hepsi yerel; kod dışarı gönderilmedi.

## 1. Statik analiz (detekt + SpotBugs/FindSecBugs)
- **detekt** (kaynak): 590 sorun — **hepsi stil/complexity** (MagicNumber 283,
  WildcardImport 68, ReturnCount…). Kripto param'lari (`GCMParameterSpec(128)`)
  yorumlu bilincli. **Güvenlik bulgusu 0.**
- **SpotBugs + FindSecBugs** (bytecode, güvenlik kategorisi):
  - signaling: 2× `RSA_NO_PADDING` (OPRF — SonarQube'de zaten FP triyaj), 1×
    `PATH_TRAVERSAL_IN` (Firebase config yolu operatör env'inden, kullanıcı
    girdisi değil = FP), 39× `CRLF_INJECTION_LOGS`.
  - bot-api: 7× `CRLF_INJECTION_LOGS`.
  - **CRLF loglarinin hepsi doğrulandı: sayı/boolean/exception-sınıf-adı/config
    logluyor — kullanıcı girdisi yok, log injection yok.**
  - **Gerçek güvenlik bulgusu: 0** (SonarQube ile tutarlı).

## 2. Yük/stres testi (k6, dummy'ye karşı)
50 VU HTTP + 200 iter/s auth/refresh flood + 30 VU WS-auth, dummy `:8090`.
- **1.87M check, %100 başarılı.** 62.316 req/s. p95 = 1.91ms, max 30ms. 5xx yok,
  takılma yok, 0 interrupted.
- **Rate limiter flood altında doğru tetikledi:** 4001× `429` (auth/refresh).
- **WS auth eşzamanlılıkta hepsini reddetti:** 150/150 (kimliksiz → 1008/1000).
- Threshold'lar geçti (p95<500ms, checks>%95).

## 3. Chaos / fail-closed (Redis partition)
Dummy'nin Redis konteyneri `docker pause` (partition simülasyonu):
- `health` (liveness) = **200** — gereksiz restart yok.
- `ready` (readiness) = **not-ready** — degradasyon yansıyor.
- `otp/request` = **429** → **rate limiter fail-CLOSED** (Redis'i öldüren
  saldırgan rate-limit'i ATLAYAMIYOR). Kod: `RateLimiter.consume` catch →
  `false`.
- `unpause` sonrası `ready` = **200** — temiz kurtarma.
- Operasyonel not (güvenlik değil): `/ready` Redis donunca hızlı 503 yerine
  timeout'a giriyor; kısa Redis-timeout eklenebilir.

## 4. Fuzzing (Jazzer, coverage-guided)
Untrusted-input parser'lar (`MessageTypes.extract` WS-frame regex,
`ClientAddress.parseTrusted/isTrustedProxy/resolve` XFF/CIDR — production'da
HTTP header'dan gelir):
- **1.093.982 mutasyon input, 91 saniye, 0 crash.** Uncaught exception yok,
  ReDoS/hang yok, OOM yok. IPv6 (`::`,`::0`) dahil IP-parse dalları kapsandı.
- Harness: `scratchpad/fuzz/FuzzParsers.java`.

## 5. Lincheck (linearizability) — PASS
`org.jetbrains.kotlinx:lincheck:2.34` test dep eklendi.
`GroupCallSessionStore` JVM-içi concurrent yapısı (per-group `synchronized`,
kapasite invaryantı) linearizability açısından doğrulandı:
- **Model-checking** (60 iterasyon, 3 thread × 3 aktör): tüm serpiştirmeler
  keşfedildi, hepsi linearizable.
- **Stress** (30 iterasyon, gerçek thread'ler): linearizable.
- **Mutasyon doğrulaması:** `synchronized` bloğu kaldırılınca Lincheck
  karşı-örnek üretti (`LincheckAssertionError: Invalid execution results`) —
  lock'un önlediği eşzamanlı kapasite-aşımı/kayıp-güncelleme yarışını yakalar.
  Orijinal geri yüklendi.

> Not: Redis-Lua / Postgres-CAS atomik iddiaları (rate-limiter, idempotency,
> prekey consume, refresh rotation) JVM-dışı olduğu için Lincheck kapsamı
> DIŞINDA — onlar zaten executor-tabanlı eşzamanlılık entegrasyon testleriyle
> (gerçek Redis/PG) kapsandı.

---
**Özet:** 4 dinamik/statik set çalıştı, hepsi PASS, **0 yeni güvenlik
bulgusu.** Fail-closed davranış (Redis partition), yük dayanıklılığı (62k
req/s), parser sağlamlığı (1.1M fuzz input) ve JVM concurrency linearizability
(mutasyon-doğrulamalı) kanıtlandı.

**Test toplamı:** 1330 Kotlin testi (811 Wycheproof KAT + 2 Lincheck + baz),
0 hata.
