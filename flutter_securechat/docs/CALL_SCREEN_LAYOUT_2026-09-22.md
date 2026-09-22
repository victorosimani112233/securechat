# Call screen layout review

## Problem

The call screen reused a centered voice-call column above the entire video.
The peer name and status therefore covered the remote person's face. The local
preview used fixed top offsets; reconnect notices and long text could collide
with it. Group video used fixed top/bottom padding to guess the space occupied
by other controls. Large circular controls wrapped unpredictably on narrow
screens, and raw mesh peer IDs / SFU feed numbers appeared as participant names.

## Changes and rationale

- `lib/src/features/calls/call_screen.dart`: identity and duration are now in
  a compact top band. Remote video remains full-bleed; the central video area
  contains no peer name or duration overlay. Top and bottom safe insets are
  respected, including system status/navigation icon contrast.
- Header, reconnection notice, remaining media area and controls are laid out
  sequentially. No hard-coded top position estimates are needed. On short
  landscape screens text is line-limited without changing the user's font scale.
- The local preview fits inside the remaining content area, uses directional
  positioning for RTL, and never overlaps the header or controls. At extremely
  small remaining heights it is hidden while the call controls remain available.
- Controls have fixed 52x52 touch targets, tooltips and accessible toggle states.
  Mute, speaker, camera, flip and end retain their existing CallManager actions.
  Turning the camera off disables flip without shifting the button positions.
- Incoming video does not show a local preview before the user answers.
  Answer/reject remain distinct. Terminal states offer close rather than active
  microphone/camera controls. No implicit answer or media permission change.
- Video with no frame and camera-off states show an avatar in the remaining
  content area, clear of the local preview. Very small remaining areas do not
  render a tiny unusable avatar.
- Group video is a scrollable grid between the header and controls, rather
  than behind them. Tiles have bounded captions. Existing locally resolved
  group identities are used; unresolved identities are labeled generically.
  Raw routing IDs and SFU feed numbers are not displayed. The SFU feed-to-user
  mapping is not expanded by this UI change; an unresolved feed stays generic.
  The local participant remains represented when its camera is disabled.
- `lib/src/widgets/video_stream_view.dart`: optional waiting content is removed
  once the renderer has a live texture/track and nonzero video dimensions.
  The SDK's cached `RTCVideoValue.renderVideo` can still be false on the first
  resize, so it is not used to gate rendering. Existing cover-fit and mirroring
  behavior are preserved. This does not change WebRTC negotiation or encryption.

## Verification and boundaries

`test/call_screen_layout_test.dart` adds 17 widget tests: 320x568, 390x844,
844x390 and 568x320 viewports; 100/200 percent text; active/reconnecting video;
incoming video; camera-off; voice; RTL; eight group tiles; control actions;
screen-reader tap actions, and first-frame / missing-frame transitions. Geometry checks assert that the
name remains in the header, preview does not overlap controls, video fills the
screen and bottom actions remain above the safe inset. Existing incoming call
navigation tests are also retained.

Optional screenshots can be generated with:

```bash
CALL_UI_SCREENSHOTS=/tmp/securechat-call-ui flutter test --no-pub test/call_screen_layout_test.dart
```

Screenshots use real UI/fonts with test renderer state, not a live camera feed.
They verify layout and controls, not actual device camera/audio delivery.
This Linux session cannot compile native iOS; the shared Flutter UI can be built
on the user's Mac. Actual iPhone/Android two-party video still needs a device
acceptance call, especially camera rotation and remote framing.

No server, database, phone-number sharing policy, CallKit permission or call
signaling protocol is changed by this layout work.

## Final result

- Complete Flutter test suite: 578 passed. Static analysis: no issues.
- Android release build: 1.0.80+80, existing API/signaling address and pins.
  APK alignment and the existing device-test signing certificate verified.
- Installed on connected Samsung R5GL2452SJK with `adb install -r`: Success.
  Package manager confirmed 1.0.80 / versionCode 80 at 15:56:32 device time.
  No application data clear or uninstall was used.
- APK: `build/app/outputs/flutter-apk/app-release-1.0.80-device-test-signed.apk`.
  SHA-256: `0205d5933262bb59e1841c57849e89108b2b7430e2aa49be06c313685402debd`.
  This is release-mode code signed with the existing debug/test key, not an
  App Store or production-signing artifact.
- No new two-device video call was placed automatically; native camera/audio
  acceptance remains separate from these UI geometry and interaction tests.

## Voice-only follow-up

The shared video layout made voice controls too hard to identify. Voice calls
now have their own layout in `call_screen.dart`; the video path is unchanged.

- Normal portrait: larger avatar, centered name and duration/status, labeled
  microphone and speaker controls, and a separate full-width red end button.
- Compact screens: smaller avatar beside the name; status comes first so long
  names and accessibility text cannot hide connection progress. The identity
  area can scroll without moving the portrait controls off screen.
- Landscape: identity and actions sit side by side. Action labels sit beside
  icons to keep the end button visible, including at 200 percent text size.
- Incoming calls have explicit answer/reject labels; terminal calls show only
  Close. Labels as well as icons are tappable. Toggle semantics and tap actions
  are exposed to screen readers, with selected controls visually highlighted.
- No audio routing, WebRTC, notification, server, encryption or iOS permission
  behavior changed. Existing localization strings are reused.

18 additional widget tests cover outgoing/ringing/reconnecting voice across
five viewport/text configurations, incoming answer/reject, label taps, initial
status/end-button visibility, and screen-reader activation and toggle state.
The call layout file now contains 35 passing tests. Voice screenshots were
reviewed; existing active video, incoming video and group-video screenshots
have identical SHA-256 hashes before and after this change.

Screenshots use test renderer state, not a real two-device call. Native iOS
compilation and hardware audio acceptance still require device testing.

Voice follow-up verification: all 596 Flutter tests passed; static analysis
and `git diff --check` passed. Android release 1.0.81+81 built successfully,
alignment and existing device-test signature verified. Installed on Samsung
R5GL2452SJK using `adb install -r`; version 81 confirmed at 16:20:32 device time.
APK: `build/app/outputs/flutter-apk/app-release-1.0.81-device-test-signed.apk`.
SHA-256: `4f201a960833ff32b765185a0bf7ad8b03bf87bb15f87a693fa089dfb375ab5a`.
This remains a release-mode APK signed with the existing debug/test key.
