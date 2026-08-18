import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/calls/call_quality_indicator.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call state maps reconnecting separately and active to good', () {
    expect(CallState.reconnecting.callQuality, CallQuality.reconnecting);
    expect(CallState.active.callQuality, CallQuality.good);
    expect((null as CallState?).callQuality, CallQuality.good);
  });

  testWidgets('quality indicator renders three increasing signal bars', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CallQualityIndicator(quality: CallQuality.fair)),
      ),
    );

    final bars = List.generate(
      3,
      (index) =>
          tester.widget<Container>(find.byKey(ValueKey('quality-bar-$index'))),
    );
    expect(bars.map((bar) => bar.constraints?.maxHeight), [8, 12, 16]);
  });

  testWidgets('reconnecting video banner offers audio-only continuation', (
    tester,
  ) async {
    var disabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReconnectingBanner(
            label: 'Reconnecting',
            disableVideoLabel: 'Disable video',
            onDisableVideo: () => disabled = true,
          ),
        ),
      ),
    );

    expect(find.text('Reconnecting'), findsOneWidget);
    expect(find.byKey(const ValueKey('quality-bar-0')), findsOneWidget);
    await tester.tap(find.text('Disable video'));
    expect(disabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
