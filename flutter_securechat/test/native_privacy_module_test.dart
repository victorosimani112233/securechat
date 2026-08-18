import 'dart:io';

import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const call = CallSession(
    callId: 'opaque-call-id',
    peerId: 'account-identity-123',
    peerName: 'Private Person',
    callType: CallType.video,
    direction: CallDirection.incoming,
    state: CallState.ringing,
  );

  test(
    'new sessions default to private presence and notification previews',
    () {
      final session = SessionStore();

      expect(session.shareLastSeen, isFalse);
      expect(session.showNotificationContent, isFalse);
    },
  );

  test('redacted native call payload contains no peer identity', () {
    final payload = nativeCallArguments(call, redactIdentity: true);

    expect(payload['callId'], 'opaque-call-id');
    expect(payload['peerName'], 'Elçim araması');
    expect(payload['peerId'], 'private');
    expect(payload['redactIdentity'], isTrue);
    expect(payload.toString(), isNot(contains('account-identity-123')));
    expect(payload.toString(), isNot(contains('Private Person')));
  });

  test('native source allowlists exclude session, key and database roots', () {
    final root = Directory.current.path;
    final swift = File('$root/ios/Runner/AppDelegate.swift').readAsStringSync();
    final kotlin = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
    ).readAsStringSync();

    for (final source in [swift, kotlin]) {
      expect(source, contains('media'));
      expect(source, contains('crash_logs'));
      expect(
        source,
        contains(
          'Only retained media and local redacted diagnostics may leave private app storage',
        ),
      );
    }
    expect(swift, contains('SecureChatPrivateFilePolicy'));
    expect(swift, contains('resolvingSymlinksInPath'));
    expect(swift, isNot(contains('CNContactThumbnailImageDataKey')));
    expect(kotlin, isNot(contains('Phone.PHOTO_URI')));
    expect(kotlin, isNot(contains('externalCacheDir')));
    expect(kotlin, isNot(contains('getExternalFilesDir')));
  });

  test('iOS background and app-switcher privacy hooks register at launch', () {
    final swift = File(
      '${Directory.current.path}/ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(swift, contains('installPrivacyOverlayHooks()'));
    expect(swift, contains('WorkmanagerPlugin.registerPeriodicTask('));
    expect(swift, contains('com.securechat.app.background.maintenance'));
    expect(
      swift,
      contains('com.securechat.app.background.sender-key-rotation'),
    );
  });
}
