import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/features/scheduled/scheduled_messages_screen.dart';
import 'package:flutter_securechat/src/features/settings/settings_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/settings_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/widgets/azure_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'privacy switches persist independently and immediately publish hidden presence',
    () async {
      final fixture = await _SettingsFixture.open(connected: true);
      addTearDown(fixture.close);
      await fixture.settings.setShareLastSeen(true);
      await fixture.settings.setShareOnline(false);
      await fixture.settings.setShareReadReceipts(false);
      final restored = SessionStore()..loadJson(fixture.session.toJson());
      expect(restored.shareOnline, isFalse);
      expect(restored.shareReadReceipts, isFalse);
      expect(restored.shareLastSeen, isTrue);
      final presence = fixture.signaling.sentMessages
          .whereType<PresenceUpdateSignal>()
          .last;
      expect(presence.isOnline, isFalse);
      expect(presence.hideLastSeen, isFalse);
    },
  );
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'SpaceGrotesk': 'assets/fonts/space_grotesk_semibold.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('settings groups and scheduled master switch at width $width', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(_SettingsFixture.open))!;
      addTearDown(fixture.close);
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = AppContainer.testing(
        session: fixture.session,
        conversations: InMemoryConversationRepository(
          conversations: [],
          messages: {},
        ),
        crypto: fixture.crypto,
        signaling: fixture.signaling,
        settingsRuntime: AppSettingsRuntime(service: fixture.settings),
        backgroundRuntime: _SettingsBackgroundRuntime(
          fixture.scheduledMessages,
        ),
        callReadinessRuntime: const AppCallReadinessRuntime(
          service: CallReadinessService(
            platform: NotApplicableCallReadinessPlatform(),
          ),
        ),
        chatAccessRuntime: const AppChatAccessRuntime(
          service: ChatAccessService(
            authenticator: AlwaysAllowDeviceOwnerAuthenticator(),
          ),
        ),
      );
      await tester.pumpWidget(
        AppContainerScope(
          container: container,
          child: MaterialApp(
            theme: width == 390
                ? SecureChatTheme.dark()
                : SecureChatTheme.light(),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(width == 320 ? 1.4 : 1),
                padding: const EdgeInsets.only(top: 24, bottom: 34),
              ),
              child: RepaintBoundary(
                key: const ValueKey('settings-capture'),
                child: child!,
              ),
            ),
            home: const SettingsScreen(),
            routes: {
              '/scheduled-messages': (_) => const ScheduledMessagesScreen(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('settings-list')),
      );
      final groups = (list.childrenDelegate as SliverChildListDelegate).children
          .whereType<AzureSurface>()
          .map(
            (group) => (group.child as Column).children.map((boundary) {
              expect(boundary, isA<Semantics>());
              expect((boundary as Semantics).container, isTrue);
              final row = boundary.child!;
              final title = row is ListTile
                  ? row.title
                  : (row as SwitchListTile).title;
              return (title as Text).data;
            }).toList(),
          )
          .toList();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(groups.sublist(1, 6), [
        [l10n.settings_language, l10n.settings_notification_sound],
        [
          l10n.settings_chat_theme,
          l10n.settings_backdrop,
          l10n.settings_fullscreen,
        ],
        [
          l10n.settings_privacy,
          l10n.recovery_email_title,
          l10n.settings_auto_download,
          l10n.settings_call_readiness,
        ],
        [l10n.settings_manage_scheduled],
        [
          l10n.settings_storage_usage,
          l10n.settings_backup,
          l10n.settings_about,
        ],
      ]);
      expect(
        groups.expand((group) => group),
        isNot(contains(l10n.settings_scheduled_messages)),
      );
      await _settingsScreenshot(tester, 'settings-$width');
      await tester.scrollUntilVisible(
        find.text(l10n.settings_manage_scheduled),
        200,
      );
      await tester.pumpAndSettle();
      await _settingsScreenshot(tester, 'settings-lower-$width');
      await tester.tap(find.text(l10n.settings_manage_scheduled));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('scheduled-messages-enabled'));
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      final tabs = find.byType(Tab);
      expect(tabs, findsNWidgets(3));
      final bar = tester.getRect(find.byType(TabBar));
      for (var index = 0; index < 3; index++) {
        final tab = tester.getRect(tabs.at(index));
        expect(
          tab.center.dx,
          closeTo(bar.left + bar.width * (index + .5) / 3, 1),
        );
        expect(tab.left, greaterThanOrEqualTo(bar.left));
        expect(tab.right, lessThanOrEqualTo(bar.right));
      }
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
      await _settingsScreenshot(tester, 'scheduled-$width');
      for (final enabled in [false, true]) {
        await tester.runAsync(() async {
          await tester.tap(toggle);
          // Flush the asynchronous preference write before inspecting UI.
          await fixture.session.persist();
        });
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, enabled);
        expect(fixture.session.scheduledMessagesEnabled, enabled);
      }
      await tester.tap(find.text(l10n.sched_tab_existing));
      await tester.pumpAndSettle();
      expect(find.text(l10n.no_scheduled_messages), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      await tester.tap(find.text(l10n.sched_tab_history));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(toggle, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(toggle)).backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settings_manage_scheduled));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('settings section semantics bounds belong to individual rows', (
    tester,
  ) async {
    await _pumpSettingsForSemantics(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );
    final rows = [
      (label: l10n.settings_chat_theme, type: ListTile),
      (label: l10n.settings_backdrop, type: SwitchListTile),
      (label: l10n.settings_fullscreen, type: SwitchListTile),
    ];
    final bounds = <Rect>[];
    for (final row in rows) {
      final label = find.text(row.label);
      final tile = find.ancestor(of: label, matching: find.byType(row.type));
      expect(tile, findsOneWidget);
      final node = tester.getSemantics(label);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final semanticRect = _globalSemanticsRect(node);
      expect(
        semanticRect,
        rectMoreOrLessEquals(tester.getRect(tile)),
        reason: '${row.label} must not inherit the whole section bounds',
      );
      bounds.add(semanticRect);
    }
    for (var index = 1; index < bounds.length; index++) {
      expect(bounds[index - 1].overlaps(bounds[index]), isFalse);
    }
  });

  testWidgets(
    'settings section semantics theme center opens only the theme dialog',
    (tester) async {
      final fixture = await _pumpSettingsForSemantics(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)),
      );
      final backdropBefore = fixture.session.useDoodleBackground;
      final fullscreenBefore = fixture.session.fullscreenMode;
      final themeNode = tester.getSemantics(
        find.text(l10n.settings_chat_theme),
      );
      final themeBounds = _globalSemanticsRect(themeNode);

      // Android coordinate automation taps the accessibility node's center,
      // not the Text widget's center or SemanticsAction.tap callback.
      await tester.runAsync(() async {
        await tester.tapAt(themeBounds.center);
        await fixture.session.persist();
      });
      await tester.pumpAndSettle();

      expect(
        fixture.session.useDoodleBackground,
        backdropBefore,
        reason: 'Tapping Theme semantics must not toggle Backdrop',
      );
      expect(fixture.session.fullscreenMode, fullscreenBefore);
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(l10n.settings_chat_theme),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone privacy switch is reachable and persists on a narrow screen',
    (tester) async {
      final fixture = (await tester.runAsync(_SettingsFixture.open))!;
      addTearDown(fixture.close);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = AppContainer.testing(
        session: fixture.session,
        conversations: InMemoryConversationRepository(
          conversations: [],
          messages: {},
        ),
        crypto: fixture.crypto,
        signaling: fixture.signaling,
        settingsRuntime: AppSettingsRuntime(service: fixture.settings),
        chatAccessRuntime: const AppChatAccessRuntime(
          service: ChatAccessService(
            authenticator: AlwaysAllowDeviceOwnerAuthenticator(),
          ),
        ),
        callReadinessRuntime: const AppCallReadinessRuntime(
          service: CallReadinessService(
            platform: NotApplicableCallReadinessPlatform(),
          ),
        ),
      );
      await tester.pumpWidget(
        AppContainerScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gizlilik'), 200);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gizlilik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gizlilik'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('settings-share-phone-number'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      for (final enabled in [true, false]) {
        await tester.runAsync(() async {
          await tester.tap(toggle);
          await fixture.session.persist();
        });
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, enabled);
        expect(fixture.session.sharePhoneNumber, enabled);
        expect(tester.takeException(), isNull);
      }
      expect(fixture.signaling.sentMessages, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  test(
    'preferences persist only inside the encrypted session envelope',
    () async {
      final fixture = await _SettingsFixture.open();
      addTearDown(fixture.close);

      await fixture.settings.setTheme(AppThemePreference.dark);
      await fixture.settings.setLanguage(AppLanguagePreference.ar);
      await fixture.settings.setShowNotificationContent(false);
      await fixture.settings.setNotificationSound(
        NotificationSoundPreference.silent,
      );
      await fixture.settings.setUseDoodleBackground(false);
      await fixture.settings.setFullscreenMode(true);
      await fixture.settings.setSharePhoneNumber(true);

      final reopened = await PersistentSessionStore.open(
        file: fixture.sessionFile,
        crypto: fixture.crypto,
      );
      expect(reopened.themePreference, 'dark');
      expect(reopened.languagePreference, 'ar');
      expect(reopened.showNotificationContent, isFalse);
      expect(reopened.notificationSound, 'silent');
      expect(reopened.useDoodleBackground, isFalse);
      expect(reopened.fullscreenMode, isTrue);
      expect(reopened.sharePhoneNumber, isTrue);
      expect(fixture.fullscreen.values, [true]);

      final raw = await fixture.sessionFile.readAsString();
      expect(raw, isNot(contains('themePreference')));
      expect(raw, isNot(contains('languagePreference')));
      expect(raw, isNot(contains('access-secret')));
      expect(raw, isNot(contains('sharePhoneNumber')));
      await reopened.close();
    },
  );

  test(
    'phone sharing is opt-in and switching it does not broadcast identity',
    () async {
      final fixture = await _SettingsFixture.open(connected: true);
      addTearDown(fixture.close);
      expect(fixture.settings.current.sharePhoneNumber, isFalse);
      await fixture.settings.setSharePhoneNumber(true);
      expect(fixture.settings.current.sharePhoneNumber, isTrue);
      await fixture.settings.setSharePhoneNumber(false);
      expect(fixture.settings.current.sharePhoneNumber, isFalse);
      expect(fixture.signaling.sentMessages, isEmpty);
      final reopened = await PersistentSessionStore.open(
        file: fixture.sessionFile,
        crypto: fixture.crypto,
      );
      expect(reopened.sharePhoneNumber, isFalse);
      await reopened.close();
    },
  );

  test('legacy sessions, logout and account changes do not inherit opt-in', () {
    final session = SessionStore()..loadJson({'userId': 'old-account'});
    expect(session.sharePhoneNumber, isFalse);
    session.sharePhoneNumber = true;
    session.login(
      userId: 'new-account',
      displayName: 'New',
      phoneNumber: '+905550001122',
      accessToken: 'token',
      refreshToken: 'refresh',
    );
    expect(session.sharePhoneNumber, isFalse);
    session.sharePhoneNumber = true;
    session.clear();
    expect(session.sharePhoneNumber, isFalse);
  });

  test(
    'restoring a different profile does not inherit phone disclosure consent',
    () async {
      final session = SessionStore(
        userId: 'old-account',
        sharePhoneNumber: true,
      );
      await session.restoreProfileAndPersist(
        userId: 'restored-account',
        displayName: 'Restored',
        phoneNumber: '+905550001122',
      );
      expect(session.sharePhoneNumber, isFalse);
    },
  );

  test(
    'last-seen preference is persisted and announced while online',
    () async {
      final fixture = await _SettingsFixture.open(connected: true);
      addTearDown(fixture.close);

      await fixture.settings.setShareLastSeen(false);

      expect(fixture.session.shareLastSeen, isFalse);
      final presence = fixture.signaling.sentMessages
          .whereType<PresenceUpdateSignal>()
          .single;
      expect(presence.senderId, 'me');
      expect(presence.recipientId, 'server');
      expect(presence.isOnline, isTrue);
      expect(presence.hideLastSeen, isTrue);
    },
  );

  test(
    'global scheduled-message switch cancels and restores active plans',
    () async {
      final fixture = await _SettingsFixture.open();
      addTearDown(fixture.close);
      final plan = ScheduledMessageEntity(
        id: 'plan-1',
        messageContent: 'encrypted later',
        repeatType: 'DAILY',
        hour: 12,
        minute: 0,
        recipientIds: 'alice',
        recipientNames: 'Alice',
        nextTriggerTime: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      );
      await fixture.database.scheduledMessages.insert(plan);

      await fixture.settings.setScheduledMessagesEnabled(false);
      expect(fixture.scheduler.cancelled, ['plan-1']);
      expect(fixture.session.scheduledMessagesEnabled, isFalse);

      await fixture.settings.setScheduledMessagesEnabled(true);
      expect(fixture.scheduler.scheduled.map((item) => item.id), ['plan-1']);
      expect(fixture.session.scheduledMessagesEnabled, isTrue);
    },
  );

  test(
    'profile photo is retained in the managed directory and removable',
    () async {
      final fixture = await _SettingsFixture.open();
      addTearDown(fixture.close);
      final source = File('${fixture.directory.path}/selected.png');
      await source.writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
      final attachment = await MediaAttachment.fromPath(
        source.path,
        mimeType: 'image/png',
      );

      final retained = await fixture.settings.updateProfilePhoto(attachment);

      expect(File(retained).parent.path, fixture.profileDirectory.path);
      expect(await File(retained).readAsBytes(), [0x89, 0x50, 0x4e, 0x47]);
      expect(fixture.session.profilePhotoUri, retained);
      expect(await source.exists(), isTrue);

      await fixture.settings.removeProfilePhoto();
      expect(await File(retained).exists(), isFalse);
      expect(fixture.session.profilePhotoUri, isNull);
    },
  );
}

Future<_SettingsFixture> _pumpSettingsForSemantics(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_SettingsFixture.open))!;
  addTearDown(fixture.close);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = AppContainer.testing(
    session: fixture.session,
    conversations: InMemoryConversationRepository(
      conversations: [],
      messages: {},
    ),
    crypto: fixture.crypto,
    signaling: fixture.signaling,
    settingsRuntime: AppSettingsRuntime(service: fixture.settings),
    callReadinessRuntime: const AppCallReadinessRuntime(
      service: CallReadinessService(
        platform: NotApplicableCallReadinessPlatform(),
      ),
    ),
    chatAccessRuntime: const AppChatAccessRuntime(
      service: ChatAccessService(
        authenticator: AlwaysAllowDeviceOwnerAuthenticator(),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        theme: SecureChatTheme.dark(),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Rect _globalSemanticsRect(SemanticsNode node) {
  var rect = node.rect;
  for (
    SemanticsNode? ancestor = node;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    final transform = ancestor.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

class _SettingsFixture {
  _SettingsFixture({
    required this.directory,
    required this.profileDirectory,
    required this.sessionFile,
    required this.crypto,
    required this.database,
    required this.session,
    required this.signaling,
    required this.scheduler,
    required this.fullscreen,
    required this.settings,
    required this.scheduledMessages,
  });

  final Directory directory;
  final Directory profileDirectory;
  final File sessionFile;
  final LocalAeadCryptoService crypto;
  final SecureChatDatabase database;
  final PersistentSessionStore session;
  final InMemorySignalingService signaling;
  final _FakeScheduler scheduler;
  final _FakeFullscreenController fullscreen;
  final SettingsService settings;
  final ScheduledMessageService scheduledMessages;

  static Future<_SettingsFixture> open({bool connected = false}) async {
    final directory = await Directory.systemTemp.createTemp('settings_test_');
    final profileDirectory = Directory('${directory.path}/profile');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 33 + index)),
    );
    final sessionFile = File('${directory.path}/session.securejson');
    final session = await PersistentSessionStore.open(
      file: sessionFile,
      crypto: crypto,
    );
    await session.loginAndPersist(
      userId: 'me',
      displayName: 'Me',
      phoneNumber: '+90000',
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: crypto,
    );
    final signaling = InMemorySignalingService();
    if (connected) {
      await signaling.connect(
        userId: 'me',
        url: 'ws://local',
        accessToken: 'access-secret',
      );
    }
    final scheduler = _FakeScheduler();
    final scheduledMessages = ScheduledMessageService(
      dao: database.scheduledMessages,
      sender: SendMessageUseCase(
        database: database,
        signaling: signaling,
        session: session,
        crypto: crypto,
        maxRetryCount: 0,
        retryDelay: Duration.zero,
      ),
      signaling: signaling,
      session: session,
      scheduler: scheduler,
    );
    final fullscreen = _FakeFullscreenController();
    final settings = SettingsService(
      session: session,
      signaling: signaling,
      scheduledMessages: scheduledMessages,
      profileDirectory: profileDirectory,
      fullscreen: fullscreen,
    );
    return _SettingsFixture(
      directory: directory,
      profileDirectory: profileDirectory,
      sessionFile: sessionFile,
      crypto: crypto,
      database: database,
      session: session,
      signaling: signaling,
      scheduler: scheduler,
      fullscreen: fullscreen,
      settings: settings,
      scheduledMessages: scheduledMessages,
    );
  }

  Future<void> close() async {
    await settings.close();
    await database.close();
    await session.close();
    await signaling.dispose();
    await directory.delete(recursive: true);
  }
}

class _SettingsBackgroundRuntime implements AppBackgroundRuntime {
  _SettingsBackgroundRuntime(this.scheduledMessages);
  @override
  final ScheduledMessageService scheduledMessages;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settingsScreenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['SETTINGS_UI_SCREENSHOTS'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('settings-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(path)..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _FakeScheduler implements BackgroundScheduler {
  final scheduled = <ScheduledMessageEntity>[];
  final cancelled = <String>[];

  @override
  Future<void> cancelScheduledMessage(String id) async => cancelled.add(id);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerRecurringTasks() async {}

  @override
  Future<void> scheduleMessage(ScheduledMessageEntity message) async {
    scheduled.add(message);
  }
}

class _FakeFullscreenController implements FullscreenController {
  final values = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async => values.add(enabled);
}
