import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/services/app_lifecycle_coordinator.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';

void main() {
  test('screen lock retains call transport until the call ends', () async {
    final signaling = InMemorySignalingService();
    final calls = StreamController<bool>();
    final lifecycle = AppLifecycleCoordinator(
      session: SessionStore(userId: 'me', accessToken: 'access'),
      signaling: signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async {},
      refreshPushRegistration: () async {},
      callActivity: calls.stream,
    );
    addTearDown(signaling.dispose);
    addTearDown(calls.close);
    addTearDown(lifecycle.dispose);
    await lifecycle.enterForeground();
    calls.add(true);
    await Future<void>.delayed(Duration.zero);
    await lifecycle.enterBackground();
    await lifecycle.enterBackground();
    expect(lifecycle.isForeground, isFalse);
    expect(signaling.currentStatus.isConnected, isTrue);
    expect(
      signaling.sentMessages.whereType<PresenceUpdateSignal>().last.isOnline,
      isFalse,
    );
    await lifecycle.enterForeground();
    expect(signaling.currentStatus.isConnected, isTrue);
    await lifecycle.enterBackground();
    calls.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(signaling.currentStatus.isConnected, isFalse);
  });

  test('disposal releases transport even with a background call', () async {
    final signaling = InMemorySignalingService();
    final calls = StreamController<bool>();
    final lifecycle = AppLifecycleCoordinator(
      session: SessionStore(userId: 'me', accessToken: 'access'),
      signaling: signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async {},
      refreshPushRegistration: () async {},
      callActivity: calls.stream,
    );
    addTearDown(signaling.dispose);
    addTearDown(calls.close);
    addTearDown(lifecycle.dispose);
    await lifecycle.enterForeground();
    calls.add(true);
    await Future<void>.delayed(Duration.zero);
    await lifecycle.enterBackground();
    expect(signaling.currentStatus.isConnected, isTrue);
    await lifecycle.dispose();
    expect(signaling.currentStatus.isConnected, isFalse);
  });

  test(
    'resume refreshes external state before opening socket or maintenance',
    () async {
      final signaling = InMemorySignalingService();
      final session = SessionStore();
      var refreshes = 0;
      final lifecycle = AppLifecycleCoordinator(
        session: session,
        signaling: signaling,
        signalingUrl: 'wss://test.invalid',
        refreshLocalState: () async {
          expect(signaling.currentStatus.isConnected, isFalse);
          refreshes++;
          session.login(
            userId: 'me',
            displayName: 'A',
            phoneNumber: '',
            accessToken: 'access',
            refreshToken: 'refresh',
          );
        },
        foregroundMaintenance: () async => expect(refreshes, greaterThan(0)),
        refreshPushRegistration: () async {},
      );
      addTearDown(signaling.dispose);
      addTearDown(lifecycle.dispose);
      await lifecycle.enterForeground();
      expect(signaling.currentStatus.isConnected, isTrue);
      await lifecycle.enterForeground();
      expect(refreshes, 1);
      await lifecycle.enterBackground();
      await lifecycle.enterForeground();
      expect(refreshes, 2);
    },
  );

  test(
    'failed refresh does not open stale socket and next resume can retry',
    () async {
      final signaling = InMemorySignalingService();
      var fail = true;
      final lifecycle = AppLifecycleCoordinator(
        session: SessionStore(userId: 'me', accessToken: 'access'),
        signaling: signaling,
        signalingUrl: 'wss://test.invalid',
        refreshLocalState: () async {
          if (fail) throw StateError('unreadable storage');
        },
        foregroundMaintenance: () async {},
        refreshPushRegistration: () async {},
      );
      addTearDown(signaling.dispose);
      addTearDown(lifecycle.dispose);
      await expectLater(lifecycle.enterForeground(), throwsStateError);
      expect(lifecycle.isForeground, isFalse);
      expect(signaling.currentStatus.isConnected, isFalse);
      fail = false;
      await lifecycle.enterForeground();
      expect(signaling.currentStatus.isConnected, isTrue);
    },
  );

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
