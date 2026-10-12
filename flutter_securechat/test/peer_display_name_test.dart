import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/peer_display_name.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 3: rehberde olmayan gonderenin adi UUID gorunuyordu.
void main() {
  const uuid = '3b3663e9-3046-4ba9-acd6-dfdaf3fa510c';

  test('internal ids are never a display name', () {
    expect(isOpaquePeerName(uuid), isTrue);
    expect(isOpaquePeerName('alice', peerId: 'alice'), isTrue);
    expect(isOpaquePeerName('  '), isTrue);
    expect(isOpaquePeerName('QaAlfa', peerId: uuid), isFalse);
    expect(isOpaquePeerName('~QaAlfa', peerId: uuid), isFalse);
    expect(isOpaquePeerName('+905321000412', peerId: uuid), isFalse);
  });

  test('display falls back to the number, then to unknown', () {
    expect(
      peerDisplayName(uuid, peerId: uuid, unknown: 'Bilinmeyen kişi'),
      'Bilinmeyen kişi',
    );
    expect(
      peerDisplayName(
        '',
        peerId: uuid,
        phone: '+905321000412',
        unknown: 'Bilinmeyen kişi',
      ),
      '+905321000412',
    );
    expect(
      peerDisplayName('QaAlfa', peerId: uuid, unknown: 'Bilinmeyen kişi'),
      'QaAlfa',
    );
  });

  testWidgets('conversation titles hide ids but keep group names', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      captured.conversationTitle(
        const Conversation(
          id: uuid,
          peerId: uuid,
          peerName: uuid,
          peerPhone: '',
        ),
      ),
      'Bilinmeyen kişi',
    );
    expect(
      captured.conversationTitle(
        const Conversation(
          id: 'group-token',
          peerId: 'group-token',
          peerName: 'group-token',
          peerPhone: '',
          isGroup: true,
        ),
      ),
      'group-token',
    );
  });
}
