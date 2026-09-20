import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final contacts = File(
    'lib/src/features/contacts/contacts_screen.dart',
  ).readAsStringSync();

  test('phone entry stays above the keyboard and explains its action', () {
    expect(contacts, contains('isScrollControlled: true'));
    expect(contacts, contains('useSafeArea: true'));
    expect(
      contacts,
      contains('MediaQuery.viewInsetsOf(context).bottom'),
      reason: 'The number field must move above the software keyboard.',
    );
    expect(contacts, contains("Key('phone-number-input')"));
    expect(contacts, contains('context.l10n.register_phone_label'));
    expect(contacts, contains("Key('phone-number-submit')"));
    expect(contacts, contains('context.l10n.cd_new_chat_action'));
  });
}
