# Incoming call navigation from the launcher

## Evidence and cause

The operator deployed the push diagnostic JAR and returned a healthy version
response with the `dirty-pushdiag-20260922` build tag. During the next call,
Android logged `wake_call_hint` at phone time 14:54:07.691 and
`incoming_notification_posted` at 14:54:07.722. This confirms successful hint
decryption and a notification API invocation, not visible UI or audible ringing.

The user then reported that opening the app icon, without tapping the incoming
call notification, showed the normal chat list. `app.dart` listened only to
native `openRequests`; an existing or newly received ringing session did not
trigger call navigation. The global call banner also excluded ringing sessions.

## Changes

- `lib/src/app.dart`: listen to call sessions, including their current snapshot.
  Restore an incoming ringing call on cold start and foreground resume, or when
  the offer arrives after reconnection. Defer navigation until launch/auth/intro
  routes finish. Recheck the current call ID and ringing state after the frame
  so a canceled/finished call is not opened from a stale callback. Do not push
  another call route when it is already visible. No automatic answering.
- `lib/src/features/calls/ongoing_call_bar.dart`: include ringing calls. Show
  the existing localized incoming/ringing label, rather than an elapsed timer.
  A user who leaves the call screen can return using this banner.
- `test/support/test_app_container.dart`: allow injecting a media runtime for
  navigation widget tests. No production fake or fallback was introduced.
- `test/incoming_call_navigation_test.dart`: cold start, delayed offer, resume,
  cancellation during launch/background, duplicate session updates, back/banner
  navigation, explicit answer/reject, outgoing non-interruption, authentication
  deferral and group invitation coverage.

Three regression scenarios failed against the original application navigation:
cold start, delayed offer, and foreground resume. After the fix, the targeted
call/navigation/lifecycle suite passed 54 tests. The complete Flutter suite then
passed 561 tests; Flutter analysis found no issues. `git diff --check` was clean.

## Scope and device check

No new server change, database migration, permission, signaling payload or
cryptographic change is required. Navigation uses the real CallManager session,
not the anonymous push hint, and does not fabricate a caller identity.

The change is shared Flutter code. Native iOS compilation and a real iPhone call
were not tested in this Linux session. For device acceptance, close the updated
Android app normally, call it, then open its launcher icon while it is still
ringing without touching the notification. Verify answer/reject and two-way
audio separately. A call already ended by the caller must not reopen as ringing.

## Android artifact and installation

- Built release `1.0.79+79` with the existing 185.22.184.114 API/signaling
  configuration and both certificate pins. Verified all 13 named sound resources
  in the APK resource table, ZIP alignment and the existing device-test signer.
- APK: `build/app/outputs/flutter-apk/app-release-1.0.79-device-test-signed.apk`.
  SHA-256: `fb17f6f18ee4d237eca5211ab043681be46d28e9e50db8ab9de04375ba428950`.
  This is release-mode code signed with the existing Android debug/test key,
  not a production distribution signing identity.
- Updated connected Samsung `R5GL2452SJK` using `adb install -r` (Success).
  Device reports version 79 / 1.0.79, update time 2026-09-22 15:20:33.
  Cold activity launch returned `Status: ok`. Logs at 15:20:47 show
  `device_hint_key_ready` and `PUSH-REGISTRATION hint_submitted`.
- No uninstall, data clear, server redeployment, commit or push was performed.
  The new physical-device incoming-call/launcher scenario still requires the
  user's next call; automated navigation tests are not a two-phone audio test.
