import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/backup/backup_service.dart';
import 'package:flutter_securechat/src/features/backup/backup_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  late _Fixture fixture;

  setUpAll(FilePickerIO.registerWith);
  setUp(() {
    fixture = _Fixture();
    final previousPicker = FilePicker.platform;
    FilePicker.platform = fixture.picker;
    addTearDown(() async {
      FilePicker.platform = previousPicker;
      await fixture.container.signaling.dispose();
      fixture.root.deleteSync(recursive: true);
    });
  });

  testWidgets('creation requirements update while typing and backspacing', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openCreate(tester);
    final strings = _strings(tester);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(fields)) {
      expect(field.obscureText, isTrue);
    }
    expect(
      tester.getTopLeft(find.text(strings.password_min_length)).dy,
      greaterThan(tester.getBottomLeft(fields.last).dy),
    );
    _expectRequirements(tester, minimum: false, match: false);
    _expectSubmitEnabled(tester, false);
    await tester.tap(_submit);
    await tester.pump();
    expect(fixture.service.createdPasswords, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(fields.first, 'abcdefg');
    await tester.enterText(fields.last, 'abcdefg');
    await tester.pump();
    _expectRequirements(tester, minimum: false, match: true);
    _expectSubmitEnabled(tester, false);

    await tester.enterText(fields.first, 'abcdefgh');
    await tester.pump();
    _expectRequirements(tester, minimum: true, match: false);
    _expectSubmitEnabled(tester, false);

    await tester.enterText(fields.last, 'abcdefgh');
    await tester.pump();
    _expectRequirements(tester, minimum: true, match: true);
    _expectSubmitEnabled(tester, true);

    await tester.showKeyboard(fields.first);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tester.widget<TextField>(fields.first).controller!.text, 'abcdefg');
    _expectRequirements(tester, minimum: false, match: false);
    _expectSubmitEnabled(tester, false);

    await tester.enterText(fields.first, 'abcdefgh');
    await tester.pump();
    _expectRequirements(tester, minimum: true, match: true);
    _expectSubmitEnabled(tester, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation matches exactly and empty fields are unmet', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openCreate(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'abcdefgh');
    for (final confirmation in ['Abcdefgh', 'abcdefgh ', '']) {
      await tester.enterText(fields.last, confirmation);
      await tester.pump();
      _expectRequirements(tester, minimum: true, match: false);
      _expectSubmitEnabled(tester, false);
    }

    await tester.enterText(fields.last, 'abcdefgh');
    await tester.pump();
    _expectRequirements(tester, minimum: true, match: true);
    _expectSubmitEnabled(tester, true);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tester.widget<TextField>(fields.last).controller!.text, 'abcdefg');
    _expectRequirements(tester, minimum: true, match: false);
    _expectSubmitEnabled(tester, false);

    await tester.enterText(fields.first, '');
    await tester.enterText(fields.last, '');
    await tester.pump();
    _expectRequirements(tester, minimum: false, match: false);
    _expectSubmitEnabled(tester, false);
  });

  testWidgets('valid creation passes the exact password and exports backup', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openCreate(tester);
    final fields = find.byType(TextField);
    final controllers = tester
        .widgetList<TextField>(fields)
        .map((field) => field.controller!)
        .toList();
    const password = ' abcdef ';
    expect(password.length, BackupService.minimumPasswordLength);
    await tester.enterText(fields.first, password);
    await tester.enterText(fields.last, password);
    await tester.pump();
    _expectSubmitEnabled(tester, true);

    // File export needs both real file I/O and fake-clock route microtasks.
    await tester.runAsync(() async {
      await tester.tap(_submit);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!fixture.picker.saved.isCompleted &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(fixture.picker.saved.isCompleted, isTrue);
    await tester.pumpAndSettle();
    expect(fixture.service.createdPasswords, [password]);
    expect(fixture.picker.savedBytes, fixture.file.readAsBytesSync());
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_strings(tester).backup_created), findsOneWidget);
    _expectDisposed(controllers);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel and back dispose controllers and reopen with empty state',
    (tester) async {
      await _pumpScreen(tester, fixture);
      for (final useBack in [false, true]) {
        await _openCreate(tester);
        final fields = find.byType(TextField);
        final controllers = tester
            .widgetList<TextField>(fields)
            .map((field) => field.controller!)
            .toList();
        expect(controllers.map((controller) => controller.text), ['', '']);
        _expectRequirements(tester, minimum: false, match: false);
        _expectSubmitEnabled(tester, false);
        await tester.enterText(fields.first, 'abcdefgh');
        await tester.enterText(fields.last, 'abcdefgh');
        await tester.pump();
        if (useBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text(_strings(tester).cancel));
        }
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        _expectDisposed(controllers);
      }
      expect(fixture.service.createdPasswords, isEmpty);
      expect(fixture.service.restoredPasswords, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final pickFile in [false, true]) {
    testWidgets(
      'restore from ${pickFile ? 'picker' : 'local list'} keeps one password field',
      (tester) async {
        await _pumpScreen(tester, fixture);
        final strings = _strings(tester);
        await tester.tap(
          pickFile
              ? find.widgetWithText(OutlinedButton, strings.restore_backup_file)
              : find.text(fixture.file.uri.pathSegments.last),
        );
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        expect(field, findsOneWidget);
        expect(tester.widget<TextField>(field).obscureText, isTrue);
        expect(find.text(strings.password_repeat), findsNothing);
        expect(find.text(strings.backup_passwords_match), findsNothing);
        expect(find.text(strings.password_min_length), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);
        expect(
          find.widgetWithText(FilledButton, strings.restore),
          findsOneWidget,
        );
        _expectSubmitEnabled(tester, true);

        for (final password in ['', 'short']) {
          await tester.enterText(field, password);
          await tester.tap(_submit);
          await tester.pump();
          expect(find.text(strings.password_too_short), findsOneWidget);
          expect(fixture.service.restoredPasswords, isEmpty);
        }
        await tester.enterText(field, 'abcdefgh');
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(fixture.service.restoredPasswords, ['abcdefgh']);
        expect(fixture.service.restoredFiles.single.path, fixture.file.path);
        expect(fixture.service.createdPasswords, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text(strings.backup_restored), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['en', 'tr', 'de', 'ar']) {
    testWidgets(
      'creation scrolls on a narrow keyboard layout at 2x in $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        await _pumpScreen(
          tester,
          fixture,
          locale: Locale(language),
          textScale: 2,
        );
        await _openCreate(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 230);
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.first, 'abcdefgh');
        await tester.enterText(fields.last, 'abcdefgh');
        await tester.pumpAndSettle();
        _expectRequirements(tester, minimum: true, match: true);
        _expectSubmitEnabled(tester, true);

        final scrollable = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(
          tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
          greaterThan(0),
        );
        final match = find.text(_strings(tester).backup_passwords_match);
        await tester.ensureVisible(match);
        await tester.pumpAndSettle();
        expect(match.hitTestable(), findsOneWidget);
        expect(_submit.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(_submit).dy, lessThanOrEqualTo(568 - 230));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(_strings(tester).cancel));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder get _submit => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BackupScreen)));

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
        home: const BackupScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCreate(WidgetTester tester) async {
  final button = find.widgetWithText(
    FilledButton,
    _strings(tester).create_backup,
  );
  await tester.scrollUntilVisible(
    button,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

void _expectSubmitEnabled(WidgetTester tester, bool enabled) {
  expect(
    tester.widget<FilledButton>(_submit).onPressed,
    enabled ? isNotNull : isNull,
  );
}

void _expectRequirements(
  WidgetTester tester, {
  required bool minimum,
  required bool match,
}) {
  final strings = _strings(tester);
  for (final (label, met) in [
    (strings.password_min_length, minimum),
    (strings.backup_passwords_match, match),
  ]) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    final icon = tester.widget<Icon>(
      find.descendant(of: row, matching: find.byType(Icon)),
    );
    expect(icon.icon, met ? Icons.check_circle : Icons.close);
    expect(
      icon.color,
      met ? AzureTokens.ok : Theme.of(tester.element(row)).colorScheme.error,
    );
  }
}

void _expectDisposed(List<TextEditingController> controllers) {
  for (final controller in controllers) {
    expect(() => controller.addListener(() {}), throwsFlutterError);
  }
}

class _Fixture {
  _Fixture() {
    file = File('${root.path}/existing.elbk')..writeAsBytesSync([1, 2, 3]);
    service = _RecordingBackupService(file);
    picker = _TestFilePicker(file);
    final defaults = createWidgetTestContainer();
    container = AppContainer.testing(
      session: defaults.session,
      conversations: defaults.conversations,
      crypto: defaults.crypto,
      signaling: defaults.signaling,
      chatAccessRuntime: defaults.chatAccessRuntime,
      callReadinessRuntime: defaults.callReadinessRuntime,
      backupRuntime: AppBackupRuntime(service: service),
    );
  }

  final root = Directory.systemTemp.createTempSync('backup-password-dialog-');
  late final File file;
  late final _RecordingBackupService service;
  late final _TestFilePicker picker;
  late final AppContainer container;
}

class _RecordingBackupService implements BackupService {
  _RecordingBackupService(this.file);

  final File file;
  final createdPasswords = <String>[];
  final restoredPasswords = <String>[];
  final restoredFiles = <File>[];

  @override
  Future<List<File>> localBackups() async => [file];

  @override
  Future<File> createBackup(String password) async {
    createdPasswords.add(password);
    return file;
  }

  @override
  Future<BackupRestoreResult> restoreBackup(File file, String password) async {
    restoredFiles.add(file);
    restoredPasswords.add(password);
    return const BackupRestoreSuccess();
  }

  @override
  Future<int> remainingAttempts(File file) async =>
      BackupService.maximumAttempts;
}

class _TestFilePicker extends FilePicker {
  _TestFilePicker(this.file);

  final File file;
  final saved = Completer<void>();
  Uint8List? savedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    saved.complete();
    return file.path;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: file.uri.pathSegments.last,
      size: file.lengthSync(),
      path: file.path,
    ),
  ]);
}
