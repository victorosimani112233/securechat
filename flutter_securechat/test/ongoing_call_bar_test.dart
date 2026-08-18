import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/calls/ongoing_call_bar.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const activeCall = CallSession(
    callId: 'call-1',
    peerId: 'peer-1',
    peerName: 'Ayse Demir',
    callType: CallType.video,
    direction: CallDirection.outgoing,
    state: CallState.active,
  );

  testWidgets('ongoing call bar is tappable and survives large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SecureChatTheme.light(),
        home: Scaffold(
          body: OngoingCallBar(
            session: activeCall.copyWith(
              startTime: DateTime.now().subtract(const Duration(minutes: 1)),
            ),
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ayse Demir'), findsOneWidget);
    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.bySemanticsLabel('Aramaya dön: Ayse Demir'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('ongoing-call-bar')));
    expect(taps, 1);
  });

  testWidgets('app frame hides the bar on call and terminal routes', (
    tester,
  ) async {
    final route = ValueNotifier<String?>('/');
    final sessions = StreamController<CallSession?>.broadcast();
    addTearDown(route.dispose);
    addTearDown(sessions.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OngoingCallAppFrame(
          activeRoute: route,
          initialSession: activeCall,
          sessions: sessions.stream,
          onReturnToCall: () {},
          child: const ColoredBox(
            key: ValueKey('route-content'),
            color: Colors.black,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('ongoing-call-bar')), findsOneWidget);
    expect(find.text('Return to call'), findsOneWidget);

    route.value = '/calls';
    await tester.pump();
    expect(find.byKey(const ValueKey('ongoing-call-bar')), findsNothing);

    route.value = '/';
    sessions.add(activeCall.copyWith(state: CallState.ended));
    await tester.pump();
    expect(find.byKey(const ValueKey('ongoing-call-bar')), findsNothing);
    expect(find.byKey(const ValueKey('route-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
