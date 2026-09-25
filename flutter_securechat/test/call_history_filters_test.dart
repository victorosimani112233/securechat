import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/calls/call_history_service.dart';
import 'package:flutter_securechat/src/features/calls/call_history_screen.dart';
import 'package:flutter_securechat/src/features/calls/call_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/widgets/avatar.dart';
import 'package:flutter_securechat/src/widgets/azure_surface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('call filters, live updates and group callback at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = _History();
      addTearDown(history.changes.close);
      final container = createWidgetTestContainer(
        mediaRuntime: _Media(history),
      );
      CallRouteArguments? callback;
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
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.4 : 1)),
              child: RepaintBoundary(
                key: const ValueKey('capture-calls'),
                child: child!,
              ),
            ),
            home: const CallHistoryScreen(embedded: true),
            routes: {
              '/calls': (context) {
                callback =
                    ModalRoute.of(context)!.settings.arguments
                        as CallRouteArguments;
                return const Scaffold(body: Text('Call route'));
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'all-calls-$width');
      Future<void> select(String name) async {
        final finder = find.byKey(ValueKey('call-filter-$name'));
        final bar = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('call-history-filters')),
            matching: find.byType(Scrollable),
          ),
        );
        bar.position.jumpTo(0);
        await tester.pumpAndSettle();
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            100,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('call-history-filters')),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(finder).selected, isTrue);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is FilterChip && widget.selected,
          ),
          findsOneWidget,
        );
      }

      for (final filter in {
        'all': 8,
        'missed': 2,
        'incoming': 4,
        'outgoing': 4,
        'video': 2,
        'group': 3,
      }.entries) {
        await select(filter.key);
        final list = tester.widget<ListView>(
          find.byKey(ValueKey('call-history-${filter.key}')),
        );
        expect(list.semanticChildCount, filter.value);
        if (filter.key == 'incoming') {
          expect(
            find.byKey(const ValueKey('call-history-entry-missed')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('call-history-entry-busy-in')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('call-history-entry-video')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('call-history-entry-group-in')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await _capture(tester, 'group-filter-$width');
      final incomingGroup = find.byKey(
        const ValueKey('call-history-entry-group-in'),
      );
      await tester.ensureVisible(incomingGroup);
      await tester.tap(
        find.descendant(of: incomingGroup, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(callback!.isGroupCall, isTrue);
      expect(callback!.peerId, 'group-ops');
      expect(callback!.peerIds, ['peer-ayse', 'peer-bora']);
      Navigator.of(tester.element(find.text('Call route'))).pop();
      await tester.pumpAndSettle();
      await select('missed');
      history.items = [history.items[1]];
      history.changes.add(history.items);
      await tester.pumpAndSettle();
      expect(find.text('Bu filtrede arama yok'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('call-filter-missed')),
            )
            .selected,
        isTrue,
      );
      await select('all');
      expect(
        find.byKey(ValueKey('call-history-entry-${history.items.single.id}')),
        findsOneWidget,
      );
      history.items = [];
      history.changes.add([]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('call-history-filters')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final dark in [false, true]) {
    testWidgets('muted call backgrounds and contrast, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = _History()
        ..items = [
          _entry('out', direction: CallDirection.outgoing),
          _entry('in'),
          _entry('missed', status: CallHistoryStatus.missed),
          _entry('busy-in', status: CallHistoryStatus.busy),
          _entry(
            'missed-out',
            direction: CallDirection.outgoing,
            status: CallHistoryStatus.missed,
          ),
          _entry(
            'busy-out',
            direction: CallDirection.outgoing,
            status: CallHistoryStatus.busy,
          ),
        ];
      addTearDown(history.changes.close);
      final theme = dark ? SecureChatTheme.dark() : SecureChatTheme.light();
      await tester.pumpWidget(
        AppContainerScope(
          container: createWidgetTestContainer(mediaRuntime: _Media(history)),
          child: MaterialApp(
            theme: theme,
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const CallHistoryScreen(embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final green = dark ? Colors.green.shade300 : Colors.green.shade700;
      final blue = dark ? Colors.blue.shade300 : Colors.blue.shade700;
      final red = dark ? Colors.red.shade300 : Colors.red.shade700;
      final l10n = AppLocalizations.of(
        tester.element(find.byType(CallHistoryScreen)),
      );
      for (final (id, color, icon, label) in [
        ('out', green, Icons.call_made, l10n.outgoing),
        ('in', blue, Icons.call_received, l10n.incoming),
        ('missed', red, Icons.call_missed, l10n.missed),
        ('busy-in', red, Icons.call_missed, l10n.busy),
        ('missed-out', red, Icons.call_missed, l10n.missed),
        ('busy-out', green, Icons.call_made, l10n.busy),
      ]) {
        final row = find.byKey(ValueKey('call-history-entry-$id'));
        await tester.scrollUntilVisible(
          row,
          100,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('call-history-all')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        final base = AzureSurface.colorOf(tester.element(row));
        final background = Color.alphaBlend(
          color.withValues(alpha: dark ? .10 : .08),
          base,
        );
        final accent = Color.lerp(
          theme.colorScheme.onSurfaceVariant,
          color,
          .60,
        )!;
        final surface = tester.widget<AzureSurface>(row);
        expect(surface.borderColor, isNull);
        expect(surface.backgroundColor, background);
        expect(background.a, 1);
        expect(background, isNot(base));
        final statusIcon = find.descendant(
          of: row,
          matching: find.byIcon(icon),
        );
        expect(statusIcon, findsOneWidget);
        expect(tester.widget<Icon>(statusIcon).color, accent);
        expect(
          find.descendant(of: row, matching: find.textContaining(label)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(GeneratedAvatar)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.call_outlined)),
          findsOneWidget,
        );
        final material = tester.widget<Material>(
          find.descendant(of: row, matching: find.byType(Material)).first,
        );
        expect(material.color, background);
        expect(
          (material.shape! as RoundedRectangleBorder).side.color,
          theme.colorScheme.outlineVariant.withValues(alpha: .48),
        );
        expect((material.shape! as RoundedRectangleBorder).side.width, 1);
        double contrast(Color foreground) {
          final first = foreground.computeLuminance();
          final second = background.computeLuminance();
          return first > second
              ? (first + .05) / (second + .05)
              : (second + .05) / (first + .05);
        }

        expect(
          contrast(theme.colorScheme.onSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(theme.colorScheme.onSurfaceVariant),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(accent), greaterThanOrEqualTo(3));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'group history persists and is associated with group rather than caller',
    () async {
      final root = await Directory.systemTemp.createTemp('group_call_history_');
      final file = File('${root.path}/db');
      final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
      var db = await SecureChatDatabase.open(file: file, crypto: crypto);
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      const log = CallLogEntity(
        id: 'group-call',
        peerId: 'caller',
        peerName: 'Group',
        callType: 'VOICE',
        direction: 'INCOMING',
        status: 'MISSED',
        timestamp: 10,
        groupId: 'group',
      );
      await db.callLogs.insert(log);
      await db.close();
      db = await SecureChatDatabase.open(file: file, crypto: crypto);
      final history = CallHistoryService(db.callLogs);
      expect((await history.watchAll().first).single.groupId, 'group');
      expect((await history.watchPeer('group').first).single.id, 'group-call');
      expect(await history.watchPeer('caller').first, isEmpty);
      final oldJson = log.toJson()..remove('groupId');
      expect(CallLogEntity.fromJson(oldJson).groupId, isNull);
    },
  );
}

CallHistoryEntry _entry(
  String id, {
  CallDirection direction = CallDirection.incoming,
  CallType type = CallType.voice,
  CallHistoryStatus status = CallHistoryStatus.completed,
  String? groupId,
  String peerId = 'peer-ayse',
}) => CallHistoryEntry(
  id: id,
  peerId: peerId,
  peerName: id,
  callType: type,
  direction: direction,
  status: status,
  timestamp: DateTime(2026),
  duration: const Duration(seconds: 30),
  groupId: groupId,
);

class _History implements CallHistoryService {
  final changes = StreamController<List<CallHistoryEntry>>.broadcast();
  List<CallHistoryEntry> items = [
    _entry('missed', status: CallHistoryStatus.missed),
    _entry('out', direction: CallDirection.outgoing),
    _entry('video', type: CallType.video),
    _entry(
      'group-video',
      type: CallType.video,
      direction: CallDirection.outgoing,
      groupId: 'group-ops',
    ),
    _entry('group-in', groupId: 'group-ops'),
    _entry('busy-in', status: CallHistoryStatus.busy),
    _entry(
      'busy-out',
      status: CallHistoryStatus.busy,
      direction: CallDirection.outgoing,
    ),
    _entry(
      'legacy-group',
      peerId: 'group-ops',
      direction: CallDirection.outgoing,
    ),
  ];
  @override
  Stream<List<CallHistoryEntry>> watchAll() async* {
    yield items;
    yield* changes.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements AppMediaRuntime {
  _Media(this.callHistory);
  @override
  final CallHistoryService callHistory;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['CALL_HISTORY_SCREENSHOTS'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture-calls')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
