# Security Assessment Report

**Generated:** 2026-08-25 16:27:54
**Tool:** Strix Claude Code

---

## Reconnaissance

**Target:** SecureChat hardened server (Kotlin/Ktor multi-module), whitebox source review at `/workspace/wb-src`.

**Modules:**
- `signaling-server/` — HTTP + WebSocket signaling: auth (JWT/OTP), directory OPRF, prekeys, group calls, Janus SFU orchestration, offline queues, FCM push. ~50 Kotlin src files.
- `bot-api/` — send-only bot API: EdDSA JWT auth, rate limit, idempotency, Signal encryption, admin surface. ~45 Kotlin src files.
- `deploy/` — compose, reverse-proxy, SBOM/SCA gate, Dockerfiles.
- `*/src/main/resources/db/migration/` — Flyway V1–V19 SQL.

**Stack:** Kotlin 1.9.22, Ktor 2.3.7, Postgres (HikariCP/JDBC 42.7.3), Jedis 5.1.2 (Redis), Flyway 9.22.3, Nimbus JOSE JWT 9.37.3, libsignal-client 0.40.0, junixsocket 2.9.0, Micrometer.

Total ~24k lines Kotlin across 214 files. Design is explicitly privacy-hardened (blind indexes, OPRF directory, sealed queues, purpose-separated secrets, fail-closed startup). Review focus: authN/authZ correctness, crypto/purpose separation, SQL/log injection, TOCTOU/atomicity, DoS/input caps, deployment hardening.

> **Note [findings]** - Whitebox review progress + candidates: Reviewed core: AuthService (HS256, epoch+typ enforced, solid), HttpRoutes (bounded bodies, requireAuth/requirePrincipal), WebSocketRoutes (senderId server-enforced, typed frames), crypto (GCM random n...

## Findings

### One-time prekey exhaustion: GET /api/v1/users/{userId}/prekeys has no rate limit (X3DH forward-secrecy degradation + prekey-pool DoS)

**Severity:** MEDIUM (5.4)
**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:L`
**Target:** signaling-server GET /api/v1/users/{userId}/prekeys
**Endpoint:** /api/v1/users/{userId}/prekeys
**Method:** GET

#### Description
The prekey bundle fetch endpoint atomically consumes (deletes) one of the target user's one-time prekeys on every call, but — unlike almost every other authenticated endpoint in the service — it enforces no rate limit and no per-caller/per-target quota. Any authenticated principal (a normal user access token, or the bot service account holding a `prekey.fetch` service assertion) that knows a victim's account UUID can drain the victim's entire one-time prekey pool with a tight request loop.

#### Impact
Once a victim's one-time prekeys are exhausted, `fetchBundle` returns a bundle with `oneTimePreKey = null` and every new initiator establishes an X3DH session against only the victim's signed prekey. This removes the per-session one-time-prekey contribution to the X3DH handshake, degrading the forward-secrecy / replay-resistance guarantee for all new sessions to that victim until the victim's client happens to re-upload (which is client-driven and may be delayed while offline). It is also a targeted availability attack on the victim's prekey pool. Real Signal-style servers rate-limit prekey fetches precisely to prevent this. Requires only a valid low-privilege token and knowledge of the target UUID (obtained legitimately from the directory or any prior conversation).

#### Technical Analysis
HttpRoutes.kt:736-762 — the handler calls `requirePrincipal(call, serviceScope = ServiceAssertion.Scope.PREKEY_FETCH)` then `PreKeyStore.fetchBundle(targetUserId)` with NO `RateLimiter.allow(...)` call anywhere in the block. Contrast with every rate-limited route (directory_evaluate, directory_snapshot, ice_config, otp_*, users_register, ws_*): grep confirms the only RateLimiter call sites in HttpRoutes are lines 336/377/397/422/480/501/663 — none for the prekey routes.

PreKeyStore.fetchBundle (PreKeyStore.kt:262-316) unconditionally runs, per call, the atomic consume:
  WITH next_key AS (SELECT id FROM one_time_prekeys WHERE user_id=?::uuid ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
  DELETE FROM one_time_prekeys USING next_key WHERE one_time_prekeys.id = next_key.id RETURNING key_id, public_key
There is no "peek" path and no per-target daily quota (contrast DirectoryQuota, which exists specifically to survive Redis loss for the directory endpoints). So N sequential fetches delete N one-time prekeys. With MAX_ONE_TIME_PREKEYS=200 per upload and a typical pool of ~100, a few hundred requests exhaust it. The signed prekey is then reused for every subsequent initiator.

Authorization is not a mitigation: fetch is intended to be callable by any counterparty (that is normal for prekey distribution), so the missing control is rate/quota, not authz.

#### Proof of Concept
Authenticated attacker repeatedly fetches a known victim UUID's bundle until oneTimePreKey stops being returned, proving the pool was drained.

```
#!/usr/bin/env bash
# ATTACKER_TOKEN = any valid access token; VICTIM = target account UUID
BASE="https://securechat.example"
VICTIM="11111111-1111-1111-8111-111111111111"
drained=0
for i in $(seq 1 500); do
  body=$(curl -s -H "Authorization: Bearer $ATTACKER_TOKEN" \
              "$BASE/api/v1/users/$VICTIM/prekeys")
  # once the pool is empty the JSON no longer contains an oneTimePreKey object
  if ! echo "$body" | grep -q '"oneTimePreKey"'; then
    echo "victim one-time prekeys exhausted after $i fetches"; drained=1; break
  fi
done
# From here, every new session initiator receives oneTimePreKey=null and
# performs X3DH against the shared signed prekey only. No 429 is ever returned.
[ $drained -eq 1 ] || echo "pool larger than loop; raise the count"
```

#### Remediation
Add a Redis sliding-window rate limit AND a durable per-target daily consume quota to the fetch path, mirroring the directory endpoints. Concretely: (1) in HttpRoutes.kt:736 add `if (!RateLimiter.allow("prekey_fetch", authedUserId)) { 429 }` (add a `prekey_fetch` entry to RateLimiter.LIMITS, e.g. RateLimit(60, 3600)); (2) add a per-target durable daily cap (analogous to DirectoryQuota) keyed on blindIndex(targetUserId) so Redis loss cannot reset it; (3) optionally serve the signed-prekey-only bundle without consuming when the requester recently fetched the same target, to blunt burst depletion. Also alert on abnormal consume rates via the existing audit counters.

---

### PreKey upload/refresh: unbounded, unrate-limited, and refresh skips field validation → per-account one_time_prekeys storage exhaustion (DoS)

**Severity:** MEDIUM (5.0)
**CVSS Vector:** `CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:N/I:N/A:L`
**Target:** signaling-server POST /api/v1/prekeys/refresh and POST /api/v1/prekeys/upload
**Endpoint:** /api/v1/prekeys/refresh
**Method:** POST

#### Description
The one-time prekey write endpoints have no rate limit, no per-account total cap, and the `/refresh` variant skips the per-field sanity validation that `/upload` performs. An authenticated user can insert an effectively unbounded number of distinct one-time prekey rows into their own `one_time_prekeys` record, exhausting PostgreSQL storage.

#### Impact
Storage-exhaustion / denial-of-service against the shared PostgreSQL instance. Because `INSERT ... ON CONFLICT (user_id, key_id) DO NOTHING` deduplicates only on `(user_id, key_id)`, an attacker simply varies `keyId` across the 2^31 Int space to add new rows on every request. With no rate limit and no per-account row cap, a single authenticated account can grow the table without bound, impacting all users of the shared database (a cross-tenant availability effect from a single low-privilege account).

#### Technical Analysis
HttpRoutes.kt:719-733 (`/prekeys/refresh`): reads `List<PreKeyEntry>` bounded only to PREKEY_BODY_LIMIT (64KB) and calls `PreKeyStore.addOneTimePreKeys(...)` directly. It never calls `hasSaneKeyMaterial()` (HttpRoutes.kt:147) — so unlike `/upload` there is no keyId range check (0..0xFFFFFF), no per-key size check, no count cap (MAX_ONE_TIME_PREKEYS=200), and no duplicate-keyId check. keyId is written straight to an INT column, negatives included.

PreKeyStore.addOneTimePreKeys (PreKeyStore.kt:235-256) batch-inserts with `ON CONFLICT (user_id, key_id) DO NOTHING` and no total-count guard. `unconsumedCount` exists but is never used to cap growth.

Neither `/prekeys/upload` (HttpRoutes.kt:680) nor `/prekeys/refresh` (719) appears in the RateLimiter call-site list (only 336/377/397/422/480/501/663 are rate-limited). ~64KB of `{"keyId":N,"publicKey":"<b64>"}` entries per request, unlimited requests, each with fresh keyId values, accumulate permanently (until the retention worker or account deletion runs) in `one_time_prekeys`.

#### Proof of Concept
A single authenticated account loops POSTing 64KB batches of one-time prekeys with monotonically increasing keyIds; row count for that account (and total table size) grows without bound and without any 429.

```
import base64, os, itertools, requests
BASE="https://securechat.example"; TOKEN=os.environ["TOKEN"]
kid = itertools.count(1)
pub = base64.b64encode(os.urandom(33)).decode()
while True:
    # ~ up to the 64KB body cap; keyIds never repeat -> ON CONFLICT never fires
    batch = [{"keyId": next(kid), "publicKey": pub} for _ in range(500)]
    r = requests.post(f"{BASE}/api/v1/prekeys/refresh",
                      headers={"Authorization": f"Bearer {TOKEN}"}, json=batch)
    # no 429 is ever returned; rows accumulate permanently for this account
    assert r.status_code != 429, "unexpectedly rate limited"
    print(r.json().get("remaining"))
```

#### Remediation
1) Apply `hasSaneKeyMaterial()`-equivalent validation on `/prekeys/refresh` (keyId range, per-key size, count cap, distinct keyIds). 2) Add a Redis rate limit (`prekey_upload`) to both `/upload` and `/refresh`. 3) Enforce a hard per-account cap on stored one-time prekeys (e.g. reject/rotate above ~1000): in `addOneTimePreKeys`/`uploadBundle` check `unconsumedCount(userId)` and cap or evict oldest. 4) Consider `bigint`/bounded keyId domain enforcement in the DB.

---

### Cross-instance credential-revocation lag: per-process 10s epoch cache lets access tokens survive logout/deletion on other signaling instances

**Severity:** LOW (3.1)
**CVSS Vector:** `CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:L/I:N/A:N`
**Target:** signaling-server AuthService.verifyToken / CredentialState cache (all authenticated HTTP + WS routes)
**Endpoint:** all authenticated endpoints (e.g. /api/v1/directory/*, /ws)
**Method:** GET

#### Description
Access-token validation checks the token's embedded credential epoch against a per-process snapshot cached for 10 seconds. Logout/account-deletion rotates the durable epoch in PostgreSQL and evicts only the LOCAL process cache. The deployment is explicitly horizontally scaled (README: "Migration tamamlandiktan sonra signaling instance'larini olcekle"), so other instances continue to accept a just-revoked access token for up to CACHE_TTL_MS (10s).

#### Impact
A window (bounded by CACHE_TTL_MS = 10s) in which a revoked/stolen access token still authenticates on signaling instances other than the one that processed the logout — including after account deletion. It weakens the "logout instantly invalidates all tokens" and "deleted account cannot authenticate" guarantees the design advertises, in exactly the multi-instance topology the operators are told to run. Severity is limited by the short, bounded window and by refresh tokens being unaffected (their rotation is an atomic DB compare-and-set on refresh_generation).

#### Technical Analysis
CredentialState.kt:39 `CACHE_TTL_MS = 10_000`; cachedSnapshot() (56-63) returns the cached Snapshot if `now - loadedAtMs < 10s`, else reloads from DB. The code comment asserts "Bu process tek yazicidir" (single writer) — true only for a single instance. `forget(userId)` (48-50) and `rotateCredentialEpoch` (85-102) run in the process that handles logout; on other instances the cache is untouched.

AuthService.verifyToken (AuthService.kt:210-235) accepts the token iff `decoded.getClaim("epc") == state.credentialEpoch` where `state = CredentialState.cachedSnapshot(subject)`. On instance B whose cache still holds the pre-rotation epoch (loaded < 10s ago), the stale epoch equals the old token's `epc`, so verification passes for up to 10s after logout. After the entry expires, B reloads the rotated epoch from DB and the token is rejected.

Account deletion: deleteDurableState removes the `users` row; but instance B's cached non-null Snapshot keeps validating the token until the 10s entry expires and the reload returns null. Refresh flow is safe: rotateRefreshGeneration (CredentialState.kt:111-135) is `UPDATE ... WHERE refresh_generation = ? RETURNING ...`, an atomic DB CAS, and logout rotates refresh_generation too, so a superseded refresh token fails the CAS regardless of cache staleness.

#### Proof of Concept
With ≥2 signaling instances behind the LB: authenticate, capture the access token, POST /auth/logout (routed to instance A), then within ~10s replay the same access token on requests that land on instance B — they still succeed until B's cache entry expires.

```
# 2+ signaling instances behind the reverse proxy / LB.
T="<captured access token>"; BASE="https://securechat.example"
# 1) revoke (lands on some instance A)
curl -s -X POST -H "Authorization: Bearer $T" "$BASE/api/v1/auth/logout"
# 2) immediately hammer an authed route; requests that land on other instances
#    keep returning 200 for up to ~10s (CACHE_TTL_MS) instead of 401.
for i in $(seq 1 40); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
       -H "Authorization: Bearer $T" "$BASE/api/v1/directory/snapshot")
  echo "$i: $code"; sleep 0.3
done
# Expect a run of 200s post-logout on stale instances, converging to 401.
```

#### Remediation
Make revocation consistent across instances rather than relying on a per-process TTL cache: (1) publish an epoch-invalidation event on Redis pub/sub (a bot_api-style `client_invalidate` channel already exists as a pattern) so all instances evict the userId on logout/delete; and/or (2) drop CACHE_TTL_MS to ~0–1s for the access-token path, or verify the epoch straight from the DB on the hot path with a very short negative-safe cache; and/or (3) shorten access-token TTL. At minimum, document that horizontal scaling introduces up to CACHE_TTL_MS revocation lag and gate the value accordingly.

---

## Executive Summary

## Methodology

Whitebox source review of the SecureChat hardened server (Kotlin/Ktor, 214 files / ~24k LoC). Read every security-critical module directly and cross-checked with targeted greps rather than generic scanners (no live target).

Coverage:
- **AuthN/AuthZ:** AuthService (HS256 JWT: issuer/typ/epoch enforced), WebSocketCredentials (header-only bearer, query-token rejected), ServiceAssertion + ServiceAccounts (Ed25519, 120s, scope + provisioned-subject binding), bot EdDsaJwtVerifier (alg=EdDSA pinned, bh-before-nonce ordering), MetricsAccess/admin token gate (constant-time), requirePrincipal scope isolation.
- **Crypto/privacy:** ServerPrivacy (AES-256-GCM random nonce, purpose-separated keys, AAD binding), FcmTokenCipher, KeyEncryptor, PrivateDirectoryOprf (blind-RSA, group-membership checks, ≥3072-bit/e=65537, HSM/PKCS11), PurposeSeparatedSecrets, SecretSource (file/perm/size gate), blind-index rate/queue keys, DirectorySnapshotCache padding + decoys, AuditLog (identity-free counters), FcmPushSender (generic wake-only payload).
- **Injection:** All SQL is parameterized (PreparedStatement everywhere; grep found zero interpolated SQL). Server-emitted frames use typed JsonObject builders. No exec/deserialization/reflection sinks. Log redaction + IP-discarding audit. Email address validated + jakarta InternetAddress (no SMTP header injection).
- **Concurrency/atomicity:** OTP (Lua atomic create/claim/consume), RateLimiter + bot RateLimitGuard (Lua sliding-window, fail-closed), IdempotencyStore (SETNX + sealed cache), PreKeyStore (single-tx upload, FOR UPDATE / SKIP LOCKED consume), CredentialState (CAS refresh rotation), RegistrationGrants (grant-consume in account tx), DirectoryQuota (atomic upsert), GroupCallSessionStore (synchronized), ConnectionManager (mutex capacity/compare-remove).
- **DoS/input caps:** receiveBounded / BoundedBody byte caps, WS 256KB frame + byte cap, offline-queue count+byte caps, prekey field caps (upload path), regexes reviewed for ReDoS (none catastrophic).
- **Deployment:** compose.privacy.yml (read_only, cap_drop ALL, no-new-privileges, internal networks, secret files, digest-pinned images), reverse-proxy.conf (access_log off, token= query blocked, admin/metrics/version 404), ProductionDeploymentPolicy (both modules: verify-full, PKCS11, TLS TURN), deploy_privacy_stack.sh preflight, ClientAddress XFF trust (right-most untrusted, literal-IP only), UnixSocketBridge (0600 socket, no TCP exposure).

## Executive summary

The target is an unusually well-hardened codebase: authentication, cryptographic key separation, SQL parameterization, atomic Redis/Postgres state transitions, fail-closed startup gating, and container/deploy hardening are all implemented correctly and defensively. No injection, RCE, deserialization, SSRF, auth-bypass, or IDOR was found; the common classes are closed.

The residual weaknesses cluster in the **prekey subsystem**, which — unlike every other authenticated route — has no rate limiting or per-account/per-target quotas:
1. **(Medium) One-time prekey exhaustion** — `GET /api/v1/users/{userId}/prekeys` consumes a target's one-time prekey per call with no rate limit, letting an authed attacker drain any known UUID's pool and degrade X3DH forward secrecy for new sessions.
2. **(Medium/Low) PreKey upload/refresh storage DoS** — `/prekeys/refresh` skips field validation and neither write path is rate-limited or capped, allowing unbounded growth of `one_time_prekeys` for a single account.
3. **(Low) Cross-instance revocation lag** — the 10s per-process credential-epoch cache plus horizontal scaling leaves revoked access tokens valid on other instances for up to 10s after logout/deletion.

Recommendation priority: add Redis rate limits + durable quotas to all three prekey routes (fetch/upload/refresh) and a hard per-account one-time-prekey cap; propagate epoch invalidation across instances (Redis pub/sub) or shorten the epoch cache TTL for the access-token path.


---
**Report Updated:** 2026-08-25 16:38:06
