import 'package:flutter/foundation.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/native_call_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android CallStyle keeps one notification across call states',
    (tester) async {
      await tester.runAsync(() async {
        final native = MethodChannelNativeCallIntegration();
        const session = CallSession(
          callId: 'device-call-notification-qa',
          peerId: 'private-device-peer',
          peerName: 'Private Device Peer',
          callType: CallType.video,
          direction: CallDirection.incoming,
          state: CallState.ringing,
        );
        try {
          await native.initialize();
          await native.reportIncoming(session);
          debugPrint('[device-call-notification] incoming-posted');
          await Future<void>.delayed(const Duration(seconds: 12));

          await native.setActive(session.callId);
          debugPrint('[device-call-notification] established-posted');
          await Future<void>.delayed(const Duration(seconds: 12));
        } finally {
          await native.end(session.callId);
          await native.dispose();
          debugPrint('[device-call-notification] ended-cancelled');
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
