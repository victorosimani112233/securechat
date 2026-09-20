import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android call notification lifecycle uses one immutable CallStyle', () {
    final root = Directory.current.path;
    final notifications = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatCallNotificationManager.kt',
    ).readAsStringSync();
    final activity = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
    ).readAsStringSync();
    final connection = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatConnectionService.kt',
    ).readAsStringSync();
    final controller = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatNativeCallController.kt',
    ).readAsStringSync();
    final pushReceiver = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatFirebaseMessagingReceiver.kt',
    ).readAsStringSync();
    final service = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatCallService.kt',
    ).readAsStringSync();
    final tones = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatCallTonePlayer.kt',
    ).readAsStringSync();
    final manifest = File(
      '$root/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final rawResourceKeepRules = File(
      '$root/android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();

    expect(notifications, contains('const val NOTIFICATION_ID = 1200'));
    expect(notifications, contains('CallStyle.forIncomingCall'));
    expect(notifications, contains('incoming_call_channel_v2'));
    expect(notifications, contains('R.raw.elcim_bell'));
    expect(notifications, contains('USAGE_NOTIFICATION_RINGTONE'));
    expect(notifications, contains('Notification.FLAG_INSISTENT'));
    expect(notifications, contains('enableVibration(true)'));
    expect(notifications, contains('CallStyle.forOngoingCall'));
    expect(notifications, contains('setFullScreenIntent'));
    expect(notifications, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(notifications, contains('.notify(NOTIFICATION_ID, notification)'));
    expect(notifications, contains('.cancel(NOTIFICATION_ID)'));
    expect(notifications, contains('SecureChatCallService.start'));
    expect(controller, contains('notifications.showIncoming(info)'));
    expect(controller, contains('NativeCallRegistry.promoteHint(info)'));
    expect(pushReceiver, contains('PushHintCipher.open(key, encryptedHint)'));
    expect(
      pushReceiver,
      contains('SecureChatNativeCallController.reportIncoming('),
    );
    expect(activity, contains('callNotifications.showConnecting(info)'));
    expect(activity, contains('callNotifications.showEstablished(info)'));
    expect(activity, contains('handleCallNotificationIntent(intent)'));
    expect(connection, contains('pendingActions'));
    expect(connection, contains('notifications.showConnecting(info)'));
    expect(connection, contains('setAudioModeIsVoip(true)'));
    expect(connection, contains('requestCallEndpointChange('));
    expect(connection, contains('setAudioRoute(route)'));
    expect(connection, contains('CallAudioState.ROUTE_SPEAKER'));
    expect(activity, contains('"setCallSpeaker" -> setCallSpeaker'));
    expect(activity, contains('"startNativeCallRingback"'));
    expect(activity, contains('"stopNativeCallTones"'));
    expect(activity, contains('"playNativeCallCue"'));
    expect(tones, contains('USAGE_VOICE_COMMUNICATION_SIGNALLING'));
    expect(tones, contains('R.raw.elcim_ringback'));
    expect(tones, contains('R.raw.elcim_call_connected'));
    expect(tones, contains('R.raw.elcim_call_ended'));
    expect(service, contains('startForeground('));
    expect(service, contains('FOREGROUND_SERVICE_TYPE_PHONE_CALL'));
    expect(service, contains('NativeCallRegistry.emit("end", callId)'));
    expect(service, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    expect(service, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(manifest, contains('android:name=".SecureChatCallService"'));
    expect(manifest, contains('android:foregroundServiceType="phoneCall"'));
    expect(rawResourceKeepRules, contains('tools:keep="@raw/elcim_*"'));
  });
}
