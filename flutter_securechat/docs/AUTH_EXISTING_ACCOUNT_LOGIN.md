# Existing-account login: contract and limitations

## Status (23 September 2026)

The user approved protected recovery-email enrollment and existing-account
login on 23 September. Client and hardened-server implementations are now being
verified locally. See [the current implementation report](ACCOUNT_RECOVERY_2026-09-23.md)
for configuration, test evidence and remaining live deployment checks.

The material below is the **historical pre-implementation audit from 22
September**, retained to explain why unrelated registration OTPs cannot recover
accounts. Its statements about missing routes/UI are not current status.

No backend, storage entity, session-store, or crypto-store implementation was
changed. No account-enumeration endpoint, phone lookup, SMTP bypass, or legacy
fallback was added. No existing account email is overwritten.

## Audited contract

Production source is `server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/`:

- `HttpRoutes.kt`: `/api/v1/otp/request` accepts an email. `/otp/verify` checks
  that email and its code, but calls `AuthService.issueRegistrationToken()`
  **without** the email or an account identifier.
- `AuthService.kt`: the registration grant contains an opaque grant ID and
  expiry, not a binding between a verified email and an existing account.
- `HttpRoutes.kt` and `RegistrationGrants.kt`: `/users/register` atomically
  consumes the grant while inserting a fresh UUID. Success always has
  `isNew: true`. It never returns credentials for an existing account.
- `UserRegistry.kt`: users have UUIDs and private-directory tokens. Registration
  creates a random pending token, not a phone-derived identifier. There is no
  original-email binding from which to implement email account recovery.
- A registration identity conflict is `409 directory_identity_already_registered`.
  Since the client chooses a fresh UUID, this is **not** a phone-existence API.
- Phone directory ownership is only checked later, on authenticated
  `/users/directory-token`. Already-owned and malformed tokens both return
  `400 invalid_directory_token`. This does not reveal the owner's UUID/email
  and cannot safely be translated into "this phone exists, enter a new email".
- `/auth/refresh` requires an existing refresh credential. It is not an OTP
  login route. There is no `/auth/login` route.

The root legacy Kotlin server is not a usable fallback: its registration flow
can return an existing phone owner after verification of an unrelated email.

## Client decisions

- Registration requires a nonempty OTP grant. Successful responses must contain
  `isNew: true`, the exact requested UUID, and nonempty string token pairs.
  Missing/ambiguous fields are rejected instead of defaulted.
- A legacy `isNew: false` response or the documented registration conflict shows
  a localized inline existing-account error, never a local session or a
  placeholder login page.
- A local/restored account UUID blocks new registration. This preserves the
  existing profile and Signal identity instead of silently replacing them.
- Directory setup must succeed before session persistence. A duplicate-phone
  directory rejection cannot leave the client reporting a logged-in account.
  No discovery lookup is used to find its owner. After directory success,
  credentials are persisted BEFORE key generation/upload so a transient upload
  failure cannot strand the account that now owns the directory identity.
- Setup errors after OTP verification clear the consumed code and return to the
  email step with a setup-specific message. They are not reported as an invalid
  OTP and do not automatically retry a consumed grant. Duplicate submissions
  are ignored while a request is running.

## Required backend/product work

An actual login needs a separately reviewed protocol and migration:

1. Establish a privacy-preserving, authenticated recovery binding for existing
   accounts. Existing rows cannot be safely linked to an arbitrary newly supplied
   email. Migration needs an already-authenticated device or a separately proven
   recovery capability. Do not invent an email for legacy accounts.
2. Add a purpose-separated, short-lived, single-use login challenge bound to the
   original account and its established recovery method. Require fresh email OTP
   verification, with generic pre-auth responses, rate limits, and replay tests.
   A create-account grant must never become a login credential.
3. Define private phone conflict/recovery behavior without unauthenticated
   existence queries. Email OTP does not prove phone ownership.
4. Define device/Signal identity recovery and explicit replacement approval.
   Logging into an account must not silently upload a fresh replacement identity.
5. Define resumable registration or transactional provisioning. Directory
   failure occurs after server account creation but before local persistence;
   the server may retain that pending account. Credentials are retained after
   directory success even when prekey upload fails. There is no provisioning
   rollback/resume API. Network or persistence failures can remain ambiguous;
   do not automatically re-register.

The requested "phone already exists: verify the account email again" behavior
cannot be completed safely solely in the present client. The UI deliberately
does not send an OTP that would imply otherwise.

## Persistence and upload retry audit

There is no separate provisional-credential state in the current session model:
`SessionStore.isLoggedIn` means a UUID and nonempty access token exist. Adding
a durable provisioning state would require coordinated storage and lifecycle
changes. This patch instead keeps the existing credential persistence model,
ordered as register -> directory check -> persist -> keys/upload -> connect.
An upload error still propagates; it is not reported as successful setup.

Actual startup behavior was read, not assumed:

- `lib/src/services/app_container.dart` opens the persisted session and wires
  prekey maintenance, but does not upload the initial identity/signed-prekey bundle.
- `lib/src/services/app_lifecycle_coordinator.dart` reconnects using retained
  credentials and invokes maintenance.
- `lib/src/crypto/pre_key_maintenance_service.dart` only calls
  `/prekeys/status` and `/prekeys/refresh`, replenishing one-time keys. It cannot
  repair a missing initial identity/signed-prekey upload.

Thus persisted credentials prevent permanent credential loss, but automatic
full-bundle recovery is an existing gap, not a working bootstrap feature. No
new storage, endpoint, or bootstrap wiring was introduced. A future approved
retry must use retained credentials and the same local identity, never create
another account or silently generate a replacement identity.

## Read-only candidate design (not approved or implemented)

V4 removed `users.email` and `email_verified`; V14 separately removed raw UUID
links in push and bot records. Do not modify those historical migrations or
backfill a recovery email from user-entered phone/email data. `SessionStore`
does not store email, including its encrypted persisted JSON. The minimal
design does not require adding an email field there.

Proposed next migration, subject to numbering recheck:
`server_hardened/signaling-server/src/main/resources/db/migration/V23__protected_account_recovery.sql`.
It would add a recovery record with unique, purpose-separated email/account
HMAC indexes, random binding version and AEAD-sealed account/email context,
plus short-lived, purpose-bound challenge state with atomic attempts and
consumption. Use dedicated recovery index/encryption secrets and AAD-bound
indexes. This is new durable recovery metadata requiring explicit product
approval, even when encrypted. Delete it transactionally with the account.

Candidate endpoints:

- Authenticated `/api/v1/account/recovery-email/request` and `/verify`: fresh
  email OTP plus current account/credential-epoch binding; require proof from
  the existing Signal private key for actual device possession. First binding
  only, no implicit replacement of an existing recovery email.
- `/api/v1/auth/login/request`, `/verify`, `/complete`: generic pre-auth
  responses, separate login-purpose OTP, restricted short-lived recovery
  capability, then atomic consumption and credential rotation for the bound
  UUID. Registration grants must remain unusable for login.
- Initial scope should be single-device recovery: current refresh generations
  are account-wide and the client uses Signal device ID 1. Close superseded
  sockets across instances and revoke old credentials on completion.

Candidate server files in `src/main/kotlin/com/securechat/signaling/`:
new `RecoveryAuthRoutes.kt`, `RecoveryAuthService.kt`, `RecoveryRecordCipher.kt`;
changes to `HttpRoutes.kt`, `AuthService.kt`, `CredentialState.kt`,
`PreKeyStore.kt`, `ModernPreKeyStore.kt`, `AccountDeletion.kt`,
`PrivacyRetentionWorker.kt`, `RateLimiter.kt`, `PurposeSeparatedSecrets.kt`,
`ConnectionManager.kt`, and `WebSocketRoutes.kt`. Deployment secret wiring,
schema/privacy audits and recovery integration tests also need updates.

Identity completion must distinguish possession of existing keys from explicit
lost-key replacement. Ordinary v1/v2 prekey uploads currently accept changed
identity keys; they must reject mismatches outside approved recovery. Peers
retain old identity pins and need explicit verification/approval, not silent
trust resets. New private keys must be staged durably before replacement, with
ambiguous network outcomes handled without regenerating yet another identity.

Client changes would involve auth API/coordinator/screens, authenticated
recovery-email enrollment UI, `lib/src/crypto/pre_key_manager.dart`,
`lib/src/crypto/crypto_protocol_store.dart`, app-container/settings wiring,
and a coordinated peer-identity verification workflow. Logout currently wipes
local keys; retaining them after logout is a separate product choice.

`lib/src/backup/backup_service.dart` excludes Signal private keys and tokens.
Old history therefore needs a backup, and backup restore does not restore the
old encryption identity. Before functional recovery ships, restore must check
authenticated UUID ownership (not only phone), and avoid wiping the newly
active crypto state. These cross-owner changes require coordination; none is
implemented here.

## Localization and verification

Only `auth_login_unavailable` (inline rejection) and `auth_setup_failed` remain
in all four ARB sources. The unused `auth_existing_account`, `auth_login_title`,
and `auth_login_requires_verification` keys were removed. Other agents' keys
are untouched. **Parent must regenerate localization output** to remove stale
getters and refresh the inline error wording. This agent did not run `gen-l10n`
or edit generated files.

Passed before localization generation:

```sh
/home/user497/flutter/bin/flutter test --no-pub test/auth_flow_test.dart test/auth_error_policy_test.dart test/auth_api_contract_test.dart
/home/user497/flutter/bin/dart analyze lib/src/auth test/auth_flow_test.dart test/auth_error_policy_test.dart test/auth_api_contract_test.dart
```

The 29 core tests cover strict registration/OTP response parsing, missing grants,
legacy existing-account rejection, restored identity preservation, directory
and prekey failures, fresh registration, token refresh, and logout.

`test/auth_screen_test.dart` now checks registration OTP sequencing and inline
existing-account rejection, with no login action/navigation, in four locales
at 320px width and 200% text scaling. All 33 auth tests passed after removal of
the placeholder UI, using the existing generated localization output. Rerun
after parent generation to test the updated localized wording as well as the
behavior. Targeted auth analysis and ARB JSON validation passed.
No live server/device login was tested because the protocol does not support it.
The existing device lifecycle test labels fresh re-registration after logout as
"relogin"; that fixture is not evidence of account recovery support.
