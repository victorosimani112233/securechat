# Security Assessment Report

**Generated:** 2026-08-25 16:14:11
**Tool:** Strix Claude Code

---

## Reconnaissance — SecureChat Ktor Signaling Server (http://host.docker.internal:8080)

**Target:** Ktor (Kotlin/JVM) HTTP + WebSocket signaling server. JVM confirmed via `/metrics` (Micrometer/Prometheus `jvm_*` gauges, `system_cpu_count 20`). No `Server` header leak. Error messages are mixed English/Turkish.

**Security headers (present on all responses):** `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. HSTS absent (plain-HTTP lab, out of scope).

**Endpoint auth matrix (unauthenticated probes):**
| Endpoint | No auth | Notes |
|---|---|---|
| GET /health | 200 `{"status":"ok"}` | public liveness |
| GET /ready | 401 | operator-only; 200 with metrics bearer `{"status":"ok","database":"ok","redis":"ok","privacy":"ok","uptime_sec":...}` |
| GET /metrics | 401 | operator-only; 200 with metrics bearer (JVM+custom counters). No secret leak |
| GET /api/v1/version | 401 | operator-only; 200 with metrics bearer `{"commit":"unknown","builtAt":"unknown","migrationTarget":"V19"}`. **User access-token does NOT reach it** (401) — authZ separation holds |
| GET /api/v1/directory/config | 200 | public by design (OPRF `keyId`, RSA `modulus`, `exponent`, `batchSize:256`) |
| GET /api/v1/directory/snapshot | 401 | JWT required |
| POST /api/v1/otp/request | 503 `{"sent":false,"message":"E-posta gonderilemedi"}` | mail transport down in lab |
| POST /api/v1/otp/verify | 401 `{"verified":false}` | no info leak on wrong code |
| POST /api/v1/users/register | 403 `{"error":"...registration token"}` | grant required |
| POST /api/v1/auth/refresh | 401 `{"error":"Gecersiz refresh token"}` | |

**JWT analysis:** Provided access token is HS256, in validity window (iat 2026-08-25 12:25:57Z, exp 13:25:57Z; server clock ~13:10Z). Yet **every** authenticated endpoint + WS rejects it as "Gecersiz token / Gecersiz veya expired token". `alg:none` forgery rejected. Common-secret HMAC guesses failed. Conclusion: this running instance's JWT signing secret differs from the secret that minted the supplied token (ephemeral/rotated per boot, or seeded-user DB mismatch). **Net effect: the authenticated attack surface (IDOR, prekeys, directory evaluate/snapshot, WS data-plane spoofing, sfu/ice/fcm, logout, account delete) is NOT reachable with the given credentials on this instance.** Operator (metrics-bearer) auth works, confirming the instance matches the provided config otherwise.

**WebSocket /ws behavior:** HTTP upgrade returns `101` unconditionally (even no-auth / no-userId / bad token), then the server authenticates on-channel and closes with `1008`:
- no token → `Token gerekli`
- bad/foreign token → `Gecersiz token`
- token in query string (`?token=`) → `Token yalniz Authorization header ile gonderilir` (query-string token explicitly refused)
- missing userId → `userId gerekli`

So WS auth is enforced; a query-string token canNOT authenticate the socket (focus question answered: no).

> **Analysis Note** (16:16:07): Connectivity check to sandbox tool server.

## Progress notes (mid-scan) — unauthenticated surface hardening

**Input validation / DoS controls (all confirmed defensive positives):**
- Request body size capped early: ~100KB body on `/api/v1/otp/request` and `/api/v1/users/register` already returns `413 {"error":"body_too_large"}`. Even 5MB bodies rejected in ~20ms → **no unbounded body read**; server does not buffer oversized payloads.
- Malformed JSON, wrong types (number/array/bool/null for expected string), empty body, deep nesting (80-level) → clean `400 {"error":"invalid_json"}`. **No stack traces, no 5xx** leaked anywhere.
- Rate limiting present on multiple layers:
  - `/api/v1/otp/request` and `/api/v1/otp/verify`: after ~19 requests in a short window → `429 {"error":"Cok fazla istek"}`. OTP brute-force is throttled.
  - `/api/v1/users/register`: separate limiter → `429 {"error":"Rate limit asildi","retryAfter":"<sec>"}` (retryAfter ~55min observed).
- Mass-assignment probe: register with extra `isAdmin:true`,`role:admin` fields → ignored; grant check (403) runs first. Cannot escalate without a valid registration grant.
- Content-Type not strictly enforced (text/plain body still JSON-parsed) — cosmetic, not exploitable.

**Pending (interrupted by sandbox outage):** IP-header rate-limit-bypass test (X-Forwarded-For / X-Real-IP / Forwarded spoofing to reset the 429 window), ffuf content-discovery result review, nuclei scan, HTTP-method matrix, Host-header handling.

**Overall so far:** Server is notably hardened — operator/JWT/WS auth separation intact, no injection/stack-trace leakage, DoS caps + rate limits enforced. No confirmed vulnerability yet; provided user JWT is not valid against this running instance, so authenticated data-plane (IDOR/prekeys/WS spoofing) remains untested for lack of a working token.
