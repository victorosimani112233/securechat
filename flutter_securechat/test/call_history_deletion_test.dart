import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
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
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  test(
    'single call deletion persists and updates all and peer streams without removing sibling calls',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'call-history-delete-',
      );
      final file = File('${root.path}/db');
      final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 7)));
      var db = await SecureChatDatabase.open(file: file, crypto: crypto);
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      for (final id in ['first', 'second', 'group']) {
        await db.callLogs.insert(
          CallLogEntity(
            id: id,
            peerId: 'peer-ayse',
            peerName: 'Ayse',
            callType: 'VOICE',
            direction: 'INCOMING',
            status: 'MISSED',
            timestamp: 10,
            groupId: id == 'group' ? 'group-ops' : null,
          ),
        );
      }
      final history = CallHistoryService(db.callLogs);
      final all = <List<CallHistoryEntry>>[];
      final peer = <List<CallHistoryEntry>>[];
      final allSubscription = history.watchAll().listen(all.add);
      final peerSubscription = history.watchPeer('peer-ayse').listen(peer.add);
      try {
        await _eventually(() => all.isNotEmpty && peer.isNotEmpty);
        await history.delete('first');
        await _eventually(() => all.last.length == 2 && peer.last.length == 1);
        expect(
          all.last.map((entry) => entry.id),
          unorderedEquals(['second', 'group']),
        );
        expect(peer.last.single.id, 'second');
        expect((await history.watchPeer('group-ops').first).single.id, 'group');
        await history.delete('first');
        await history.delete('unknown');
      } finally {
        await allSubscription.cancel();
        await peerSubscription.cancel();
      }
      await db.close();
      db = await SecureChatDatabase.open(file: file, crypto: crypto);
      expect(
        (await CallHistoryService(
          db.callLogs,
        ).watchAll().first).map((entry) => entry.id),
        unorderedEquals(['second', 'group']),
      );
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'delete confirmation and live filtered removal preserve callback routes at $width',
      (tester) async {
        final history = _History();
        addTearDown(history.changes.close);
        final routes = <CallRouteArguments>[];
        await _pumpHistory(tester, history, width: width, routes: routes);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(CallHistoryScreen)),
        );
        await tester.tap(find.byKey(const ValueKey('call-filter-missed')));
        await tester.pumpAndSettle();
        await tester.longPress(_row('missed'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l10n.msg_action_delete_for_me), findsOneWidget);
        expect(routes, isEmpty);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(history.deleted, isEmpty);
        expect(_row('missed'), findsOneWidget);

        await _deleteRow(tester, 'missed');
        expect(history.deleted, ['missed']);
        expect(_row('missed'), findsNothing);
        expect(_row('busy'), findsOneWidget);
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('call-filter-missed')),
              )
              .selected,
          isTrue,
        );
        await _deleteRow(tester, 'busy');
        expect(find.text(l10n.calls_filter_empty), findsOneWidget);
        expect(routes, isEmpty);

        await tester.tap(find.byKey(const ValueKey('call-filter-all')));
        await tester.pumpAndSettle();
        await tester.tap(_callback('direct'));
        await tester.pumpAndSettle();
        expect(routes.single.peerId, 'peer-ayse');
        expect(routes.single.isGroupCall, isFalse);
        expect(routes.single.callType, CallType.voice);
        Navigator.of(tester.element(find.text('Call route'))).pop();
        await tester.pumpAndSettle();
        await _showRow(tester, 'group');
        await tester.tap(_callback('group'));
        await tester.pumpAndSettle();
        expect(routes.last.peerId, 'group-ops');
        expect(routes.last.isGroupCall, isTrue);
        expect(routes.last.peerIds, ['peer-ayse', 'peer-bora']);
        Navigator.of(tester.element(find.text('Call route'))).pop();
        await tester.pumpAndSettle();
        await _showRow(tester, 'unavailable-group');
        expect(
          tester.widget<IconButton>(_callback('unavailable-group')).onPressed,
          isNull,
        );
        await _deleteRow(tester, 'unavailable-group');
        expect(_row('unavailable-group'), findsNothing);
        expect(routes, hasLength(2));
        expect(history.items.map((entry) => entry.id), ['direct', 'group']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed deletion keeps row visible and permits retry', (
    tester,
  ) async {
    final history = _History()..error = StateError('private database detail');
    addTearDown(history.changes.close);
    await _pumpHistory(tester, history);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CallHistoryScreen)),
    );
    await _deleteRow(tester, 'direct');
    expect(_row('direct'), findsOneWidget);
    expect(find.text(l10n.recipient_action_failed), findsOneWidget);
    expect(find.textContaining('private database detail'), findsNothing);
    expect(tester.widget<IconButton>(_callback('direct')).onPressed, isNotNull);
    history.error = null;
    await _deleteRow(tester, 'direct');
    expect(_row('direct'), findsNothing);
    expect(history.deleted, ['direct', 'direct']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'overlapping long presses share one confirmation and pending deletion',
    (tester) async {
      final history = _History()..pending = Completer<void>();
      addTearDown(history.changes.close);
      await _pumpHistory(tester, history);
      final longPress = tester
          .widget<ListTile>(
            find.descendant(
              of: _row('direct'),
              matching: find.byType(ListTile),
            ),
          )
          .onLongPress!;
      longPress();
      longPress();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('call-history-delete-confirm')),
      );
      await tester.pumpAndSettle();
      longPress();
      await tester.pumpAndSettle();
      expect(history.deleted, ['direct']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<IconButton>(_callback('direct')).onPressed, isNull);
      history.pending!.complete();
      await tester.pumpAndSettle();
      expect(_row('direct'), findsNothing);
      expect(history.deleted, ['direct']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Finder _row(String id) => find.byKey(ValueKey('call-history-entry-$id'));
Finder _callback(String id) =>
    find.descendant(of: _row(id), matching: find.byType(IconButton));

Future<void> _showRow(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    _row(id),
    100,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('call-history-all')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _deleteRow(WidgetTester tester, String id) async {
  await tester.ensureVisible(_row(id));
  await tester.pumpAndSettle();
  await tester.longPress(_row(id));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('call-history-delete-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _pumpHistory(
  WidgetTester tester,
  _History history, {
  double width = 390,
  List<CallRouteArguments>? routes,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = createWidgetTestContainer(mediaRuntime: _Media(history));
  addTearDown(container.signaling.dispose);
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        theme: SecureChatTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
          child: child!,
        ),
        home: const CallHistoryScreen(embedded: true),
        routes: {
          '/calls': (context) {
            routes?.add(
              ModalRoute.of(context)!.settings.arguments as CallRouteArguments,
            );
            return const Scaffold(body: Text('Call route'));
          },
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CallHistoryEntry _entry(
  String id, {
  CallHistoryStatus status = CallHistoryStatus.completed,
  String? groupId,
}) => CallHistoryEntry(
  id: id,
  peerId: 'peer-ayse',
  peerName: id,
  callType: CallType.voice,
  direction: CallDirection.incoming,
  status: status,
  timestamp: DateTime(2026),
  duration: const Duration(seconds: 30),
  groupId: groupId,
);

class _History extends Fake implements CallHistoryService {
  final changes = StreamController<List<CallHistoryEntry>>.broadcast();
  final deleted = <String>[];
  Object? error;
  Completer<void>? pending;
  List<CallHistoryEntry> items = [
    _entry('direct'),
    _entry('missed', status: CallHistoryStatus.missed),
    _entry('busy', status: CallHistoryStatus.busy),
    _entry('group', groupId: 'group-ops'),
    _entry('unavailable-group', groupId: 'left-group'),
  ];

  @override
  Stream<List<CallHistoryEntry>> watchAll() async* {
    yield List.of(items);
    yield* changes.stream;
  }

  @override
  Future<void> delete(String callId) async {
    deleted.add(callId);
    await pending?.future;
    if (error != null) throw error!;
    items.removeWhere((entry) => entry.id == callId);
    changes.add(List.of(items));
  }
}

class _Media extends Fake implements AppMediaRuntime {
  _Media(this.callHistory);
  @override
  final CallHistoryService callHistory;
}

Future<void> _eventually(bool Function() ready) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Call history stream did not update');
}
