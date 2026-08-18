import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/app_lifecycle_coordinator.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';

void main() {
  test(
    'foreground connects, publishes presence and refreshes maintenance',
    () async {
      final signaling = InMemorySignalingService();
      final session = SessionStore(
        userId: 'me',
        accessToken: 'access',
        refreshToken: 'refresh',
        shareLastSeen: false,
      );
      var maintenanceRuns = 0;
      var pushRefreshes = 0;
      final lifecycle = AppLifecycleCoordinator(
        session: session,
        signaling: signaling,
        signalingUrl: 'wss://test.invalid',
        foregroundMaintenance: () async => maintenanceRuns++,
        refreshPushRegistration: () async => pushRefreshes++,
      );

      await lifecycle.enterForeground();
      await lifecycle.enterForeground();

      expect(lifecycle.isForeground, isTrue);
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(signaling.currentUserId, 'me');
      expect(maintenanceRuns, 1);
      expect(pushRefreshes, 1);
      final online = signaling.sentMessages.whereType<PresenceUpdateSignal>();
      expect(online, hasLength(1));
      expect(online.single.isOnline, isTrue);
      expect(online.single.hideLastSeen, isTrue);
      expect(online.single.recipientId, 'server');
    },
  );

  test(
    'background sends offline before disconnect and resume reconnects',
    () async {
      final signaling = InMemorySignalingService();
      final lifecycle = AppLifecycleCoordinator(
        session: SessionStore(userId: 'me', accessToken: 'access'),
        signaling: signaling,
        signalingUrl: 'wss://test.invalid',
        foregroundMaintenance: () async {},
        refreshPushRegistration: () async {},
      );

      await lifecycle.enterForeground();
      await lifecycle.enterBackground();
      await lifecycle.enterBackground();

      expect(lifecycle.isForeground, isFalse);
      expect(signaling.currentStatus.isConnected, isFalse);
      final presence = signaling.sentMessages.whereType<PresenceUpdateSignal>();
      expect(presence.map((signal) => signal.isOnline), [true, false]);

      await lifecycle.enterForeground();
      expect(signaling.currentStatus.isConnected, isTrue);
      expect(
        signaling.sentMessages.whereType<PresenceUpdateSignal>().last.isOnline,
        isTrue,
      );
    },
  );

  test('logged-out foreground runs cleanup without opening a socket', () async {
    final signaling = InMemorySignalingService();
    var maintenanceRuns = 0;
    var pushRefreshes = 0;
    final lifecycle = AppLifecycleCoordinator(
      session: SessionStore(),
      signaling: signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async => maintenanceRuns++,
      refreshPushRegistration: () async => pushRefreshes++,
    );

    await lifecycle.enterForeground();

    expect(maintenanceRuns, 1);
    expect(pushRefreshes, 0);
    expect(signaling.currentStatus.isConnected, isFalse);
    expect(signaling.sentMessages, isEmpty);
  });
}
