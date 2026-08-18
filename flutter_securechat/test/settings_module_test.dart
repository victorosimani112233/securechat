import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/background/background_scheduler.dart';
import 'package:flutter_securechat/src/background/scheduled_message_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/settings/settings_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      expect(fixture.fullscreen.values, [true]);

      final raw = await fixture.sessionFile.readAsString();
      expect(raw, isNot(contains('themePreference')));
      expect(raw, isNot(contains('languagePreference')));
      expect(raw, isNot(contains('access-secret')));
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
