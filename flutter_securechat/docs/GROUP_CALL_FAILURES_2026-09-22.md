# Group voice/video call repair and hardened server handoff

## Scope and evidence

Client repair files: `lib/src/media/call_manager.dart`,
`group_media_engine.dart`, `janus_client.dart`, and
`lib/src/core/signal_message.dart`, plus focused tests. Flutter sources are
refrozen after the final SFU handoff regression; parent owns Android builds.

Authorized server work is in `server_hardened/signaling-server`:
`GroupCallSessionStore.kt`, `GroupCallSignaling.kt`, `GroupCallLifecycle.kt`,
`GroupJanusGateway.kt`, `JanusOrchestrator.kt`, `SfuPolicy.kt`,
group branches of `WebSocketRoutes.kt`, and one instance-bound room lookup in
`HttpRoutes.kt`. No auth implementation, database migration, screen,
notification, incoming handler, or composition-root edits belong to this task.
Other dirty worktree changes belong to the parent/other agents.

Only local tests/builds were run. No SSH, remote server access, deployment,
image build, commit, or push. The older root signaling-server tree is not the
hardened implementation; verify which artifact is actually deployed.

## Concrete Client Repairs

- Connect signaling before encrypted private-group preparation. Preparation
  itself sends messages and previously ran before connection readiness.
- Register outgoing groups with native call integration, as direct calls do.
- Handle the server-routed `group_call_join_request`, validate call/token/type
  and invited sender, and require its encryption capability for encrypted calls.
  Legacy `ACCEPT` remains usable only for non-frame-encrypted mesh calls.
- Serialize membership changes and SDP offers/answers, deduplicate joins, and
  rotate the media key on actual admission. Previously the coordinator ignored
  the join request and only reacted to a subsequent `ACCEPT`.
- Announce each mesh pair in both directions, including peers still connecting.
  The lower user ID offers for non-coordinator edges. Previously announcements
  only reached already-connected peers, and the new peer did not learn the old
  peer, so its SDP could be mistaken for a separate incoming call. Bounded
  pending SDP/ICE handles cross-socket arrival order without authorizing unknown
  peers to create media connections.
- Check SDP send results and surface setup failures. Inviting is now `ringing`,
  accepting is `connecting`, and real transport connection starts duration and
  `active`. Receiving a track alone no longer declares a connection successful.
- Wait up to eight seconds for a required key when the encrypted payload arrives
  after the invite/accept action. No join capability or media connection is
  created without that key. Reinstall the current key after media initialization.
- Dispose the native key provider on close. Previously keys/providers survived
  calls, including later calls that advertised no frame encryption. Receiver
  cryptor installation is awaited in SDP setup, so its failure is owned by the
  call failure path rather than an unobserved async callback.
- Stop group capture/connections before waiting for reliable hangup ACKs. Reject
  still sends peer `REJECT`, but sends server `HANGUP`: the server only removes
  membership on server-directed `HANGUP`. Peer coordinator departure no longer
  unconditionally ends every remaining peer; server handoff can proceed.
- Cancel the previous group terminal timer on a new group session and stage keys
  for a new call arriving while the previous call is still terminal-visible.
- Defer SFU announcements until local acceptance/media readiness. Require both
  the call's advertised frame-encryption mode and the engine's installed key;
  an operator/server announcement cannot force plaintext SFU. Deduplicate binds
  and subscriptions. A transaction response's Janus JSEP is consumed only once,
  rather than both by its requester and the unsolicited-event handler.

- Decode and handle `group_call_error` only from the server and only for the
  current opaque group token plus call ID. Forged, missing-context, and
  unrelated errors cannot terminate the call.
- Serialize SFU binding/status and mesh SDP/ICE on the group signal queue.
  During binding and after promotion, late mesh answers/offers/ICE are ignored;
  joining members still get key rotation but cannot recreate mesh peers.
  Pending mesh SDP/ICE is discarded at handoff.

The protocol ceiling remains eight people including the caller. Mesh without
FrameCryptor still relies on endpoint-to-endpoint DTLS-SRTP (including TURN
relay); it is never silently promoted to an SFU that terminates that encryption.
Keys remain on the existing encrypted-direct-message boundary. These tests do
not independently prove the crypto adapter or native frame encryption.

## Repaired Server Behavior

- Both VOICE and VIDEO reserve at most eight participants including the caller.
  Invitations and capability-confirmed joins are separate; invitations no
  longer prematurely block the seventh/eighth participant.
- The authenticated join contract rechecks call/token/type, invited membership,
  and required E2EE capability. Explicit correlated server errors replace silent
  admission failures. Client-supplied server-only frames are rejected.
- After the seventh capable participant joins, one serialized promotion creates
  an encrypted-only room, commits only to the same call instance, and announces
  to the latest joined set. Failed creation retains mesh; incompatible media is
  never promoted, including when the legacy plaintext acknowledgement is set.
- Controller transactions distinguish ACK from final replies and reject plugin
  errors or mismatched room creation. Dynamic rooms specify eight publishers,
  VP8/Opus, no recording, private listing, and `require_e2ee=true`.
- The new `/janus` gateway accepts Bearer-authenticated WebSockets with
  `janus-protocol`, then injects the API secret only on internal Janus frames.
  A socket is bound to one joined, encrypted SFU call instance. Commands are
  restricted to that room, its registered feeds, and that socket's sessions and
  handles; discovery, room administration, arbitrary plugins and recording are
  denied. Raw upstream error strings and secret fields are removed.
  One application-scoped HttpClient is reused; connections have separate
  WebSocket builders/sessions instead of a selector/client per authenticated user.
- Public room-info lookup carries the authorized call instance so a replacement
  room is not returned based on an earlier call's membership check.

### Independent Security Review Closure

| Finding | Repair | Regression coverage |
|---|---|---|
| P1 unbounded retained calls | Atomic global ceiling 1,024 and per-user ceiling 4; pending SFU disposal also reserves capacity. All store mutations/expiry share one short reentrant lock. | Concurrent per-user/global admission, capacity release, retained-disposal accounting. |
| P1 handshake-only bearer | Revalidate the existing AuthService verifier on every request, before forwarded responses, and every second while idle. Revocation closes the public and upstream sockets and attempts owned-session destruction. | Real loopback gateway sockets, active-request and idle revocation, upstream closure and no revoked request forwarded. |
| P2 late A teardown destroys B | Room ownership carries a unique call-instance ID; replacement never reuses A's room. Disposal and HTTP lookup check instance ownership. | Real controller WebSocket contract: A/B replacement, delayed A teardown, failed destruction then retry. |
| P2 expiry loses room cleanup | Expiry/end queue owned disposal work; application-wired worker drains every 30 seconds, retries failures, stops with the application. Retired controller sessions receive no further keepalives; retries use a fresh controller. | Expiry versus concurrent join/add, failed disposal retained, replacement survives old cleanup. |
| Follow-up expiry resurrection race | Expiry revalidates instance/start time under the same lock as joins and admission; no remove/write gap. | Repeated concurrent expiry/join/add regression plus existing Lincheck model/stress tests. |

The gateway uses existing credential-epoch semantics, including the existing
10-second credential cache and cross-instance invalidation. It does not claim
instantaneous distributed revocation during invalidation loss. Gateway socket
tests inject a revocable verifier; existing server E2E tests exercise actual
JWT/PostgreSQL/Redis authentication separately.

### Tested Janus Contract, Not Live Janus

Official [VideoRoom documentation](https://janus.conf.meetecho.com/docs/videoroom.html)
documents `require_e2ee` for publishing **and subscribing**, and transactional
room creation/destruction responses. The
[legacy one-feed subscriber contract](https://janus-legacy.conf.meetecho.com/docs/videoroom.html)
matches this Flutter client's separate subscriber handles.
[Janus API authentication](https://janus.conf.meetecho.com/docs/auth.html)
documents frame-level API-secret authentication: forwarding an HTTP Bearer
header to raw Janus is not sufficient.

Tests drive actual encoded signaling, the production admission/gateway logic,
and real local WebSocket connections to a protocol fixture. They do not run a
real Janus binary or media session. The gateway sets `jsep.e2ee=true` after
authenticated capability admission and rejects explicit plaintext negotiation.
Neither that declaration nor `require_e2ee` proves cryptographic frame content.
FrameCryptor installation, key agreement, and actual encrypted forwarding remain
device/Janus interoperability gates.

## Operator Configuration Still Required

**SFU stays OFF by default.** Unset `SFU_ENABLED` leaves both audio and video
in mesh up to eight. At eight, each device may need seven outgoing streams and
multiple encodes: upload bandwidth, CPU, thermal and battery failure remain
real risks. This fallback is supported admission, not verified eight-device
performance or a production-success claim.

For encrypted SFU rollout, the operator must supply and verify:

1. Explicit `SFU_ENABLED=true` on the signaling process. The checked-in hardened
   compose does not forward this variable; merely setting a host environment
   variable is insufficient. No compose/live configuration was changed.
2. `JANUS_WS_URL` pointing to the private Janus control WebSocket and
   `JANUS_PUBLIC_WS_URL=wss://<pinned-signaling-host>/janus` pointing to the
   **signaling gateway**, never raw Janus. Extend the operator-owned reverse
   proxy to route `/janus` to signaling:8080, preserve Authorization,
   WebSocket upgrade and `janus-protocol`, reject query tokens and disable
   request/access logging. The checked-in proxy lacks this route.
3. Existing provisioned read-only `JANUS_API_SECRET_FILE` and
   `JANUS_ADMIN_SECRET_FILE`, matching Janus core API secret and VideoRoom
   `admin_key`. No credentials were invented. Keep raw Janus private and
   inaccessible to clients; private room listing alone is not authorization.
4. A Janus version tested with encrypted VP8/Opus and the legacy subscriber
   contract, correct TLS trust/pinning, UDP/media ports, and usable short-lived
   TURN credentials from `/api/v1/ice/config`. STUN alone is not enough.
5. Same-version device validation for 2/7/8-member VOICE and VIDEO calls,
   late joins, leave/rejoin, promotion, logout, dropped sockets, denied
   permissions, foreground/background, and restrictive NAT/network changes.

Call/room metadata is in-memory. Restart does not reconstruct a preexisting
Janus room inventory; operator recovery must reconcile orphaned dynamic rooms
after a signaling crash or uncertain Janus creation response. No durable
membership or media-key database was introduced.

## Permissions and Unverified Constraints

Android declares `RECORD_AUDIO` and `CAMERA`; iOS includes microphone/camera usage
descriptions. `getUserMedia` requests audio for both call types and camera only
for video. Permission/capture exceptions now have tested cleanup behavior; no
permissions were widened or bypassed. Actual OS prompts, permanent denial,
CallKit/Telecom audio activation, Bluetooth/speaker routing, background/resume,
and physical microphone/camera capture were not exercised.

No physical devices, live signaling service, TURN relay, real Janus deployment,
network transition, NAT traversal, bandwidth/load at eight participants, or
native FrameCryptor interoperability were verified. Use same-version clients
for rollout validation; mixed-version mesh offer-direction behavior needs a
device regression pass. SDP/ICE wire frames still lack a call ID, so delayed
frames across reused peer pairs cannot be perfectly isolated by this client
alone. Initial media keys are distributed to invitees: this repair does not
claim stronger pre-join history secrecy than that existing protocol provides.

## Focused Verification

Initial client verification: 89 tests passed. Final client refresh verification:
46 tests passed in `group_call_contract_test.dart`,
`group_media_lifecycle_test.dart`, `janus_group_contract_test.dart`,
`media_module_test.dart`, and `services_test.dart`. Scoped analysis of
`call_manager.dart`, `signal_message.dart`, and the group contract test is
clean; scoped `git diff --check` passed. Parent separately reported 706 full
Flutter tests after the handoff fix plus 22 latest scoped tests; parent reports
final APK84 installed. This does not establish live group-call interoperability.

- `test/group_call_contract_test.dart`: real signal encode/decode between three
  managers with strict fake media; voice/video full mesh, concurrent/duplicate
  joins, early ICE, connection state, delayed/missing keys, permissions, failed
  SDP sends, immediate next call, max-eight, forged context, SFU gating, rejection.
- `test/group_media_lifecycle_test.dart`: real group engine with mocked native
  method channel; key-provider disposal/recreation and fail-closed options.
- `test/janus_group_contract_test.dart`: actual loopback WebSocket handshake,
  Janus ACK/final transaction replies, publish/subscribe/start and unsolicited
  JSEP; no duplicate negotiation or API-secret disclosure.
- `test/media_module_test.dart`: existing group regressions updated to assert
  ringing-before-media and rotation through the real join-request contract.
- Existing media-key, failure-diagnostics, native rejection, iOS outgoing-call,
  and call-screen layout tests are run as compatibility checks.

Run with `/home/user497/flutter/bin/flutter test --no-pub` followed by the test
paths above. Analyze only the three changed media files and focused test files
with `flutter analyze --no-pub`. No application build/install is needed.


### Server Tests

Full server suite: **1,250 passed across 57 suites**, no skipped/failed tests,
in 5m04s. This full run preceded only the final application-scoped HttpClient
reuse correction. After that correction, all 78 focused tests passed again;
the final clean-test run using the repository-owned init script passed in
2m07s. Server sources are frozen at the artifact below.

Focused run: **78 passed**, no skipped/failed tests:
`GroupCallAdmissionLifecycleTest` (5), `GroupCallCapacityTest` (7),
`GroupCallSessionPrivacyTest` (2), `GroupCallSessionStoreLincheckTest` (2),
`GroupCallSignalingContractTest` (6), `GroupJanusGatewayTest` (7),
`JanusControlPlaneTest` (17), `JanusOrchestratorTest` (4),
`SfuPolicyTest` (6), `WebSocketRoutingE2ETest` (22).

`FakeJanusServer.kt` is the changed local controller fixture. Gateway coverage
includes same-room publishing/subscribing, denied foreign
rooms/feeds/sessions/handles, removed feed owners, replacement calls,
non-encrypted membership, plaintext negotiation, admin/record/plugin commands,
secret/error redaction, revoked bearer, and SFU-off denial. Real route tests use
a local Netty upstream; routing E2E tests use local Docker PostgreSQL/Redis.

The normal combined test run hit JaCoCo/Lincheck class-redefinition interaction
and then a Lincheck test-worker heap failure. Successful runs use 2 GiB workers
and one test class per JVM. Parent added the repository-owned
`server_hardened/tools/isolated-test-workers.init.gradle` with those effective
settings, used for final verification below. JaCoCo remains enabled; no tests
are skipped and no coverage percentage is claimed. The earlier temporary init
script's attempted agent disable did not take effect; its effective settings
match the repository script. Reproduction is not dependent on `/tmp`.

```bash
./gradlew --offline -I tools/isolated-test-workers.init.gradle \
  :signaling-server:test --tests '*GroupCall*' --tests '*SfuPolicyTest' \
  --tests '*GroupJanusGatewayTest' --tests '*JanusControlPlaneTest' \
  --tests '*JanusOrchestratorTest' --tests '*WebSocketRoutingE2ETest'
```

### Artifact and Deployment Handoff

Built artifact: `server_hardened/signaling-server/build/libs/signaling-server-all.jar`
(86,502,777 bytes), Java 17 target.

```text
SHA-256: 4bf60c0c16bc40812e54f21dcb79b3575c1ae795ff7b4dbf4e6b2aa6a2e48e3b
commit: dbb3c4410400ea7ea575022308cb870f755fb0ae-dirty-group-calls
builtAt: 2026-09-22T16:01:15Z
migrationTarget: V22
```

Build command (from `server_hardened`):

```bash
./gradlew --offline :signaling-server:fatJar \
  -PsourceCommit=dbb3c4410400ea7ea575022308cb870f755fb0ae-dirty-group-calls \
  -PsourceBuiltAt=2026-09-22T16:01:15Z
```

The build was run together with the final focused test command above. V22 is
the repository's existing migration target, not a migration added by this task.
No remote deployment has occurred and no database migration file was changed.

The candidate is an **uncommitted working-tree snapshot**, not an approved
release revision. The embedded build identity records that distinction; do not
claim it is the clean HEAD commit. The hardened image-build release script
requires a real 40-hex release commit and its normal test/SBOM/SCA gates. The
maintainer must perform those release steps separately; this task must not
commit/push or invent image digests.

Deployment action needed: package the verified JAR as
`/opt/securechat/app.jar` using `deploy/Dockerfile.signaling` and the approved
immutable JRE image, publish through the normal release process, set
`SIGNALING_IMAGE` to the resulting immutable registry digest, retain the
existing secrets/configuration, run `deploy/deploy_privacy_stack.sh --check-only`,
then the operator-approved `--apply` procedure. Keep SFU disabled for the first
mesh-only rollout unless all gateway/Janus requirements above have been tested.
Do not use the legacy root compose or replace a running container ad hoc.
Verify the running build identity and repeat physical-device calls after
deployment. Neither APK replacement alone nor this local JAR build repairs an
old running server.
