import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/network/network_monitor.dart';
import 'package:flutter_securechat/src/services/app_lifecycle_coordinator.dart';
import 'package:flutter_securechat/src/services/async_operation_tracker.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';

void main() {
  group('transfer activity', () {
    test(
      'retains background transport and monitor but publishes offline',
      () async {
        final h = _LifecycleHarness();
        await h.lifecycle.enterForeground();
        h.transfers.add(true);
        h.calls.add(false);
        await h.lifecycle.enterBackground();
        await h.lifecycle.enterBackground();

        expect(h.lifecycle.isForeground, isFalse);
        expect(h.signaling.currentStatus.isConnected, isTrue);
        expect(h.gateway.controller.hasListener, isTrue);
        expect(h.presence, [true, false]);
      },
    );

    test('completion releases background transport and monitor', () async {
      final h = _LifecycleHarness();
      await h.lifecycle.enterForeground();
      h.transfers.add(true);
      await h.lifecycle.enterBackground();
      h.transfers.add(false);
      await _eventLoop();

      expect(h.signaling.currentStatus.isConnected, isFalse);
      expect(h.signaling.currentUserId, isNull);
      expect(h.gateway.controller.hasListener, isFalse);
      expect(h.presence, [true, false]);
      final changes = List<bool>.of(h.signaling.networkChanges);
      h.gateway.emit(NetworkTransport.cellular);
      await _eventLoop();
      expect(h.signaling.networkChanges, changes);
    });

    for (final callEndsFirst in [true, false]) {
      test(
        'call and transfer retain independently (call ends first: $callEndsFirst)',
        () async {
          final h = _LifecycleHarness();
          await h.lifecycle.enterForeground();
          h.calls.add(true);
          h.transfers.add(false);
          await h.lifecycle.enterBackground();
          expect(h.signaling.currentStatus.isConnected, isTrue);
          h.transfers.add(true);
          await _eventLoop();

          (callEndsFirst ? h.calls : h.transfers).add(false);
          await _eventLoop();
          expect(h.signaling.currentStatus.isConnected, isTrue);
          expect(h.gateway.controller.hasListener, isTrue);
          (callEndsFirst ? h.transfers : h.calls).add(false);
          await _eventLoop();
          expect(h.signaling.currentStatus.isConnected, isFalse);
          expect(h.gateway.controller.hasListener, isFalse);
          expect(h.presence, [true, false]);
        },
      );
    }

    test(
      'foreground completion leaves transport and monitoring connected',
      () async {
        final h = _LifecycleHarness();
        await h.lifecycle.enterForeground();
        h.transfers.add(true);
        h.transfers.add(false);
        await _eventLoop();
        expect(h.lifecycle.isForeground, isTrue);
        expect(h.signaling.currentStatus.isConnected, isTrue);
        expect(h.gateway.controller.hasListener, isTrue);
        await h.lifecycle.enterBackground();
        expect(h.signaling.currentStatus.isConnected, isFalse);
        expect(h.gateway.controller.hasListener, isFalse);
      },
    );

    test('logged-out activity cannot retain background resources', () async {
      final h = _LifecycleHarness();
      await h.lifecycle.enterForeground();
      h.transfers.add(true);
      await h.lifecycle.enterBackground();
      h.session.clear();
      await h.lifecycle.enterBackground();
      expect(h.signaling.currentStatus.isConnected, isFalse);
      expect(h.gateway.controller.hasListener, isFalse);
      h.transfers.add(false);
      h.transfers.add(true);
      h.calls.add(true);
      await _eventLoop();
      expect(h.signaling.currentStatus.isConnected, isFalse);
      expect(h.gateway.controller.hasListener, isFalse);
    });

    test(
      'network loss and recovery work during a background transfer',
      () async {
        final h = _LifecycleHarness();
        await h.lifecycle.enterForeground();
        h.transfers.add(true);
        await h.lifecycle.enterBackground();
        h.gateway.emit(NetworkTransport.none);
        await _eventLoop();
        expect(h.signaling.currentStatus.isConnected, isFalse);
        expect(h.signaling.currentUserId, 'me');
        h.gateway.emit(NetworkTransport.cellular);
        await _eventLoop();
        expect(h.signaling.currentStatus.isConnected, isTrue);
        expect(h.signaling.networkChanges, [true, false, true]);
        expect(h.lifecycle.isForeground, isFalse);
        expect(h.presence, [true, false]);
        h.transfers.add(false);
        await _eventLoop();
        expect(h.signaling.currentStatus.isConnected, isFalse);
        expect(h.gateway.controller.hasListener, isFalse);
      },
    );

    for (final background in [true, false]) {
      test(
        'dispose cancels both activities and releases resources (background: $background)',
        () async {
          final h = _LifecycleHarness();
          await h.lifecycle.enterForeground();
          h.calls.add(true);
          h.transfers.add(true);
          if (background) await h.lifecycle.enterBackground();
          final first = h.lifecycle.dispose();
          expect(identical(first, h.lifecycle.dispose()), isTrue);
          await first;
          expect(h.calls.hasListener, isFalse);
          expect(h.transfers.hasListener, isFalse);
          expect(h.gateway.controller.hasListener, isFalse);
          expect(h.signaling.currentStatus.isConnected, isFalse);
          expect(h.lifecycle.isForeground, isFalse);
          final changes = List<bool>.of(h.signaling.networkChanges);
          h.calls.add(true);
          h.transfers.add(true);
          h.gateway.emit(NetworkTransport.cellular);
          await _eventLoop();
          expect(h.signaling.networkChanges, changes);
          expect(h.signaling.currentStatus.isConnected, isFalse);
          expect(h.lifecycle.enterForeground, throwsStateError);
        },
      );
    }

    test(
      'dispose releases resources even when offline presence fails',
      () async {
        final signaling = _FailingSignaling();
        final h = _LifecycleHarness(signaling: signaling);
        await h.lifecycle.enterForeground();
        h.transfers.add(true);
        signaling.failOfflinePresence = true;
        await expectLater(h.lifecycle.dispose(), throwsStateError);
        expect(h.calls.hasListener, isFalse);
        expect(h.transfers.hasListener, isFalse);
        expect(h.gateway.controller.hasListener, isFalse);
        expect(signaling.currentStatus.isConnected, isFalse);
      },
    );

    test(
      'transfer callback failures are reported and do not poison transitions',
      () async {
        final signaling = _FailingSignaling();
        final failures = <String>[];
        final h = _LifecycleHarness(
          signaling: signaling,
          onAsyncFailure: (operation, error, stackTrace) {
            failures.add(operation);
            throw StateError('diagnostics unavailable');
          },
        );
        await h.lifecycle.enterForeground();
        h.transfers.add(true);
        await h.lifecycle.enterBackground();
        signaling.failNextDisconnect = true;
        h.transfers.add(false);
        await _eventLoop();
        expect(failures, ['lifecycle.transfer-activity']);
        expect(h.gateway.controller.hasListener, isFalse);
        h.transfers.add(true);
        h.transfers.add(false);
        await _eventLoop();
        expect(signaling.currentStatus.isConnected, isFalse);
        expect(h.gateway.controller.hasListener, isFalse);
        await h.lifecycle.enterForeground();
        expect(signaling.currentStatus.isConnected, isTrue);
      },
    );
  });

  test('hidden online status keeps transport active across resume', () async {
    final session = SessionStore(
      userId: 'me',
      accessToken: 'access',
      shareOnline: false,
      shareLastSeen: false,
    );
    final signaling = InMemorySignalingService();
    final lifecycle = AppLifecycleCoordinator(
      session: session,
      signaling: signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async {},
      refreshPushRegistration: () async {},
    );
    addTearDown(signaling.dispose);
    addTearDown(lifecycle.dispose);
    await lifecycle.enterForeground();
    await lifecycle.enterBackground();
    await lifecycle.enterForeground();
    expect(signaling.currentStatus.isConnected, isTrue);
    final signals = signaling.sentMessages.whereType<PresenceUpdateSignal>();
    expect(signals, isNotEmpty);
    expect(
      signals.every((signal) => !signal.isOnline && signal.hideLastSeen),
      isTrue,
    );
  });
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

class _LifecycleHarness {
  _LifecycleHarness({
    InMemorySignalingService? signaling,
    AsyncOperationFailureHandler? onAsyncFailure,
  }) : signaling = signaling ?? InMemorySignalingService() {
    monitor = SystemNetworkMonitor(gateway: gateway);
    lifecycle = AppLifecycleCoordinator(
      session: session,
      signaling: this.signaling,
      signalingUrl: 'wss://test.invalid',
      foregroundMaintenance: () async {},
      refreshPushRegistration: () async {},
      networkMonitor: monitor,
      callActivity: calls.stream,
      transferActivity: transfers.stream,
      onAsyncFailure: onAsyncFailure,
    );
    addTearDown(() async {
      try {
        await lifecycle.dispose();
      } catch (_) {
        // Explicit disposal-failure tests already assert the returned error.
      }
      await calls.close();
      await transfers.close();
      await monitor.dispose();
      await gateway.controller.close();
      await this.signaling.dispose();
    });
  }

  final session = SessionStore(userId: 'me', accessToken: 'access');
  final InMemorySignalingService signaling;
  final calls = StreamController<bool>(sync: true);
  final transfers = StreamController<bool>(sync: true);
  final gateway = _ConnectivityGateway();
  late final SystemNetworkMonitor monitor;
  late final AppLifecycleCoordinator lifecycle;

  Iterable<bool> get presence => signaling.sentMessages
      .whereType<PresenceUpdateSignal>()
      .map((signal) => signal.isOnline);
}

class _ConnectivityGateway implements ConnectivityGateway {
  final controller = StreamController<List<NetworkTransport>>.broadcast();
  var current = [NetworkTransport.wifi];

  @override
  Future<List<NetworkTransport>> checkConnectivity() async => current;

  @override
  Stream<List<NetworkTransport>> get connectivityChanges => controller.stream;

  void emit(NetworkTransport transport) {
    current = [transport];
    controller.add(current);
  }
}

class _FailingSignaling extends InMemorySignalingService {
  bool failOfflinePresence = false;
  bool failNextDisconnect = false;

  @override
  Future<bool> send(SignalMessage message) async {
    if (failOfflinePresence &&
        message is PresenceUpdateSignal &&
        !message.isOnline) {
      throw StateError('presence unavailable');
    }
    return super.send(message);
  }

  @override
  Future<void> disconnect() async {
    if (failNextDisconnect) {
      failNextDisconnect = false;
      throw StateError('disconnect failed');
    }
    await super.disconnect();
  }
}

Future<void> _eventLoop() => Future<void>.delayed(Duration.zero);
