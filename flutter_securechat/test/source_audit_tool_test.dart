import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `tool/generate_source_audit.dart` silinmis libsignal dosyalarini hedef
/// gosterdigi icin aylarca calismadi (2026-10-14'te fark edildi). Kural
/// tablosundaki her uretim ve test yolu var olmali.
void main() {
  test('every path named by the source audit generator exists', () {
    final source = File('tool/generate_source_audit.dart').readAsStringSync();
    final paths = RegExp(
      r"'((?:lib|test)/[^'*]+\.dart)'",
    ).allMatches(source).map((match) => match[1]!).toSet();
    expect(paths, isNotEmpty);
    final missing = paths.where((path) => !File(path).existsSync()).toList()
      ..sort();
    expect(missing, isEmpty);
  });
}
