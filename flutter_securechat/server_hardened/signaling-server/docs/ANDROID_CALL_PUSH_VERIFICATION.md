# Android Call Push: Repository Findings and Admin Verification

Scope: this hardened signaling-server module only. No client, legacy server,
endpoint configuration, database schema, or deployed service was changed by this
review. The external server was reportedly updated independently; repository
behavior is not proof of the running artifact's behavior.

## Findings

1. **A same-token refresh could erase the hint key.** The authenticated
   `/api/v1/fcm/register` route passes the optional `pushHintKey` into
   `FcmTokenStore.registerToken`. Previously every registration replaced the
   entire record, including replacing an existing key with null if the field was
   omitted. This was reproduced through both HTTP and the PostgreSQL store.
   The fix preserves an unexpired key only for the exact same FCM token.
   Explicit key rotation still replaces it. A different token without a key
   never inherits the previous device's key; unregister and expiry discard it.

2. **Token and hint reads could observe different registrations.** The sender
   previously called `getToken` and `getPushHintKey` separately. Registration,
   removal, or expiry between those reads could pair an old token with a new key
   or no key. The sender now obtains a single defensive registration snapshot.
   Per-user cache updates and persistence writes are serialized within a store
   instance. The existing blind index, AEAD storage format, and retention remain.

3. **A connected background runtime could consume calls without handling them.**
   Previously `addConnection` drained call frames on every authenticated socket;
   `deliverOfflineMessages` removed them after socket send, not a call-handler
   ACK. Online call routing also sent to any socket and bypassed push. Presence
   foreground status was not consulted. An opt-in capability now keeps call
   frames away from message-only background sockets, including during initial
   drain, and uses the existing queue/push path for new calls.

4. **A call-control wake could suppress an incoming-call wake for three seconds.**
   `call_control` has a message hint (`m`) but previously shared the incoming-call
   rate bucket. A regression reproduced control-then-offer suppression. Control
   now has its own bounded, blind-indexed bucket; incoming offers/invites retain
   their existing rate limit, priority, and 30-second FCM TTL.

## What Missing `k` Means

In this sender, every sent `securechat_wake_v2` contains `k` when its registration
has a hint key, including non-call wakes. Only `sdp_offer` and `group_call_invite`
encrypt `c`; other eligible wakes encrypt `m`. A legacy/keyless registration sends
only the generic type. Encryption failure fails the send; it does not silently
fall back to a hintless payload.

`PushHintCipher` produces fixed-width, 42-character `v1.` AES-256-GCM hints with
the existing AAD and random nonce. No cipher/wire-format change was necessary.
Tests inspect the actual Firebase SDK message and decrypt the opaque hint. The
provider gets no caller, conversation, phone, call ID, SDP, or plaintext kind in
the data fields.

The reported device `wake_no_hint` is evidence of missing `k`, not evidence that
the wake was a call or a message. A wrong key would not remove `k`. A client
`hint_submitted` event is not proof that the selected server accepted/persisted
that key before an earlier push. The repository bugs above are concrete, but
attributing the deployed symptom to them requires the checks below.

## Coordinated WebSocket Contract

Header on authenticated `/ws`:

```text
X-SecureChat-Call-Capable: false
```

- Only message-only background runtimes send `false`.
- Foreground sends `true`; an absent header also means `true` for compatibility.
- Values are exactly lowercase `true` or `false`. Other values close with policy
  violation. This header does not grant authorization or change routing identity.
- A message-only connection cannot replace an existing capable socket. It is
  closed with code 1013 and reason `Call-capable session active`; the client should
  stop that background attempt rather than enter a reconnect loop.
- A capable socket can replace a message-only socket. No second simultaneous
  per-account socket or new message protocol was introduced.
- SDP offer/answer, ICE, call-control, and group-call-invite frames remain queued
  for a capable socket. Chat/file handling and encrypted-message ACKs are
  unchanged. Offers/invites still use the existing FCM call-hint path even while
  a message-only socket is connected; ICE/answers do not generate their own push.
- Closing a message-only socket does not clear active one-to-one or group-call
  state. Closing a superseded socket does not remove the replacement's state.
- The existing 30-second offer age check (when a timestamp is present), bounded
  queue TTL/size, and ACCEPT/HANGUP/REJECT/BUSY cleanup still apply. Retained SDP
  answers are now included in pending-call cleanup. No lifetime was extended.

**Handler readiness remains a client obligation.** The server trusts `true`;
the call listener must be installed before that socket opens. A capable socket
still consumes call frames on send, not handler ACK. This is not durable call
delivery across a foreground process crash. Unmarked old background clients
retain the old behavior. This header cannot repair a missing hint key or an
already-consumed offer, and does not provide background media/call management.

## Local Verification

From `server_hardened/signaling-server` (Docker required for integration tests):

```sh
../gradlew :signaling-server:test --console=plain
```

Focused classes: `FcmPushSenderTest`, `PushHintCipherTest`,
`FcmTokenPrivacyIntegrationTest`, `EndToEndServerTest`,
`BackgroundCallDeliveryIntegrationTest`, `ConnectionLifecycleTest`,
`ConnectionManagerIntegrationTest`, `WebSocketRoutingE2ETest`, `MessageTypesTest`.
The fake push transport captures the actual SDK message locally; it needs no
Firebase credentials and sends nothing to FCM. Database/Redis integration uses
disposable local containers, not the deployed stores.

## External Admin Checklist

Perform identity/configuration checks read-only first. Do not deploy, restart,
clear queues, remove tokens, rotate secrets, or modify tables as a diagnostic
shortcut. Controlled device re-registration/call/restart checks below require
the admin's separately approved test window, preferably staging.

1. **Verify the target independently for each installed build.** Parent reports
   that the manually built Android APK and iOS/default build configuration point
   to different servers. Confirm the installed APK's actual HTTPS/WSS origin,
   reverse-proxy upstream, running process/image/JAR, and Firebase project.
   Do not infer the endpoint from this checkout, a pipeline default, or the other
   platform. No endpoint is hardcoded in this patch or this checklist.

2. **Verify the responding artifact, not just source files on disk.** Compare its
   image/JAR digest and protected `/api/v1/version` metadata with the approved
   release. A commit label alone cannot identify uncommitted/external AI edits.
   Confirm that the running build includes hint persistence/snapshot changes,
   payload `k`, and the exact capability header handling. Check every replica.
   Do not overwrite unrelated external server changes with this checkout.

3. **Check readiness without printing credentials.** Use an existing owner-only
   curl config containing the operator authorization header. Set the verified
   origin locally; do not use verbose curl, shell tracing, redirect following,
   or credentials in command arguments/history:

   ```sh
   curl --silent --show-error --fail --proto '=https' \
     --config "$OPERATOR_CURL_CONFIG" "$VERIFIED_SERVER_ORIGIN/api/v1/version"
   curl --silent --show-error --fail --proto '=https' \
     --config "$OPERATOR_CURL_CONFIG" "$VERIFIED_SERVER_ORIGIN/ready"
   ```

   `/health` only means process liveness. Explicitly check `fcm: enabled` in
   `/ready`; even that proves SDK initialization, not FCM acceptance or device
   delivery. Check private startup aggregate `loaded`/`erased` counts for
   unexpected token loss. Do not print encryption secrets or service accounts.

4. **Check registration on the verified server in the approved test window.**
   Confirm HTTP 200 for the authenticated registration and the new existing-log
   suffix `Token kaydedildi; hint=true`. Report only status, field-presence
   booleans, and test outcome. A database token row/count or outer `v5:` envelope
   alone does not prove an inner hint key. Never dump/decrypt rows into a report.
   Both the FCM token and the device's 32-byte key must be submitted when the
   token changes. In staging verify same-token keyless refresh, explicit key
   rotation, and reload with unchanged server secret files.

5. **Check process consistency.** Token registrations are cached per process and
   loaded at startup; this patch does not add cross-process cache invalidation
   or multi-device storage. Verify registration and call routing reach the same
   state-owning instance. Multiple independently cached writers require a
   separate deployment/architecture fix, not an assumption that re-registration
   refreshed every process.

6. **Exercise message-only call delivery with consenting test accounts.** Verify
   that the proxy preserves the capability header (presence/value only), that a
   background drain leaves fresh call setup queued, and that a foreground socket
   receives it before expiry. Confirm the new send-log suffix
   `Generic wake push gonderildi; hint=true` and device-side hint presence/call
   classification without logging `k` itself. Exercise calls before and during
   background connection, foreground takeover, a background connection attempt
   while foreground is active, and cancellation before takeover. Confirm no
   ghost offer is replayed after cancellation. `hint=true` on a successful send
   means FCM accepted the constructed hint-bearing payload, not device delivery.

7. **Return a sanitized evidence summary.** Include verified endpoint match
   (yes/no), artifact digest/version match, replica count, readiness fields,
   registration HTTP status, stored-hint boolean, sent-hint boolean, capability
   header result, device hint-presence result, and call outcome. Never include
   raw FCM/auth tokens, hint keys/ciphertext, private keys, phone/user/call IDs,
   SDP, request bodies, database rows, or whole environment/log dumps. Existing
   push failure metrics also count suppressed/no-token sends, so they are not
   equivalent to provider rejection counts.
