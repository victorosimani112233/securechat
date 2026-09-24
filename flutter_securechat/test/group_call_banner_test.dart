import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/features/calls/group_call_banner.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/inter_regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final type in CallType.values) {
    testWidgets(
      '${type.name} banner joins, disappears at end, fits narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = _Calls(type);
        addTearDown(calls.changes.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: SecureChatTheme.light(),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: Scaffold(
                body: Column(
                  children: [
                    GroupCallBanner(groupId: 'group', calls: calls),
                    const Expanded(child: Center(child: Text('Chat'))),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('group-call-banner')), findsOneWidget);
        await _screenshot(tester, 'group-banner-${type.name}');
        await tester.tap(find.text('Katıl'));
        await tester.pumpAndSettle();
        expect(calls.joined, 1);
        expect(calls.opened, 1);
        expect(tester.takeException(), isNull);
        calls.active = null;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('group-call-banner')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['CALL_UI_SCREENSHOTS'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
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

class _Calls implements CallManager {
  _Calls(CallType type)
    : active = ActiveGroupCall(
        groupId: 'group',
        routingToken: 'token',
        callId: 'call',
        coordinatorId: 'peer',
        callType: type,
        mediaE2ee: true,
        participants: ['peer'],
      );
  ActiveGroupCall? active;
  int joined = 0;
  int opened = 0;
  final changes = StreamController<CallSession?>.broadcast();
  @override
  CallSession? get currentSession => null;
  @override
  Stream<CallSession?> get sessions => changes.stream;
  @override
  Future<ActiveGroupCall?> activeGroupCall(String groupId) async => active;
  @override
  Future<bool> joinActiveGroupCall(ActiveGroupCall call) async {
    joined++;
    return true;
  }

  @override
  void openCurrentCall() {
    opened++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
