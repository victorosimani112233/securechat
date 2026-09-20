import 'package:flutter_securechat/src/l10n/service_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: servis katmani metinleri (bildirim basliklari, kacirilan arama
/// onizlemesi, guvenlik uyarisi) BuildContext olmadigi icin kaynak koda
/// Turkce gomulmustu ve uygulama baska bir dile alinsa bile Turkce kaliyordu.
void main() {
  test('desteklenen her dil kendi metnini dondurur', () async {
    final expected = {
      'tr': 'Kaçırılan arama',
      'en': 'Missed call',
      'de': 'Verpasster Anruf',
    };
    for (final entry in expected.entries) {
      final l10n = await ServiceStrings.fixed(entry.key).load();
      expect(l10n.missed_call, entry.value, reason: entry.key);
    }
    final arabic = await ServiceStrings.fixed('ar').load();
    expect(arabic.missed_call, isNot('Kaçırılan arama'));
  });

  test('guvenlik uyarisi cevrilmis geliyor', () async {
    final tr = await ServiceStrings.fixed('tr').load();
    final en = await ServiceStrings.fixed('en').load();
    expect(tr.security_number_changed, contains('Güvenlik numarası'));
    expect(en.security_number_changed, contains('security number'));
    expect(en.security_number_changed, isNot(contains('Güvenlik')));
  });

  test('kacirilan arama govdesi peer adini yerlestirir', () async {
    final en = await ServiceStrings.fixed('en').load();
    expect(en.missed_call_from('Ada'), contains('Ada'));
  });

  test('desteklenmeyen dil kodu sablon dile duser', () async {
    final l10n = await ServiceStrings.fixed('xx').load();
    expect(l10n.missed_call, isNotEmpty);
  });
}
