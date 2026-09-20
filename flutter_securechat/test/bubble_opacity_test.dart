import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// Mesaj balonlari SAYDAM OLMAMALI.
///
/// Arka plan deseni surekli kayiyor. Balon yari saydam kalirsa desen yazinin
/// altindan gecer: cihazda gelen balonlarin icinden zarf/kilit motifleri
/// goruluyordu. Okunabilirlik, desenin gorunurlugunden once gelir.
void main() {
  const conversation = Conversation(
    id: 'peer-ayse',
    peerId: 'peer-ayse',
    peerName: 'Ayse Demir',
    peerPhone: '+90 532 000 00 01',
  );

  Color bubbleColorOf(WidgetTester tester, String text) {
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text(text), matching: find.byType(Material))
          .first,
    );
    return material.color!;
  }

  testWidgets('gelen ve giden balonlar opak', (tester) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pushNamed('/chat', arguments: conversation);
    await tester.pumpAndSettle();

    for (final text in const [
      'Merhaba, Flutter tasima ekranini inceliyorum.',
      'Mevcut davranisi koruyarak ilerliyorum.',
    ]) {
      final color = bubbleColorOf(tester, text);
      expect(
        color.a,
        1.0,
        reason: '"$text" balonu saydam: desen yazinin altindan gecer',
      );
    }
  });

  // NOT: "asagi tusu son mesaja gider" icin widget testi yazilamadi. 60+
  // mesajli bir listede Flutter'in kendi semantics assert'i tetikleniyor:
  //   'package:flutter/src/rendering/object.dart': Failed assertion:
  //   '!childSemantics.renderObject._needsLayout': is not true.
  // Framework hatasi cerceve icinde asilamiyor; duzeltme cihazda dogrulandi.
}
