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
    final service = File(
      '$root/android/app/src/main/kotlin/com/securechat/app/'
      'SecureChatCallService.kt',
    ).readAsStringSync();
    final manifest = File(
      '$root/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(notifications, contains('const val NOTIFICATION_ID = 1200'));
    expect(notifications, contains('CallStyle.forIncomingCall'));
    expect(notifications, contains('CallStyle.forOngoingCall'));
    expect(notifications, contains('setFullScreenIntent'));
    expect(notifications, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(notifications, contains('.notify(NOTIFICATION_ID, notification)'));
    expect(notifications, contains('.cancel(NOTIFICATION_ID)'));
    expect(notifications, contains('SecureChatCallService.start'));
    expect(activity, contains('callNotifications.showIncoming(info)'));
    expect(activity, contains('callNotifications.showConnecting(info)'));
    expect(activity, contains('callNotifications.showEstablished(info)'));
    expect(activity, contains('handleCallNotificationIntent(intent)'));
    expect(connection, contains('pendingActions'));
    expect(connection, contains('callNotifications.showConnecting(info)'));
    expect(service, contains('startForeground('));
    expect(service, contains('FOREGROUND_SERVICE_TYPE_PHONE_CALL'));
    expect(service, contains('NativeCallRegistry.emit("end", callId)'));
    expect(service, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    expect(service, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(manifest, contains('android:name=".SecureChatCallService"'));
    expect(manifest, contains('android:foregroundServiceType="phoneCall"'));
  });
}
