import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// DENETIM KALKANI: her ekran dar telefonda buyuk metin olceginde ve Arapca
/// RTL'de tasma/assert uretmeden cizilmeli.
///
/// Bu testin varlik sebebi somut: `/permissions` ekrani 320 px genislikte %200
/// metin olceginde `ListTile` assert'i ("Trailing widget consumes the entire
/// tile width") atiyor ve HIC cizilemiyordu. Erisilebilirlik icin yazi
/// boyutunu buyutmus bir kullanici, kurulumun ilk ekraninda kaliyordu.
const _conversation = Conversation(
  id: 'peer-ayse',
  peerId: 'peer-ayse',
  peerName: 'Ayse Demir',
  peerPhone: '+90 532 000 00 01',
);
const _group = Conversation(
  id: 'group-ops',
  peerId: 'group-ops',
  peerName: 'Operasyon Ekibi',
  peerPhone: '',
  isGroup: true,
  groupMembers: ['me', 'peer-ayse'],
  groupAdmins: ['me'],
);

const _routes = <String, Object?>{
  '/onboarding': null,
  '/permissions': null,
  '/auth': null,
  '/contacts': null,
  '/call-readiness': null,
  '/settings': null,
  '/scheduled-messages': null,
  '/backup': null,
  '/auto-download': null,
  '/storage-usage': null,
  '/about': null,
  '/chat': _conversation,
  '/chat-info': _conversation,
  '/export-history': _conversation,
  '/group-info': _group,
};

typedef _Scenario = ({
  String name,
  Size size,
  double scale,
  String language,
  String theme,
});

const _scenarios = <_Scenario>[
  (
    name: 'dar-telefon-200%',
    size: Size(320, 568),
    scale: 2,
    language: 'tr',
    theme: 'dark',
  ),
  (
    name: 'normal',
    size: Size(411, 891),
    scale: 1,
    language: 'tr',
    theme: 'dark',
  ),
  (
    name: 'arapca-rtl-150%',
    size: Size(320, 568),
    scale: 1.5,
    language: 'ar',
    theme: 'dark',
  ),
  // Acik tema koyu temayla ayni ozeni gormeli: butun ekranlar burada da
  // tasmadan cizilmeli.
  (
    name: 'acik-tema',
    size: Size(411, 891),
    scale: 1,
    language: 'tr',
    theme: 'light',
  ),
  (
    name: 'acik-tema-dar-200%',
    size: Size(320, 568),
    scale: 2,
    language: 'tr',
    theme: 'light',
  ),
];

void main() {
  for (final scenario in _scenarios) {
    for (final entry in _routes.entries) {
      testWidgets('${scenario.name} ${entry.key}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        final container = createWidgetTestContainer();
        container.session.languagePreference = scenario.language;
        container.session.themePreference = scenario.theme;
        await tester.pumpWidget(SecureChatFlutterApp(container: container));
        await tester.pumpAndSettle();
        tester.takeException();

        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.pushNamed(entry.key, arguments: entry.value);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} ${scenario.name} altinda cizilemiyor',
        );
      });
    }
  }
}
