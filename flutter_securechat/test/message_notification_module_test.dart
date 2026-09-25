import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/l10n/service_strings.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final silent in [false, true]) {
    for (final group in [false, true]) {
      test('missed call presentation: silent $silent, group $group', () async {
        final details = <NotificationDetails>[];
        final payloads = <String?>[];
        final presenter = PluginLocalNotificationPresenter(
          strings: ServiceStrings.fixed('en'),
          showNotification:
              ({
                required int id,
                String? title,
                String? body,
                NotificationDetails? notificationDetails,
                String? payload,
              }) async {
                expect(id, 42);
                details.add(notificationDetails!);
                payloads.add(payload);
              },
        );
        addTearDown(presenter.dispose);
        await presenter.showMissedCall(
          MissedCallNotification(
            id: 42,
            callId: 'missed-call',
            peerId: group ? 'group-row' : 'peer',
            peerName: group ? 'Group' : 'Alice',
            callType: CallType.video,
            silent: silent,
            isGroupCall: group,
          ),
        );
        final android = details.single.android!;
        expect(
          android.channelId,
          silent
              ? PluginLocalNotificationPresenter.quietMissedCallChannelId
              : 'missed_call_channel',
        );
        expect(android.playSound, !silent);
        expect(android.enableVibration, !silent);
        expect(android.silent, silent);
        expect(
          android.importance,
          silent ? Importance.low : Importance.defaultImportance,
        );
        expect(
          android.priority,
          silent ? Priority.low : Priority.defaultPriority,
        );
        expect(android.visibility, NotificationVisibility.secret);
        expect(android.category, AndroidNotificationCategory.missedCall);
        expect(
          android.actions!.map((action) => action.id),
          group ? isEmpty : ['call_back'],
        );
        expect(details.single.iOS!.presentSound, !silent);
        expect(details.single.iOS!.presentAlert, isTrue);
        expect(
          details.single.iOS!.categoryIdentifier,
          group ? 'securechat_message' : 'securechat_missed_call',
        );
        expect(payloads.single, group ? 'group-row' : 'missed_call|peer|video');
      });
    }
  }

  test(
    'recreated background coordinator uses persistent unread totals',
    () async {
      final unread = <String, int>{'alice': 2};
      Future<LocalMessageNotification> receive(String conversation) async {
        final input = StreamController<IncomingMessageEvent>.broadcast();
        final presenter = _FakePresenter();
        final coordinator = MessageNotificationCoordinator(
          incomingMessages: input.stream,
          session: SessionStore(
            showNotificationContent: false,
            languagePreference: 'tr',
          ),
          presenter: presenter,
          unreadCounts: () async => Map.of(unread),
        );
        await coordinator.start();
        coordinator.setAppForeground(false);
        input.add(_event(conversationId: conversation));
        await _eventually(() => presenter.shown.isNotEmpty);
        await coordinator.close();
        await input.close();
        return presenter.shown.single;
      }

      expect((await receive('alice')).body, '1 sohbetten 2 yeni mesaj');
      unread['bob'] = 3;
      final summary = await receive('bob');
      expect(summary.body, '2 sohbetten 5 yeni mesaj');
      expect(summary.count, 5);
      expect(summary.payload, isNull);
      unread.remove('alice');
      expect((await receive('bob')).body, '1 sohbetten 3 yeni mesaj');
    },
  );

  test('queued notification is omitted if its conversation was read', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: SessionStore(),
      presenter: presenter,
      unreadCounts: () async => {'other': 4},
    );
    await coordinator.start();
    input.add(_event(conversationId: 'already-read'));
    await Future<void>.delayed(Duration.zero);
    await coordinator.waitForIdle();
    expect(presenter.shown, isEmpty);
    await coordinator.close();
    await input.close();
  });

  test(
    'privacy mode never exposes sender, content or routing payload',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(
          showNotificationContent: false,
          languagePreference: 'tr',
        ),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(false);

      input.add(
        _event(conversationId: 'alice', title: 'Alice', preview: 'secret'),
      );
      await _eventually(() => presenter.shown.isNotEmpty);

      final notification = presenter.shown.single;
      expect(notification.title, 'Elçim');
      expect(notification.body, '1 sohbetten 1 yeni mesaj');
      expect(notification.payload, isNull);
      expect(
        notification.conversationId,
        PluginLocalNotificationPresenter.groupKey,
      );
      expect(notification.hideOnLockScreen, isTrue);
      expect(notification.title, isNot(contains('Alice')));
      expect(notification.body, isNot(contains('secret')));
    },
  );

  test('mute is silent, while a mention overrides conversation mute', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: SessionStore(),
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    coordinator.setAppForeground(false);

    input.add(_event(conversationId: 'muted', isMuted: true));
    input.add(
      _event(conversationId: 'mentioned', isMuted: true, isMention: true),
    );
    await _eventually(() => presenter.shown.length == 2);

    expect(presenter.shown[0].silent, isTrue);
    expect(presenter.shown[1].silent, isFalse);
  });

  test(
    'foreground suppresses only the active chat and alerts for another',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(showNotificationContent: true),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(true);
      coordinator.setActiveConversation('alice');

      input.add(_event(conversationId: 'alice'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(presenter.shown, isEmpty);

      input.add(_event(conversationId: 'bob'));
      await _eventually(() => presenter.shown.length == 1);
      expect(presenter.shown.single.silent, isFalse);
      expect(presenter.shown.single.payload, 'bob');

      final details = <NotificationDetails>[];
      final platformPresenter = PluginLocalNotificationPresenter(
        strings: ServiceStrings.fixed('en'),
        showNotification:
            ({
              required int id,
              String? title,
              String? body,
              NotificationDetails? notificationDetails,
              String? payload,
            }) async => details.add(notificationDetails!),
      );
      addTearDown(platformPresenter.dispose);
      await platformPresenter.show(presenter.shown.single);
      expect(details.single.android!.importance, Importance.high);
      expect(details.single.android!.priority, Priority.high);
      expect(details.single.android!.playSound, isTrue);
      expect(
        details.single.android!.channelId,
        isNot(PluginLocalNotificationPresenter.lowChannelId),
      );
      expect(details.single.iOS!.presentBanner, isTrue);
      expect(details.single.iOS!.presentSound, isTrue);

      coordinator.setActiveConversation('bob');
      input.add(_event(conversationId: 'bob'));
      input.add(_event(conversationId: 'alice'));
      await Future<void>.delayed(Duration.zero);
      await coordinator.waitForIdle();
      expect(presenter.shown, hasLength(2));
      expect(presenter.shown.last.payload, 'alice');
      expect(presenter.shown.last.silent, isFalse);
    },
  );

  test(
    'foreground outside a chat still alerts without exposing private content',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(
          showNotificationContent: false,
          languagePreference: 'tr',
        ),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(true);
      coordinator.setActiveConversation(null);
      input.add(
        _event(conversationId: 'alice', title: 'Alice', preview: 'secret'),
      );
      await _eventually(() => presenter.shown.isNotEmpty);
      final notification = presenter.shown.single;
      expect(notification.silent, isFalse);
      expect(notification.title, 'Elçim');
      expect(notification.body, '1 sohbetten 1 yeni mesaj');
      expect(notification.payload, isNull);
      expect(notification.hideOnLockScreen, isTrue);
    },
  );

  test('foreground respects mute, mention and chosen silent sound', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final session = SessionStore(notificationSound: 'bell');
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: session,
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    coordinator.setAppForeground(true);
    coordinator.setActiveConversation('alice');
    input.add(_event(conversationId: 'muted', isMuted: true));
    input.add(
      _event(conversationId: 'mention', isMuted: true, isMention: true),
    );
    input.add(_event(conversationId: 'custom-silent', customSound: 'silent'));
    input.add(_event(conversationId: 'custom-sound', customSound: 'chime'));
    await _eventually(() => presenter.shown.length == 4);
    expect(presenter.shown.map((item) => item.silent), [
      true,
      false,
      true,
      false,
    ]);
    expect(presenter.shown.last.sound, 'elcim_chime');

    session.notificationSound = 'silent';
    input.add(_event(conversationId: 'global-silent'));
    await _eventually(() => presenter.shown.length == 5);
    expect(presenter.shown.last.silent, isTrue);
  });

  test('active chat alerts in background and again after leaving it', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: SessionStore(showNotificationContent: true),
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    coordinator.setActiveConversation('alice');

    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown, isEmpty);

    coordinator.setAppForeground(false);
    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown.single.count, 1);
    expect(presenter.shown.single.silent, isFalse);

    coordinator.setAppForeground(true);
    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown, hasLength(1));

    coordinator.setActiveConversation(null);
    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown, hasLength(2));
    expect(presenter.shown.last.count, 2);
    expect(presenter.shown.last.silent, isFalse);
  });

  for (final locale in <String, (String, String)>{
    'en': ('1 message from 1 chat', '5 messages from 2 chats'),
    'tr': ('1 sohbetten 1 yeni mesaj', '2 sohbetten 5 yeni mesaj'),
    'de': ('1 Nachricht aus 1 Chat', '5 Nachrichten aus 2 Chats'),
    'ar': ('رسالة واحدة من محادثة واحدة', '5 رسائل من محادثتين'),
  }.entries) {
    test(
      'private summary counts messages and distinct chats in ${locale.key}',
      () async {
        final input = StreamController<IncomingMessageEvent>.broadcast();
        final presenter = _FakePresenter();
        final coordinator = MessageNotificationCoordinator(
          incomingMessages: input.stream,
          session: SessionStore(languagePreference: locale.key),
          presenter: presenter,
        );
        addTearDown(() async {
          await coordinator.close();
          await input.close();
        });
        await coordinator.start();
        coordinator.setActiveConversation('viewed');
        input.add(_event(conversationId: 'viewed'));
        for (final id in ['alice', 'alice', 'bob', 'alice', 'bob']) {
          input.add(
            _event(
              conversationId: id,
              title: 'Private name',
              preview: 'secret',
            ),
          );
        }
        await _drain(coordinator);

        expect(presenter.shown, hasLength(5));
        expect(presenter.shown.first.body, locale.value.$1);
        expect(presenter.shown.last.body, locale.value.$2);
        expect(presenter.shown.map((item) => item.count), [1, 2, 3, 4, 5]);
        for (final notification in presenter.shown) {
          expect(
            notification.id,
            MessageNotificationCoordinator.privacyNotificationId,
          );
          expect(notification.payload, isNull);
          expect(
            notification.conversationId,
            PluginLocalNotificationPresenter.groupKey,
          );
          expect(notification.hideOnLockScreen, isTrue);
          expect(notification.silent, isFalse);
          expect(notification.body, isNot(contains('secret')));
          expect(notification.title, isNot(contains('Private name')));
        }

        await coordinator.clear();
        input.add(_event(conversationId: 'alice'));
        await _drain(coordinator);
        expect(presenter.shown.single.body, locale.value.$1);
        expect(presenter.shown.single.count, 1);
      },
    );
  }

  test('private summary follows session language changes', () async {
    final input = StreamController<IncomingMessageEvent>.broadcast();
    final presenter = _FakePresenter();
    final session = SessionStore(languagePreference: 'en');
    final coordinator = MessageNotificationCoordinator(
      incomingMessages: input.stream,
      session: session,
      presenter: presenter,
    );
    addTearDown(() async {
      await coordinator.close();
      await input.close();
    });
    await coordinator.start();
    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown.single.body, '1 message from 1 chat');
    session.languagePreference = 'tr';
    input.add(_event(conversationId: 'alice'));
    await _drain(coordinator);
    expect(presenter.shown.last.body, '1 sohbetten 2 yeni mesaj');
  });

  test(
    'dismissal clears one conversation count and summary clears all',
    () async {
      final input = StreamController<IncomingMessageEvent>.broadcast();
      final presenter = _FakePresenter();
      final coordinator = MessageNotificationCoordinator(
        incomingMessages: input.stream,
        session: SessionStore(
          showNotificationContent: false,
          languagePreference: 'tr',
        ),
        presenter: presenter,
      );
      addTearDown(() async {
        await coordinator.close();
        await input.close();
      });
      await coordinator.start();
      coordinator.setAppForeground(false);

      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 1);
      presenter.dismissController.add(
        const NotificationDismissal.conversation('alice'),
      );
      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 2);
      expect(presenter.shown.last.count, 1);

      input.add(_event(conversationId: 'bob'));
      await _eventually(() => presenter.shown.length == 3);
      presenter.dismissController.add(const NotificationDismissal.all());
      input.add(_event(conversationId: 'alice'));
      await _eventually(() => presenter.shown.length == 4);
      expect(presenter.shown.last.count, 1);
      expect(presenter.shown.last.body, '1 sohbetten 1 yeni mesaj');
    },
  );
}

IncomingMessageEvent _event({
  required String conversationId,
  String title = 'Peer',
  String preview = 'message',
  bool isMuted = false,
  bool isMention = false,
  String? customSound,
}) => IncomingMessageEvent(
  messageId: 'message-$conversationId',
  conversationId: conversationId,
  title: title,
  preview: preview,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
  isMuted: isMuted,
  isMention: isMention,
  customSound: customSound,
);

class _FakePresenter implements LocalNotificationPresenter {
  final shown = <LocalMessageNotification>[];
  final tapController = StreamController<String>.broadcast();
  final dismissController = StreamController<NotificationDismissal>.broadcast();

  @override
  Stream<String> get taps => tapController.stream;

  @override
  Stream<NotificationDismissal> get dismissals => dismissController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(LocalMessageNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> reconcileDismissals() async {}

  @override
  Future<void> cancelAll() async => shown.clear();
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Notification was not presented before timeout');
}

Future<void> _drain(MessageNotificationCoordinator coordinator) async {
  await Future<void>.delayed(Duration.zero);
  await coordinator.waitForIdle();
}
