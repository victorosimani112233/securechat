import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/settings_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  late _LocalizationFixture fixture;
  setUpAll(() async => fixture = await _LocalizationFixture.open());
  tearDownAll(() async => fixture.close());

  test('Flutter catalogs contain every Kotlin Turkish and English key', () {
    for (final locale in ['tr', 'en']) {
      final source = File(
        locale == 'tr'
            ? '../app/src/main/res/values/strings.xml'
            : '../app/src/main/res/values-en/strings.xml',
      ).readAsStringSync();
      final sourceKeys = RegExp(
        r'<string\s+name="([^"]+)"',
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      final arbKeys = arb.keys.where((key) => !key.startsWith('@')).toSet();

      expect(sourceKeys, hasLength(167));
      expect(arbKeys, containsAll(sourceKeys));
    }
  });

  testWidgets('partial German catalog falls back to English', (tester) async {
    late AppLocalizations strings;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            strings = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(strings.group_info, 'Gruppeninfo');
    expect(strings.settings_title, 'Settings');
  });

  testWidgets(
    'runtime language changes persist direction and system fallback',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      await fixture.settings.setLanguage(AppLanguagePreference.tr);
      await tester.pumpWidget(
        SecureChatFlutterApp(container: fixture.container),
      );
      await _pumpFrames(tester);
      expect(find.bySemanticsLabel('Sohbetler'), findsOneWidget);

      await fixture.settings.setLanguage(AppLanguagePreference.ar);
      await _pumpFrames(tester);
      expect(find.text('الدردشات'), findsWidgets);
      expect(
        Directionality.of(tester.element(find.text('الدردشات').first)),
        TextDirection.rtl,
      );

      await fixture.settings.setLanguage(AppLanguagePreference.system);
      await _pumpFrames(tester);
      expect(find.text('Chats'), findsWidgets);
      expect(
        Directionality.of(tester.element(find.text('Chats').first)),
        TextDirection.ltr,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _LocalizationFixture {
  _LocalizationFixture({
    required this.directory,
    required this.database,
    required this.signaling,
    required this.settings,
    required this.container,
  });

  final Directory directory;
  final SecureChatDatabase database;
  final InMemorySignalingService signaling;
  final SettingsService settings;
  final AppContainer container;

  static Future<_LocalizationFixture> open() async {
    final directory = await Directory.systemTemp.createTemp('localization_');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 71)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${directory.path}/database.securejson'),
      crypto: crypto,
    );
    final session = createLoggedInTestSession();
    final signaling = InMemorySignalingService();
    final scheduled = ScheduledMessageService(
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
      scheduler: _NoopScheduler(),
    );
    final settings = SettingsService(
      session: session,
      signaling: signaling,
      scheduledMessages: scheduled,
      profileDirectory: Directory('${directory.path}/profile'),
      fullscreen: _NoopFullscreen(),
    );
    final container = AppContainer.testing(
      session: session,
      conversations: createTestConversationRepository(),
      crypto: crypto,
      signaling: signaling,
      settingsRuntime: AppSettingsRuntime(service: settings),
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
    return _LocalizationFixture(
      directory: directory,
      database: database,
      signaling: signaling,
      settings: settings,
      container: container,
    );
  }

  Future<void> close() async {
    await settings.close();
    await signaling.disconnect();
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _NoopScheduler implements BackgroundScheduler {
  @override
  Future<void> cancelScheduledMessage(String id) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerRecurringTasks() async {}

  @override
  Future<void> scheduleMessage(ScheduledMessageEntity message) async {}
}

class _NoopFullscreen implements FullscreenController {
  @override
  Future<void> setEnabled(bool enabled) async {}
}
