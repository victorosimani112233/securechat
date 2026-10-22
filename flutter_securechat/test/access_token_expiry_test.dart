import 'dart:convert';

import 'package:flutter_securechat/src/auth/access_token_expiry.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Object? payload) {
  String part(Object? value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.signature';
}

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  test('a token valid beyond the margin is not refreshed', () {
    final token = _jwt({'exp': seconds(now.add(const Duration(minutes: 45)))});
    expect(accessTokenExpiry(token), now.add(const Duration(minutes: 45)));
    expect(accessTokenNeedsRefresh(token, now: now), isFalse);
  });

  test('a token close to expiry or expired is refreshed', () {
    for (final left in [
      const Duration(minutes: 9),
      Duration.zero,
      const Duration(minutes: -5),
    ]) {
      final token = _jwt({'exp': seconds(now.add(left))});
      expect(accessTokenNeedsRefresh(token, now: now), isTrue, reason: '$left');
    }
  });

  test('a missing or unreadable token is refreshed', () {
    expect(accessTokenNeedsRefresh(null, now: now), isTrue);
    expect(accessTokenNeedsRefresh('', now: now), isTrue);
    expect(accessTokenNeedsRefresh('opaque-token', now: now), isTrue);
    expect(accessTokenNeedsRefresh('a.%%%.c', now: now), isTrue);
    expect(accessTokenNeedsRefresh(_jwt({'sub': 'x'}), now: now), isTrue);
    expect(accessTokenNeedsRefresh(_jwt(['exp']), now: now), isTrue);
  });
}
