import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/background_tasks.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/media/voice_note_service.dart';
import 'package:flutter_securechat/src/network/network_monitor.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/platform/native_bridge.dart';
import 'package:flutter_securechat/src/services/key_material_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'physical device native privacy and media contract',
    (tester) async {
      await tester.runAsync(_runNativeContract);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _runNativeContract() async {
  await _verifyDeviceKeyStore();

  const bridge = NativeBridge();
  await _verifyNativeBridge(bridge);
  await _verifyBackgroundScheduling();
  await _verifyNetworkMonitor();
  await _verifyVoiceRecording();
  await _verifyWebRtcCapture();
  await _verifyLocalNotifications();

  // Keep this last: on Android this reenables FLAG_SECURE for the activity.
  await bridge.enableScreenProtection();
  debugPrint('[device-native] screen-protection-enabled');
}

Future<void> _verifyDeviceKeyStore() async {
  final store = PlatformKeyMaterialStore();
  final first = await store.readOrCreateMasterKey();
  final second = await store.readOrCreateMasterKey();
  expect(first, hasLength(32));
  expect(second, orderedEquals(first));
  debugPrint('[device-native] keystore-persistent');
}

Future<void> _verifyNativeBridge(NativeBridge bridge) async {
  final readiness = await bridge.getCallReadiness();
  expect(
    readiness.keys,
    containsAll(<String>[
      'battery',
      'fullScreenIntent',
      'notification',
      'overlay',
    ]),
  );
  for (final value in readiness.values) {
    expect(value, isIn(const ['granted', 'denied', 'notApplicable']));
  }
  debugPrint('[device-native] call-readiness-contract');

  expect(await bridge.requestContactsPermission(), isTrue);
  final contacts = await bridge.readContacts();
  const allowedFields = {'displayName', 'phoneNumber', 'avatarUri'};
  for (final contact in contacts) {
    expect(contact.keys.toSet().difference(allowedFields), isEmpty);
    expect(contact['displayName'], isA<String>());
    expect(contact['phoneNumber'], isA<String>());
  }
  // Only the count is logged; device contact data never leaves the process.
  debugPrint('[device-native] contacts-provider rows=${contacts.length}');

  await bridge.registerCallIntegration();
  debugPrint('[device-native] telecom-account-registered');
}

Future<void> _verifyBackgroundScheduling() async {
  const scheduler = WorkmanagerBackgroundScheduler(
    callbackDispatcher: secureChatBackgroundCallbackDispatcher,
  );
  await scheduler.initialize();
  await scheduler.registerRecurringTasks();
  debugPrint('[device-native] workmanager-recurring-tasks-registered');
}

Future<void> _verifyNetworkMonitor() async {
  final monitor = SystemNetworkMonitor();
  try {
    final snapshot = await monitor.start();
    expect(snapshot.transports, isNotEmpty);
    expect(snapshot.kind, isA<dynamic>());
    debugPrint(
      '[device-native] network-monitor '
      '${snapshot.transports.map((item) => item.name).join(',')}',
    );
  } finally {
    await monitor.dispose();
  }
}

Future<void> _verifyVoiceRecording() async {
  final temporary = await getTemporaryDirectory();
  final recordingDirectory = Directory(
    '${temporary.path}/device-native-voice-${DateTime.now().microsecondsSinceEpoch}',
  );
  final recorder = VoiceNoteRecorder(
    backend: PluginVoiceRecorderBackend(),
    recordingDirectory: recordingDirectory,
  );
  String? outputPath;
  try {
    await recorder.start();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await recorder.pause();
    expect(recorder.isPaused, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await recorder.resume();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final draft = await recorder.stop();
    expect(draft, isNotNull);
    outputPath = draft!.attachment.path;
    expect(draft.attachment.fileSize, greaterThan(0));
    expect(draft.metadata.duration, greaterThan(Duration.zero));
    expect(draft.metadata.waveform, isNotEmpty);
    debugPrint('[device-native] microphone-aac-recording');
  } finally {
    await recorder.dispose();
    if (outputPath != null) {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
    }
    if (await recordingDirectory.exists()) {
      await recordingDirectory.delete(recursive: true);
    }
  }
}

Future<void> _verifyWebRtcCapture() async {
  final engine = WebRtcMediaEngine();
  try {
    final offer = await engine.createOffer(
      video: true,
      iceServers: const <IceServerConfig>[],
      onIceCandidate: (_, _, _) {},
    );
    expect(offer, contains('m=audio'));
    expect(offer, contains('m=video'));
    await engine.setMuted(true);
    await engine.setMuted(false);
    await engine.setCameraEnabled(false);
    await engine.setCameraEnabled(true);
    await engine.switchCamera();
    await engine.setSpeakerOn(true);
    await engine.setSpeakerOn(false);
    debugPrint('[device-native] webrtc-camera-microphone-offer');
  } finally {
    await engine.dispose();
  }
}

Future<void> _verifyLocalNotifications() async {
  final presenter = PluginLocalNotificationPresenter();
  try {
    await presenter.initialize();
    await presenter.show(
      const LocalMessageNotification(
        id: 918273,
        title: 'Elcim',
        body: 'Yeni güvenli mesaj',
        payload: 'device-native-qa',
        conversationId: 'device-native-qa',
        count: 1,
        silent: true,
        hideOnLockScreen: true,
      ),
    );
    await presenter.reconcileDismissals();
    await presenter.cancelAll();
    debugPrint('[device-native] secret-local-notification');
  } finally {
    await presenter.dispose();
  }
}
