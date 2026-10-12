import '../auth/phone_privacy.dart';

/// Rehber ve kisi secici aramasi: ad (buyuk/kucuk harf duyarsiz) ya da
/// numara.
///
/// Numara ham dize olarak araniyordu; kayitli numara "+90 532 100 04 13"
/// iken "5321000413" bulunamiyordu (QA 2026-10-12 Bulgu 7). Sorgu en az 3
/// rakam iceriyorsa iki taraf da rakama indirgenir ve ulke/0 oneki farki
/// [normalizePhoneDigits] ile kapatilir.
bool matchesContactQuery({
  required String name,
  required String phone,
  required String query,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return true;
  if (name.toLowerCase().contains(trimmed.toLowerCase())) return true;
  final queryDigits = trimmed.replaceAll(RegExp('[^0-9]'), '');
  if (queryDigits.length < 3) return phone.contains(trimmed);
  final phoneDigits = phone.replaceAll(RegExp('[^0-9]'), '');
  if (phoneDigits.isEmpty) return false;
  return phoneDigits.contains(queryDigits) ||
      normalizePhoneDigits(phone).contains(normalizePhoneDigits(trimmed));
}
