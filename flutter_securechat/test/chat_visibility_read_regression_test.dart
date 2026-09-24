import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/widgets/main_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  for (final outOfOrder in [false, true]) {
    testWidgets(
      'covered chat keeps ${outOfOrder ? 'out-of-order' : 'new'} arrivals '
      'unread and marks them read on return',
      (tester) async {
        final fixture = await _Fixture.open(tester);
        await fixture.openChat('alice');
        final readsBeforeCover = fixture.repository.readCalls('alice');
        expect(fixture.repository.conversation('alice').unreadCount, 0);

        unawaited(
          fixture.navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await fixture.arrive('alice', outOfOrder: outOfOrder);
        expect(fixture.repository.conversation('alice').unreadCount, 1);
        expect(fixture.repository.readCalls('alice'), readsBeforeCover);
        expect(fixture.presenter.shown, hasLength(1));

        fixture.navigator.pop();
        await tester.pumpAndSettle();
        expect(fixture.repository.conversation('alice').unreadCount, 0);
        expect(fixture.repository.readCalls('alice'), readsBeforeCover + 1);

        fixture.repository.replayMessages('alice');
        await tester.pumpAndSettle();
        expect(
          fixture.repository.readCalls('alice'),
          readsBeforeCover + 1,
          reason: 'Repeated snapshots must not repeat the same read write',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('paused arrivals stay unread until the visible chat resumes', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.openChat('alice');
    final readsBeforePause = fixture.repository.readCalls('alice');
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    await fixture.arrive('alice');
    expect(fixture.repository.conversation('alice').unreadCount, 1);
    expect(fixture.repository.readCalls('alice'), readsBeforePause);
    expect(fixture.presenter.shown, hasLength(1));

    _resume(tester);
    await tester.pumpAndSettle();
    expect(fixture.repository.conversation('alice').unreadCount, 0);
    expect(fixture.repository.readCalls('alice'), readsBeforePause + 1);
    await fixture.arrive('alice');
    expect(fixture.repository.conversation('alice').unreadCount, 0);
    expect(
      fixture.presenter.shown,
      hasLength(1),
      reason: 'Resumed visible chat should suppress its notifications',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an older chat cannot clear the newer route owner', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.openChat('alice');
    final oldRoute = ModalRoute.of(tester.element(find.byType(ChatScreen)))!;
    await fixture.openChat('bob');
    expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));

    fixture.navigator.removeRoute(oldRoute);
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    await fixture.arrive('bob');
    expect(
      fixture.presenter.shown,
      isEmpty,
      reason: 'Old dispose must not clear the visible Bob route owner',
    );
    expect(fixture.repository.conversation('bob').unreadCount, 0);

    await fixture.arrive('alice');
    expect(fixture.presenter.shown.single.payload, 'alice');
    expect(fixture.repository.conversation('alice').unreadCount, 1);
    fixture.navigator.pop();
    await tester.pumpAndSettle();
    await fixture.arrive('bob');
    expect(fixture.presenter.shown.last.payload, 'bob');
    expect(fixture.presenter.shown, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture(this.tester);

  final WidgetTester tester;
  final repository = _ReadTrackingRepository();
  final incoming = StreamController<IncomingMessageEvent>.broadcast();
  final presenter = _RecordingPresenter();
  late final MessageNotificationCoordinator coordinator;
  late final NavigatorState navigator;

  static Future<_Fixture> open(WidgetTester tester) async {
    final fixture = _Fixture(tester);
    final base = createWidgetTestContainer();
    base.session.showNotificationContent = true;
    fixture.coordinator = MessageNotificationCoordinator(
      incomingMessages: fixture.incoming.stream,
      session: base.session,
      presenter: fixture.presenter,
    );
    await fixture.coordinator.start();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _resume(tester);
      await fixture.coordinator.close();
      await fixture.incoming.close();
      await fixture.repository.close();
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      SecureChatFlutterApp(
        container: AppContainer.testing(
          session: base.session,
          conversations: fixture.repository,
          crypto: base.crypto,
          signaling: base.signaling,
          chatAccessRuntime: base.chatAccessRuntime,
          callReadinessRuntime: base.callReadinessRuntime,
          notificationRuntime: AppNotificationRuntime(
            coordinator: fixture.coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fixture.navigator = Navigator.of(tester.element(find.byType(MainShell)));
    return fixture;
  }

  Future<void> openChat(String id) async {
    unawaited(
      navigator.pushNamed<void>(
        '/chat',
        arguments: repository.conversation(id),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> arrive(String id, {bool outOfOrder = false}) async {
    final message = await repository.arrive(id, outOfOrder: outOfOrder);
    incoming.add(
      IncomingMessageEvent(
        messageId: message.id,
        conversationId: id,
        title: 'Test sender',
        preview: 'Test message',
        timestamp: message.timestamp,
        isMuted: false,
        isMention: false,
      ),
    );
    await tester.pumpAndSettle();
    await coordinator.waitForIdle();
  }
}

class _ReadTrackingRepository extends InMemoryConversationRepository {
  factory _ReadTrackingRepository() => _ReadTrackingRepository._([
    for (final id in ['alice', 'bob'])
      Conversation(id: id, peerId: id, peerName: id, peerPhone: ''),
  ]);

  _ReadTrackingRepository._(this._items)
    : super(conversations: _items, messages: {});

  final List<Conversation> _items;
  final _histories = <String, List<LocalMessage>>{};
  final _updates = <String, StreamController<List<LocalMessage>>>{};
  final _readCalls = <String, int>{};
  int _serial = 0;
  static final _seedTime = DateTime.utc(2026, 1, 1, 12);

  Conversation conversation(String id) => _items.singleWhere((c) => c.id == id);
  int readCalls(String id) => _readCalls[id] ?? 0;

  List<LocalMessage> _history(String id) =>
      _histories.putIfAbsent(id, () => [_message(id, 'seed-$id', _seedTime)]);

  @override
  Stream<List<LocalMessage>> watchMessages(String conversationId) async* {
    final updates = _updates.putIfAbsent(
      conversationId,
      () => StreamController<List<LocalMessage>>.broadcast(),
    );
    yield List.of(_history(conversationId));
    yield* updates.stream;
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    _readCalls.update(conversationId, (count) => count + 1, ifAbsent: () => 1);
    await super.markConversationRead(conversationId);
  }

  Future<LocalMessage> arrive(String id, {required bool outOfOrder}) async {
    final serial = ++_serial;
    final message = _message(
      id,
      'arrival-$serial',
      _seedTime.add(Duration(minutes: outOfOrder ? -serial : serial)),
    );
    _history(id).add(message);
    final index = _items.indexWhere((item) => item.id == id);
    _items[index] = _items[index].copyWith(
      unreadCount: _items[index].unreadCount + 1,
    );
    // Publish the updated list using the in-memory repository's normal stream.
    await setPinned(id, _items[index].isPinned);
    replayMessages(id);
    return message;
  }

  void replayMessages(String id) => _updates[id]?.add(List.of(_history(id)));

  Future<void> close() async {
    for (final controller in _updates.values) {
      await controller.close();
    }
  }

  static LocalMessage _message(String peerId, String id, DateTime timestamp) =>
      LocalMessage(
        id: id,
        conversationId: peerId,
        senderId: peerId,
        peerId: peerId,
        content: 'Test message',
        contentType: MessageContentType.text,
        timestamp: timestamp,
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
}

class _RecordingPresenter implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];

  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Stream<NotificationDismissal> get dismissals => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show(LocalMessageNotification notification) async =>
      shown.add(notification);
  @override
  Future<void> reconcileDismissals() async {}
  @override
  Future<void> cancelAll() async => shown.clear();
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
