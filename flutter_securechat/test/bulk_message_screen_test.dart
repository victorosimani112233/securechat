import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// Toplu gonderim ekraninin davranis kurallari.
void main() {
  Future<void> open(WidgetTester tester, {AppContainer? container}) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: container ?? createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pushNamed('/bulk-message');
    await tester.pumpAndSettle();
  }

  testWidgets('message is entered before searching and selecting recipients', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-message-input')),
      'Test message',
    );
    await tester.pump();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('recipient-search')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
  });

  testWidgets('mesaj bos iken gonderim kapali', (tester) async {
    await open(tester);
    final button = find.widgetWithText(FilledButton, 'Gönder');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
      reason: 'alici ve mesaj olmadan gonderilememeli',
    );
    expect(button, findsNothing);
  });

  testWidgets('selected recipient has a removable avatar badge', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-message-input')),
      'Test',
    );
    await tester.pump();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    final checkbox = find.byType(CheckboxListTile).first;
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(tester.widget<InputChip>(find.byType(InputChip)).avatar, isNotNull);
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
  });

  Future<void> compose(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('bulk-message-input')),
      'Toplantı 10:00',
    );
    await tester.pump();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
  }

  testWidgets('a selection is saved as a list and reused next time', (
    tester,
  ) async {
    final container = createWidgetTestContainer();
    final lists = container.bulkRuntime!.lists!;
    await open(tester, container: container);
    await compose(tester);
    // Kayitli liste yokken dogrudan kisi secimi acilir; kaydet kapali.
    expect(find.byKey(const ValueKey('bulk-new-selection')), findsNothing);
    final save = find.byKey(const ValueKey('recipient-selection-action'));
    expect(tester.widget<IconButton>(save).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bulk-list-name')),
      'Ekip',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('“Ekip” listesi kaydedildi'), findsOneWidget);
    final saved = (await lists.watch().first).single;
    expect(saved.memberIds, hasLength(1));
    // Ilk kayittan sonra secici acik kalir, secim kaybolmaz.
    expect(find.byKey(const ValueKey('recipient-search')), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-new-selection')), findsNothing);

    // Ikinci acilista once kayitli listeler gosterilir.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed('/bulk-message');
    await tester.pumpAndSettle();
    await compose(tester);
    expect(find.byKey(const ValueKey('bulk-new-selection')), findsOneWidget);
    expect(find.text('1 alıcı'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('bulk-list-${saved.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Ekip'), findsWidgets);

    // Geri tusu listeye doner; listeyi silmek onu kaldirir.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-new-selection')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('bulk-list-delete-${saved.id}')));
    await tester.pumpAndSettle();
    expect(await lists.watch().first, isEmpty);
    expect(find.byKey(const ValueKey('recipient-search')), findsOneWidget);
  });
}
