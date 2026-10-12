import 'package:flutter_securechat/src/contacts/contact_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 7: rehber aramasi tam numarayi bulmuyordu.
void main() {
  const name = 'QaBeta';
  const phone = '+90 532 100 04 13';

  bool match(String query) =>
      matchesContactQuery(name: name, phone: phone, query: query);

  test('a full number matches regardless of spacing and prefix', () {
    expect(match('5321000413'), isTrue);
    expect(match('05321000413'), isTrue);
    expect(match('+905321000413'), isTrue);
    expect(match('0532 100 04 13'), isTrue);
    expect(match('532'), isTrue);
  });

  test('names match case-insensitively; others do not match', () {
    expect(match('qabeta'), isTrue);
    expect(match(''), isTrue);
    expect(match('5329999999'), isFalse);
    expect(match('alfa'), isFalse);
  });
}
