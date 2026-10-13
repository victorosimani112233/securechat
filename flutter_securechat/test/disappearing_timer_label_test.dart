import 'package:flutter/widgets.dart';
import 'package:flutter_securechat/src/chat/disappearing_timer_notice.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-13 T17: secenek listesinde 1 saat "0 gun" yaziyordu, sistem
/// satiri ise "1 saat" diyordu. Her secenegin etiketi sistem satirindaki
/// sureyle ayni olmali.
void main() {
  final l10n = lookupAppLocalizations(const Locale('tr'));
  const options = <Duration>[
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 7),
    Duration(days: 30),
  ];

  test('secenek etiketleri sifir birim gostermez', () {
    expect(
      options.map(
        (d) => disappearingTimerDurationLabel(l10n, d.inMilliseconds),
      ),
      [l10n.hours(1), l10n.days(1), l10n.days(7), l10n.days(30)],
    );
    expect(disappearingTimerDurationLabel(l10n, 0), l10n.off);
  });

  test('sistem satiri secenekle ayni sureyi yazar', () {
    for (final option in options) {
      final label = disappearingTimerDurationLabel(l10n, option.inMilliseconds);
      expect(
        localDisappearingTimerNotice(l10n, option.inMilliseconds),
        contains(label),
      );
    }
  });
}
