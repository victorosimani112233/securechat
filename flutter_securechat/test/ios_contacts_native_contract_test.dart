import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source contract only: the actual Contacts framework requires the Mac tests.
void main() {
  final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  test('iOS contacts fetch supplies the full-name formatter descriptor', () {
    expect(
      source,
      contains('CNContactFormatter.descriptorForRequiredKeys(for: .fullName)'),
    );
    expect(
      source,
      contains(
        'CNContactFetchRequest(keysToFetch: SecureChatContactsAccess.keysToFetch)',
      ),
    );
    expect(source, contains('CNContactPhoneNumbersKey as CNKeyDescriptor'));
    expect(source, isNot(contains('CNContactGivenNameKey as CNKeyDescriptor')));
  });
  test('both permission and read paths support iOS limited contacts', () {
    expect(source, contains('if #available(iOS 18.0, *), status == .limited'));
    expect(source, contains('if SecureChatContactsAccess.isReadable(status)'));
    expect(
      source,
      contains(
        'guard SecureChatContactsAccess.isReadable(CNContactStore.authorizationStatus(for: .contacts))',
      ),
    );
  });
}
