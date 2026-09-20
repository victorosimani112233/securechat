# Security Assessment Report

**Generated:** 2026-08-25 15:40:49
**Tool:** Strix Claude Code

---
## Executive Summary

The SecureChat Ktor signaling server at http://host.docker.internal:8080 was assessed across its full authenticated and unauthenticated attack surface (HTTP + WebSocket). The result is a strongly hardened service: no high or critical vulnerabilities were found, and every high-value attack attempted — authentication bypass, JWT forgery, authorization/privilege escalation, sender impersonation, injection, IDOR, and denial of service — was correctly defended.

Only two low-severity, defense-in-depth gaps were confirmed: (1) HTTP responses omit standard security headers (nosniff, frame-options/CSP, Referrer-Policy, and no-store caching on sensitive JSON such as TURN credentials); and (2) the /api/v1/auth/refresh endpoint is not rate-limited, unlike the OTP endpoints. Neither is directly exploitable — refresh tokens are opaque and high-entropy, and the API is consumed by a native client — but both should be closed for completeness.

Notably, the server actively demonstrated the security controls this lab was built to validate: JWT signatures are strictly verified (alg:none and weak-secret attacks failed), operator surfaces (/metrics, /ready, /api/v1/version) are cleanly separated from user tokens with no path/header-normalization bypass, WebSocket connections bind userId to the token subject and reject query-string tokens, the server stamps a trustworthy senderId on relayed frames (blocking impersonation), a global 256KB body cap and WS frame/flood limits prevent resource exhaustion, the directory snapshot is padded to a fixed 256 sealed entries (hiding the true user count), and logout immediately revokes the access token.

## Methodology

Black-box + credentialed testing using curl, Python (requests/aiohttp for HTTP and raw WebSocket), and jwt_tool. Phases: (1) recon/fingerprinting and endpoint enumeration; (2) targeted content discovery (swagger/openapi/actuator/.git/.env — none present); (3) JWT attacks — alg:none/None/NONE, empty signature, key confusion, and dictionary crack of the HS256 secret (common + app-specific + targeted lists); (4) AuthZ/privilege-separation testing across operator vs user tokens, plus path-normalization and header-spoofing bypass attempts on operator endpoints; (5) WebSocket protocol reverse-engineering and abuse — query-string auth, userId/sub mismatch, senderId/timestamp override, unknown/server-only/presence frame injection, oversized frames, and message flooding; (6) injection testing (JSON body, path params, malformed JSON) checking for stack-trace/SQL behavior; (7) DoS testing — global body-size cap and per-endpoint rate limiting (OTP request/verify, refresh); (8) info-disclosure review — headers, CORS, error verbosity, directory-snapshot count leakage, TURN/version leakage; (9) session-management — logout access-token revocation. All testing was confined to host.docker.internal:8080.

## Technical Analysis

AuthN: HS256 JWT, signature strictly verified; forged alg-confusion and unsigned tokens rejected with "Gecersiz veya expired token"; signing secret resisted dictionary attack. AuthZ: two distinct auth realms (static operator bearer vs per-user JWT) with no cross-acceptance; operator endpoints returned 401/404 to every normalization trick (//, /./, %2e, %00, ..;/, case, /api/v1/../) and to X-Forwarded-*/X-Original-URL header spoofing. WebSocket (/ws): handshake succeeds then server closes with 1008 unless the Authorization header carries a valid JWT whose sub equals the userId query param; query-string token variants all closed 1008. On the message channel, the server discards client-supplied senderId/timestamp and re-stamps them from the authenticated session, eliminating impersonation; unknown and presence/subscribe frame types are silently dropped (no server-frame injection or presence oracle); frames >256KB close with 1009 and sustained flooding closes with 1008. Injection: path parameters containing SQL metacharacters behaved identically to valid UUIDs (parametrized access), and malformed JSON produced clean typed errors (invalid_json / invalid_directory_json) with no stack traces or framework leakage. DoS resistance: a global 256KB body cap returns 413 body_too_large in ~10ms across all routes (no unbounded read), and OTP endpoints throttle to 429. Info-disclosure posture: no Server header, no CORS exposure, directory snapshot padded to 256 sealed/blinded entries (user count concealed), TURN credentials are standard time-limited REST creds. Session mgmt: logout blacklists the token so subsequent authenticated calls return 401. Residual gaps: absent response security headers and absent rate limiting on /auth/refresh (both Low).

## Recommendations

1) LOW — Add response security headers via Ktor DefaultHeaders: X-Content-Type-Options: nosniff, X-Frame-Options: DENY (or CSP frame-ancestors 'none'), Referrer-Policy: no-referrer, and Cache-Control: no-store on sensitive authenticated JSON (ice/config, directory/snapshot, prekeys); add HSTS once TLS terminates in production. 2) LOW — Apply the OTP endpoints' per-IP/per-identity rate limiting to /api/v1/auth/refresh (and other unauthenticated POST routes), coupling it with the existing refresh-reuse detection. 3) Maintain the strong controls already in place: strict JWT verification, operator/user realm separation, WebSocket userId-to-sub binding, server-side senderId stamping, global body caps, WS frame/flood limits, directory padding, and immediate logout revocation. No high/critical remediation is required based on this assessment.

---

**Report Completed:** 2026-08-25 15:41:52
|---|---|
| GET /health, / | public | 200 `{"status":"ok"}` |
| GET /api/v1/directory/config | public | 200 — RSA modulus + keyId + batchSize:256 (public OPRF params, by design) |
| GET /metrics, /ready, /api/v1/version | operator bearer | 401 without bearer; 200 with metrics bearer |
| GET /api/v1/directory/snapshot | JWT | 200 — exactly **256** entries (padded to batchSize), sealed userIds + blinded labels |
| POST /api/v1/directory/evaluate | JWT | OPRF; strict validation (`invalid_directory_batch`/`invalid_directory_json`) |
| POST /api/v1/otp/request / verify | none | rate-limited (429); email disabled in lab (503) |
| POST /api/v1/users/register | grant | 403 without valid registrationToken |
| POST /api/v1/auth/refresh | none | 401 on bad token |
| POST /api/v1/auth/logout, /account/delete, /prekeys/upload, /fcm/register | JWT | strict validation |
| GET /api/v1/users/{id}/prekeys | JWT | 404 when no bundle |
| GET /api/v1/ice/config | JWT | 200 — time-limited TURN REST creds (by design) |
| GET /api/v1/sfu/room/{groupId} | JWT | 404 without active call |
| WS /ws?userId=<uuid> | JWT header | relay of `message` frames |

### Security controls CONFIRMED EFFECTIVE (attempted bypasses failed)
- **JWT crypto:** HS256; `alg:none`/`None`/`NONE` rejected; empty-sig rejected; weak-secret dictionary (common + app-specific + targeted) did NOT crack the signing key. Signature strictly verified.
- **AuthZ / privilege separation:** user JWT cannot reach operator surfaces (401); operator (metrics) bearer cannot reach user surfaces (401). No cross-use.
- **Operator-endpoint bypass:** path tricks (`//metrics`, `/./metrics`, `/%2e/metrics`, `/metrics%00`, `/metrics..;/`, case variants, `/api/v1/../metrics`) all 401/404 — never 200. Header spoofing (X-Forwarded-For, X-Real-IP, X-Original-URL, X-Forwarded-Host, X-Forwarded-Authorization) all 401.
- **WebSocket:** userId query param must equal token `sub` (mismatch → close 1008); query-string token (`?token=`/`?access_token=`/`?jwt=`) does NOT authenticate (1008) — only `Authorization` header works; no-auth → 1008.
- **WS message integrity:** server **overrides** client-supplied `senderId` and `timestamp` with the authenticated `sub` + server time → **no sender impersonation**. Unknown/`presence`/`subscribe`/server-only frame types silently ignored → no arbitrary presence-subscribe or server-frame injection. Invalid JSON → socket closed. Oversized frame (>256KB) → close 1009. Message flood → close 1008 (rate limit). Single-session enforcement (new connection supersedes old).
- **DoS caps:** global 256KB request-body cap enforced on ALL endpoints (2MB → 413 `body_too_large` in ~0.01s, no unbounded read); evaluate has dedicated `directory_body_too_large`.
- **Rate limiting:** OTP request → 429 after ~3; OTP verify → 429 after ~19 (brute mitigated).
- **Injection:** JSON parse errors return clean `invalid_json` (no stack traces); path params with SQL metacharacters handled identically to valid UUIDs (parametrized).
- **Session invalidation:** `logout` immediately revokes the access token (post-logout requests → 401) — jti/epc revocation working.
- **Privacy:** directory snapshot padded to fixed 256 & sealed → true user count NOT leaked. No permissive CORS (preflight 405, no ACAO). No swagger/openapi/actuator/.git/.env exposed.

**Overall: the server is strongly hardened.** No auth bypass, injection, impersonation, IDOR, or DoS was achievable. Only two low-severity defense-in-depth gaps confirmed (below).
## Findings

### Missing HTTP Security Response Headers

**Severity:** LOW (3.1)
**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N`
**Target:** http://host.docker.internal:8080 (all endpoints)

**Method:** GET

#### Description
All HTTP responses (public and authenticated) omit standard hardening headers: X-Content-Type-Options, X-Frame-Options, Content-Security-Policy, Referrer-Policy, Strict-Transport-Security, and Cache-Control/Pragma on sensitive JSON (e.g., directory snapshot, ice/config TURN credentials).

#### Impact
Defense-in-depth gap. For a JSON API consumed by a native mobile client the practical risk is limited, but absent no-store caching, sensitive responses (TURN credentials, directory snapshot) may be retained by intermediaries/proxies; absent nosniff/frame/CSP any future web-facing surface would be exposed to MIME-sniffing and clickjacking. HSTS absence is moot only because the lab runs plain HTTP.

#### Technical Analysis
Response headers observed on /health: only Content-Length, Content-Type, Connection. No Server header (good). No X-Content-Type-Options: nosniff, no X-Frame-Options/CSP frame-ancestors, no Referrer-Policy, no Cache-Control: no-store on /api/v1/ice/config (which returns time-limited TURN credentials) or /api/v1/directory/snapshot. CORS is not permissive (preflight → 405, no Access-Control-Allow-Origin), which partially mitigates cross-origin concerns.

#### Proof of Concept
Capture response headers of any endpoint and observe the absence of the hardening headers.

```
$ curl -s -D - -o /dev/null http://host.docker.internal:8080/health
HTTP/1.1 200 OK
Content-Length: 15
Content-Type: application/json
Connection: keep-alive
# No X-Content-Type-Options / X-Frame-Options / CSP / Referrer-Policy / Cache-Control
```

#### Remediation
Add a Ktor DefaultHeaders/response interceptor emitting: X-Content-Type-Options: nosniff; X-Frame-Options: DENY (or CSP frame-ancestors 'none'); Referrer-Policy: no-referrer; Cache-Control: no-store on authenticated/sensitive JSON responses (ice/config, directory/snapshot, prekeys). Add Strict-Transport-Security once TLS is terminated in production.

---

### No Rate Limiting on /api/v1/auth/refresh (Defense-in-Depth Gap)

**Severity:** LOW (3.7)
**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:N/A:L`
**Target:** http://host.docker.internal:8080/api/v1/auth/refresh

**Method:** POST

#### Description
The token-refresh endpoint applies no rate limiting: 40 consecutive requests with invalid refresh tokens all returned 401 with no 429 throttling, in contrast to the OTP endpoints which throttle to 429 after a few attempts.

#### Impact
Low. Refresh tokens are opaque, server-issued, and high-entropy, so online brute force is computationally infeasible even without throttling; the server also tracks refresh-token reuse (AUTH_REFRESH_REUSE security-event counter observed in /metrics). The residual risk is that an unthrottled endpoint allows unlimited credential-stuffing / token-guessing attempts and consumes resources. No account lockout or resource exhaustion was achieved.

#### Technical Analysis
Burst of 40 POSTs with distinct junk refreshToken values yielded status distribution {401: 40} — no 429 observed. OTP endpoints under the same test showed throttling: /api/v1/otp/request {503:3, 429:27}; /api/v1/otp/verify {401:19, 429:21}. The inconsistency indicates the refresh route is missing the throttling middleware the OTP routes have. Body-size cap (256KB → 413) still applies, so oversized-body DoS is not possible here.

#### Proof of Concept
Send many refresh attempts and observe no 429 is ever returned.

```
import requests,json
T="http://host.docker.internal:8080"
codes={}
for i in range(40):
    r=requests.post(T+"/api/v1/auth/refresh",
        headers={"Content-Type":"application/json"},
        data=json.dumps({"refreshToken":f"junk{i}"}),timeout=10)
    codes[r.status_code]=codes.get(r.status_code,0)+1
print(codes)   # -> {401: 40}  (no 429 throttling)
```

#### Remediation
Apply the same per-IP/per-identity rate limiting used on the OTP endpoints to /api/v1/auth/refresh (and other unauthenticated POST routes). Combine with the existing refresh-reuse detection to lock a token family on repeated failures.

---
