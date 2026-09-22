import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/settings/chat_storage_screen.dart';
import 'package:flutter_securechat/src/features/settings/storage_usage_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/security/chat_lock_credential_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _chatId = 'storage-chat';
const _privateName = 'private-view-once-filename.png';

void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
    addTearDown(fixture.container.signaling.dispose);
  });

  testWidgets('overview opens chat detail and refreshes when returning', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    expect(find.text(_summary(tester, fixture)), findsOneWidget);
    expect(fixture.service.analyzeCalls, 1);
    await _openDetail(tester);
    expect(find.byType(ChatStorageScreen), findsOneWidget);
    expect(find.text(fixture.service.conversation.peerName), findsOneWidget);
    expect(fixture.service.fileRequests, [_chatId]);
    expect(fixture.auth.requests, isEmpty);
    expect(find.byType(CheckboxListTile), findsNWidgets(5));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatStorageScreen), findsNothing);
    expect(find.text(_summary(tester, fixture)), findsOneWidget);
    expect(fixture.service.analyzeCalls, 2);
  });

  testWidgets('category filters and select-all affect the visible files', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    final strings = _strings(tester);
    for (final (label, ids) in [
      (strings.photos, ['photo', 'view-once']),
      (strings.videos, ['video']),
      (strings.storage_audio, ['audio']),
      (strings.documents, ['document']),
    ]) {
      await _filter(tester, label);
      expect(find.byType(CheckboxListTile), findsNWidgets(ids.length));
      for (final id in ids) {
        expect(_file(id), findsOneWidget);
      }
    }

    await _filter(tester, strings.photos);
    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'photo'), isTrue);
    expect(_selected(tester, 'view-once'), isTrue);
    expect(find.text(strings.storage_delete_action(2)), findsOneWidget);

    await _filter(tester, strings.documents);
    expect(_selected(tester, 'document'), isFalse);
    await tester.tap(_file('document'));
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_action(3)), findsOneWidget);
    await _filter(tester, strings.storage_all_files);
    expect(_selected(tester, 'photo'), isTrue);
    expect(_selected(tester, 'document'), isTrue);
    expect(_selected(tester, 'video'), isFalse);

    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_action(5)), findsOneWidget);
    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(_deleteSelected, findsNothing);
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    )) {
      expect(tile.value, isFalse);
    }
  });

  testWidgets(
    'cancel preserves files and confirm refreshes detail and overview',
    (tester) async {
      await _pumpScreen(tester, fixture);
      final originalSummary = _summary(tester, fixture);
      await _openDetail(tester);
      final strings = _strings(tester);
      await tester.tap(_file('video'));
      await tester.pumpAndSettle();
      await tester.tap(_deleteSelected);
      await tester.pumpAndSettle();
      expect(find.text(strings.storage_delete_selected(1)), findsOneWidget);
      await tester.tap(find.text(strings.cancel));
      await tester.pumpAndSettle();
      expect(fixture.service.cleanRequests, isEmpty);
      expect(_selected(tester, 'video'), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(originalSummary), findsOneWidget);

      await _openDetail(tester);
      expect(_selected(tester, 'video'), isFalse);
      await tester.tap(_file('video'));
      await tester.pumpAndSettle();
      await tester.tap(_deleteSelected);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, strings.cd_clear));
      await tester.pumpAndSettle();
      expect(fixture.service.cleanRequests, hasLength(1));
      expect(fixture.service.cleanRequests.single.$1, _chatId);
      expect(fixture.service.cleanRequests.single.$2, {'video'});
      expect(_file('video'), findsNothing);
      expect(_file('photo'), findsOneWidget);
      expect(_deleteSelected, findsNothing);
      expect(
        find.text(strings.storage_cleanup_result(1, formatStorageBytes(3072))),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(originalSummary), findsNothing);
      expect(find.text(_summary(tester, fixture)), findsOneWidget);
      expect(fixture.service.analyzeCalls, 3);
    },
  );

  for (final throwsError in [false, true]) {
    testWidgets(
      'locked chat fails closed on ${throwsError ? 'error' : 'denial'}',
      (tester) async {
        fixture.service.conversation = fixture.service.conversation.copyWith(
          isLocked: true,
        );
        fixture.auth.allowed = false;
        fixture.auth.error = throwsError
            ? PlatformException(code: 'authentication-unavailable')
            : null;
        await _pumpScreen(tester, fixture);
        await _openDetail(tester);
        expect(fixture.auth.requests, [fixture.service.conversation.peerName]);
        expect(fixture.service.fileRequests, isEmpty);
        _expectNoFiles(tester, fixture);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.select_all),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<PopupMenuButton<StorageFileCategory?>>(
                find.byType(PopupMenuButton<StorageFileCategory?>),
              )
              .enabled,
          isFalse,
        );

        fixture.auth.allowed = true;
        fixture.auth.error = null;
        await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
        await tester.pumpAndSettle();
        expect(fixture.auth.requests, hasLength(2));
        expect(fixture.service.fileRequests, [_chatId]);
        expect(_file('photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'password-protected chat never falls back to device authentication',
    (tester) async {
      fixture.service.conversation = fixture.service.conversation.copyWith(
        isLocked: true,
      );
      fixture.credentials.present = true;
      await _pumpScreen(tester, fixture);
      // The detail screen stays busy underneath the password dialog.
      await tester.tap(_chat);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final strings = _strings(tester);
      expect(
        find.byKey(const ValueKey('chat-unlock-password')),
        findsOneWidget,
      );
      expect(fixture.auth.requests, isEmpty);
      expect(fixture.service.fileRequests, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('chat-unlock-password')),
        'incorrect-password',
      );
      await tester.tap(find.byKey(const ValueKey('chat-unlock-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(strings.chat_lock_wrong_password), findsOneWidget);
      expect(fixture.service.fileRequests, isEmpty);
      await tester.tap(find.text(strings.cancel));
      await tester.pumpAndSettle();
      _expectNoFiles(tester, fixture);
      expect(fixture.auth.requests, isEmpty);
    },
  );

  testWidgets('view-once filenames are absent from text and semantics', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    final strings = _strings(tester);
    expect(find.text(strings.view_once_protected), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.textContaining(_privateName), findsNothing);
    expect(find.bySemanticsLabel(RegExp(_privateName)), findsNothing);
    expect(find.byType(Image), findsNothing);
    await tester.tap(_file('view-once'));
    await tester.pumpAndSettle();
    await tester.tap(_deleteSelected);
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_selected(1)), findsOneWidget);
    expect(find.textContaining(_privateName), findsNothing);
    expect(find.bySemanticsLabel(RegExp(_privateName)), findsNothing);
    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();
    expect(fixture.service.cleanRequests, isEmpty);
  });

  for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('$state clears access and selection until reauthorized', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      fixture.service.conversation = fixture.service.conversation.copyWith(
        isLocked: true,
      );
      await _pumpScreen(tester, fixture);
      await _openDetail(tester);
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(_deleteSelected, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      _expectNoFiles(tester, fixture);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      _expectNoFiles(tester, fixture);

      fixture.auth.allowed = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.auth.requests, hasLength(2));
      expect(fixture.service.fileRequests, [_chatId]);
      _expectNoFiles(tester, fixture);
      fixture.auth.allowed = true;
      await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
      await tester.pumpAndSettle();
      expect(fixture.auth.requests, hasLength(3));
      expect(_selected(tester, 'photo'), isFalse);
      expect(_deleteSelected, findsNothing);
    });
  }

  testWidgets('an unlock completed after pause cannot expose files', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    fixture.service.conversation = fixture.service.conversation.copyWith(
      isLocked: true,
    );
    final pending = Completer<bool>();
    fixture.auth.pending = pending;
    await _pumpScreen(tester, fixture);
    await tester.tap(_chat);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.auth.requests, hasLength(1));
    expect(fixture.service.fileRequests, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pending.complete(true);
    await tester.pump();
    _expectNoFiles(tester, fixture);
    expect(fixture.service.fileRequests, isEmpty);

    fixture.auth.pending = null;
    fixture.auth.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.auth.requests, hasLength(2));
    expect(fixture.service.fileRequests, isEmpty);
    _expectNoFiles(tester, fixture);
  });

  testWidgets('pausing invalidates an outstanding delete confirmation', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    fixture.service.conversation = fixture.service.conversation.copyWith(
      isLocked: true,
    );
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await tester.tap(_file('photo'));
    await tester.pumpAndSettle();
    await tester.tap(_deleteSelected);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    fixture.auth.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(
        find.widgetWithText(FilledButton, _strings(tester).cd_clear),
      );
      await tester.pumpAndSettle();
    }
    expect(fixture.service.cleanRequests, isEmpty);
    expect(fixture.service.files, hasLength(5));
  });

  for (final language in ['en', 'tr', 'de', 'ar']) {
    testWidgets('storage workflow fits 320px at 2x text in $language', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      fixture.service.conversation = fixture.service.conversation.copyWith(
        peerName: 'Storage Conversation With A Long Display Name',
      );
      await _pumpScreen(
        tester,
        fixture,
        locale: Locale(language),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await _openDetail(tester);
      expect(tester.takeException(), isNull);
      final strings = _strings(tester);
      await _filter(tester, strings.documents);
      expect(tester.takeException(), isNull);
      await tester.tap(_file('document'));
      await tester.pumpAndSettle();
      expect(_deleteSelected.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_deleteSelected);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      final cancel = find.widgetWithText(TextButton, strings.cancel);
      expect(cancel.hitTestable(), findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(StorageUsageScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder get _chat => find.byKey(const ValueKey('storage-chat-$_chatId'));
Finder get _deleteSelected =>
    find.byKey(const ValueKey('storage-delete-selected'));
Finder _file(String id) => find.byKey(ValueKey('storage-file-$id'));
bool _selected(WidgetTester tester, String id) =>
    tester.widget<CheckboxListTile>(_file(id)).value!;

AppLocalizations _strings(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(StorageUsageScreen, skipOffstage: false)),
);

String _summary(WidgetTester tester, _Fixture fixture) {
  final summary = fixture.service.summary;
  return _strings(tester).storage_summary(
    summary.messageCount,
    summary.fileCount,
    formatStorageBytes(summary.totalBytes),
  );
}

void _expectNoFiles(WidgetTester tester, _Fixture fixture) {
  expect(find.byType(CheckboxListTile), findsNothing);
  expect(_deleteSelected, findsNothing);
  for (final file in fixture.service.files) {
    expect(find.text(file.message.fileName!), findsNothing);
  }
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.ensureVisible(_chat);
  await tester.pumpAndSettle();
  await tester.tap(_chat);
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(_strings(tester).storage_filter));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _Fixture fixture, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    AppContainerScope(
      container: fixture.container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SecureChatTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const StorageUsageScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture() {
    final defaults = createWidgetTestContainer();
    container = AppContainer.testing(
      session: defaults.session,
      conversations: defaults.conversations,
      crypto: defaults.crypto,
      signaling: defaults.signaling,
      chatAccessRuntime: AppChatAccessRuntime(
        service: ChatAccessService(authenticator: auth),
        credentials: credentials,
      ),
      callReadinessRuntime: defaults.callReadinessRuntime,
      storageRuntime: AppStorageRuntime(service: service),
    );
  }

  final service = _StorageService();
  final auth = _Authenticator();
  final credentials = _Credentials();
  late final AppContainer container;
}

class _StorageService extends Fake implements StorageManagementService {
  ConversationEntity conversation = const ConversationEntity(
    id: _chatId,
    peerId: 'peer',
    peerName: 'Storage Chat',
    peerPhone: '',
  );
  final files = [
    _storageFile('photo', 'photo.png', 'image/png', 4096),
    _storageFile('video', 'video.mp4', 'video/mp4', 3072),
    _storageFile('audio', 'audio.ogg', 'audio/ogg', 2048),
    _storageFile(
      'document',
      'quarterly-planning-document-with-a-long-name.pdf',
      'application/pdf',
      1024,
    ),
    _storageFile('view-once', _privateName, 'image/png', 512, viewOnce: true),
  ];
  final fileRequests = <String>[];
  final cleanRequests = <(String, Set<String>)>[];
  int analyzeCalls = 0;

  ChatStorageBreakdown get summary {
    final bytes = files.fold(0, (total, file) => total + file.diskBytes);
    return ChatStorageBreakdown(
      conversationId: conversation.id,
      displayName: conversation.peerName,
      isGroup: conversation.isGroup,
      messageCount: files.length + 1,
      fileCount: files.length,
      fileBytes: bytes,
      totalBytes: bytes + StorageManagementService.textOverheadPerMessage,
    );
  }

  @override
  Future<List<ChatStorageBreakdown>> analyzeAll() async {
    analyzeCalls++;
    return [summary];
  }

  @override
  Future<ConversationEntity?> getConversation(String id) async =>
      id == conversation.id ? conversation : null;

  @override
  Future<List<ChatStorageFile>> filesForChat(String conversationId) async {
    fileRequests.add(conversationId);
    return List.of(files);
  }

  @override
  Future<StorageCleanupResult> cleanSelectedFiles(
    String conversationId,
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toSet();
    cleanRequests.add((conversationId, ids));
    final removed = files
        .where((file) => ids.contains(file.message.id))
        .toList();
    files.removeWhere((file) => ids.contains(file.message.id));
    return StorageCleanupResult(
      deletedCount: removed.length,
      freedBytes: removed.fold(0, (total, file) => total + file.diskBytes),
      failedIds: const [],
    );
  }
}

class _Authenticator implements DeviceOwnerAuthenticator {
  bool allowed = true;
  Object? error;
  Completer<bool>? pending;
  final requests = <String>[];

  @override
  Future<bool> authenticate(String title) async {
    requests.add(title);
    if (error != null) throw error!;
    return pending == null ? allowed : await pending!.future;
  }
}

class _Credentials extends Fake implements ChatLockCredentialService {
  bool present = false;

  @override
  Future<bool> hasCredential(String conversationId) async => present;

  @override
  Future<bool> verifyPassword(String conversationId, String password) async =>
      false;
}

ChatStorageFile _storageFile(
  String id,
  String name,
  String mime,
  int bytes, {
  bool viewOnce = false,
}) => ChatStorageFile(
  message: LocalMessage(
    id: id,
    conversationId: _chatId,
    senderId: 'peer',
    peerId: 'me',
    content: LocalMessage.buildFileContent(
      fileName: name,
      mimeType: mime,
      fileSize: bytes,
      filePath: '/managed/$name',
    ),
    contentType: MessageContentType.file,
    timestamp: DateTime(2026, 9, 22),
    status: MessageStatus.delivered,
    isOutgoing: false,
    isViewOnce: viewOnce,
  ),
  diskBytes: bytes,
  available: true,
);
