# Protected Account Recovery

Backend implementation, not a deployment authorization. No automatic legacy
email backfill, account creation, phone lookup, or phone-directory reassignment.
Old chat history is available only from independently encrypted user backups.
Email recovery does not decrypt old Signal sessions or approve changed peer pins.

## Immutable V1 Client Contract

All requests below use JSON and POST. All response lifetimes are explicit integer
seconds. Authenticated requests require `Authorization: Bearer <access token>`.
No recovery credentials belong in URLs. Responses carry `Cache-Control: no-store`.

| Path under `/api/v1` | Request | Successful response |
| --- | --- | --- |
| `account/recovery-email/status` | `{}` authenticated | `{bound:boolean}` |
| `account/recovery-email/request` | `{email}` authenticated | `{challengeId,nonce,credentialEpoch,identityProtocol,expiresIn:600}` |
| `account/recovery-email/verify` | `{challengeId,otp,signature}` authenticated | `{status:"ok"}` |
| `auth/login/request` | `{email}` | `{challengeId,expiresIn:600}` |
| `auth/login/verify` | `{challengeId,otp}` | `{recoveryToken,userId,identityProtocol,identityPublicKey,registrationId,expiresIn:300}` |
| `auth/login/complete` | `{recoveryToken,completionId,mode,identityProtocol,identityPublicKey,registrationId,signature}` | `{userId,token,refreshToken,identityReplaced:boolean}` |

`mode` is `preserve` or `replace`; `identityProtocol` is `v1` or `v2`. The server
selects the current enrollment/login identity, preferring an existing modern
bundle. `registrationId` is an integer from 1 through 16383. UUIDs use server
canonical lowercase text. Identity public keys are 33-byte Signal serialized
public keys, signatures are 64-byte libsignal Curve signatures, both encoded as
standard padded Base64. Completion requires canonical Base64, not alternate
spellings. `challengeId`, `nonce`, `recoveryToken`, and client-generated
`completionId` are 32 random bytes in unpadded Base64url (43 characters).

Email normalization: trim surrounding whitespace, lowercase with locale-neutral
rules; only ASCII mailbox addresses are accepted. No plus/dot alias rewriting.
Use the normalized address in the enrollment signature; newline/NUL injection is
rejected. The server never returns a bound address or UUID before valid OTP proof.

Sign exactly these UTF-8 bytes with `Curve.calculateSignature`. Each line break
is one byte `0A`; there is **no final newline**, BOM, length prefix, or JSON layer.

```text
securechat/recovery-enroll/v1
<challengeId>
<nonce>
<userId>
<credentialEpoch>
<normalizedEmail>
<identityProtocol>
```

```text
securechat/recovery-complete/v1
<recoveryToken>
<completionId>
<userId>
<mode>
<identityProtocol>
<identityPublicKey>
<registrationId>
```

Enrollment is first-binding-only and requires the existing identity private key,
fresh email OTP, and a current credential epoch rechecked under an account lock.
The verification request must use the same signed challenge context. There is no
email replacement endpoint. An address binds to at most one account.

Login request is generic for bound, unknown, and address-quota-exhausted mailboxes.
All return a fresh opaque challenge shape. Unknown addresses get no mail and
cannot receive a grant. OTPs are six decimal digits, valid for ten minutes, with
five atomic attempts including malformed guesses. A valid fifth attempt is
accepted. Enrollment, login, completion, and registration proofs are not
interchangeable. Verify failures return `400 {error:"recovery_rejected"}` without
an existence reason. IP limits return `429 {error:"rate_limited"}`. Missing
dedicated recovery secrets/storage failures return `503 {error:"recovery_unavailable"}`.
Malformed or oversized JSON receives `400` or `413` respectively; missing/invalid
authentication on enrollment/status receives `401`.

## Completion And Crash Recovery

Preserve requires the exact current identity, protocol, registration ID, and
proof from its private key. Replacement requires explicit client approval and
proof from the proposed new private key. Persist that private material and the
entire completion request, including `completionId` and signature, before sending.
No access/refresh credentials are issued before successful possession proof.

Completion locks the account, consumes the capability, optionally replaces the
identity pin and clears both legacy/modern public prekey pools, rotates the
credential epoch and refresh generation, and encrypts a response receipt in one
PostgreSQL transaction. Directory identity and UUID do not change. A failed
transaction leaves none of these changes committed.

Retry the **identical** request after a lost response. For five minutes from
commit, the receipt returns the exact original token pair, never a newly issued
pair, only while that account still has the committed epoch. Changed request
fields/signature/completionId, expired receipts, deleted accounts, and later
epoch rotations are rejected. A used refresh token is not revived by a receipt.
Outside this retry window, obtain a fresh email OTP and prove the durably staged
identity; do not generate another replacement identity.

After receiving credentials: persist pending credentials encrypted, bind the local
profile to the confirmed UUID, and install the staged identity without dropping
peer pins. Upload the same staged bundle using new credentials before persisting
the authenticated session; then clear pending state and connect. Failed uploads
retain the staged operation for retry rather than exposing a completed login.
Completion intentionally accepts no bundle: its durable identity pin fences the
empty-bundle interval. Both upload namespaces reject mismatched identities, and
prekey upload/refresh recheck the presented epoch in their write transaction.
Creating the other namespace cannot bypass an existing identity pin.
The epoch is captured once during successful authentication, before reading the
body; an expired/reformatted token cannot become a missing-epoch bypass. Explicit
service principals remain separate. Account deletion rechecks this epoch under
the account lock; logout uses an epoch-conditional rotation, so old requests queued
behind recovery cannot delete the account or revoke the replacement session.

Ordinary HTTP/socket authentication retains the existing bounded epoch cache;
recovery invalidates the local cache and broadcasts invalidation to other instances.
User sockets recheck cached credentials on each incoming frame and an independent
one-second poll closes idle/superseded sockets. Normally pub/sub propagates
revocation promptly; during a pub/sub outage the ten-second cache TTL plus at most
one polling interval bounds socket closure. There is no per-frame PostgreSQL read.
Security-sensitive mutations above remain authoritative under their transaction
lock even during this cache window. Already in-flight operations are not undone.
Service-assertion sockets retain their existing separate authentication policy.

## Secrets And Deployment

Apply immutable migration `V23__protected_account_recovery.sql` through the
normal Flyway startup path. Historical migrations are unchanged. Provision two
independent, random 32-byte keys, encoded as standard Base64:

- `RECOVERY_INDEX_KEY_FILE`: HMAC-SHA256 lookup, challenge/proof, quota, receipt indexes.
- `RECOVERY_ENCRYPTION_KEY_FILE`: AES-256-GCM protected contexts and response receipts.

The existing `SecretSource` also accepts direct environment names without `_FILE`,
but production should use owner-only, read-only secret mounts. Configure both or
neither. Recovery is disabled with neither; partial, weak, malformed, or reused
material fails closed. Never reuse JWT, directory/privacy, push, queue, TURN, or
other configured secrets. Development has no bypass. Existing account registration
continues separately and does not imply recovery enrollment.

Mount/wire these new secrets explicitly in the operator's deployment environment;
the checked-in compose stack does not automatically enable recovery. Validate SMTP
with the existing TLS policy. Recovery mail uses a bounded process-local queue;
queue saturation, SMTP errors, and process restarts can drop mail without changing
public responses. Users may retry subject to quotas. No OTP or address is logged.

Do not simply rotate either key on an existing database: indexes cannot be looked
up and ciphertext cannot be opened with a new key. Plan an offline authenticated
reindex/reencryption migration and coordinate all instances. Keep keys available
for deletion even while public recovery is operationally disabled. With secrets
absent and protected records present, account deletion fails closed rather than
silently leaving protected recovery data behind. Key loss is not recoverable by
email, registration grants, or guessed account metadata.

## Privacy, Retention, And Deletion

New durable metadata is explicitly opt-in via trusted-device enrollment:

- `account_recovery_bindings`: separate HMAC account/email indexes, random binding
  version, AEAD-sealed UUID/email. Unique indexes enforce one-to-one binding.
  Retained until account deletion. No plaintext UUID/email or FK to `users`.
- `account_recovery_challenges`: purpose-separated capability index, protected
  account/email indexes, encrypted context, HMAC proof, bounded attempts, expiry.
  OTP challenges expire in ten minutes; completion capabilities in five minutes.
  Consumption removes the row; recovery removes all remaining account challenges.
- `account_recovery_receipts`: protected account/capability indexes, HMAC of the
  exact typed request, encrypted token response and epoch, five-minute expiry.
- `account_recovery_quotas`: purpose-separated hourly HMAC bucket, count, expiry
  within two hours. Five enrollment requests/account/hour and address/hour; five
  login requests/address/hour. IP Redis limits additionally allow five requests,
  twenty verifications, and twenty completions per ten minutes per category.
- `users.recovery_identity_pin` and `recovery_identity_protocol`: public key pin
  and namespace, not email metadata or private key material.

AEAD uses fresh random 96-bit nonces, 128-bit tags, and versioned AAD bound to the
row's purpose and indexes. No plaintext OTP or capability is persisted. The
existing startup/six-hour retention worker removes expired challenges, receipts,
and quotas in its fail-closed transaction. Expiration is enforced at use, not
delayed until cleanup. Physical row retention can therefore exceed validity by
up to the cleanup interval; database WAL/backups follow operator retention.
Quota buckets have no plaintext account link and expire rather than becoming a
permanent activity log. Account deletion locks `users` then transactionally removes
binding, account-associated challenges and receipts before deleting the account.

Database compromise still reveals recovery enrollment counts and equality within
each protected index domain; live server/key compromise can decrypt bindings.
SMTP providers necessarily observe destination addresses and email content. This
feature is account recovery, not protection against a compromised mailbox.

## Verification

Tests use real PostgreSQL/Redis Testcontainers and libsignal signatures. Run from
`server_hardened` with Docker available:

```sh
./gradlew :signaling-server:test --tests '*Recovery*Test' --tests '*PreKey*IntegrationTest' --tests '*PurposeSeparatedSecretsTest' --tests '*SchemaMigrationIntegrationTest'
./gradlew -I tools/isolated-test-workers.init.gradle :signaling-server:test :signaling-server:fatJar
```

Before release, complete the client staged-key/backup-owner/peer-approval tests,
exercise lost responses and application restarts against this wire contract, and
load-test bounded epoch-cache refresh and idle socket polling. No deploy is performed by
this implementation task.
