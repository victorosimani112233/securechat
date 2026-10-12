/// Karsi tarafin kullaniciya gosterilecek adi.
///
/// Ic kimlik (UUID) hicbir ekranda ad olarak gosterilmez. Rehberde olmayan
/// birinden gelen ilk mesajda ad bilinmiyordu ve yedek olarak gonderenin
/// kimligi yaziliyordu; sohbet listesi, baslik ve gelen arama ekrani UUID
/// gosteriyordu (QA 2026-10-12 Bulgu 3).
library;

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// [name] gosterilebilir bir ad degilse true: bos, karsi tarafin kimligiyle
/// ayni ya da UUID bicimli.
bool isOpaquePeerName(String name, {String? peerId}) {
  final trimmed = name.trim();
  return trimmed.isEmpty ||
      (peerId != null && trimmed == peerId) ||
      _uuidPattern.hasMatch(trimmed);
}

/// Gosterilecek ad: insan adi, yoksa numara, yoksa [unknown].
String peerDisplayName(
  String name, {
  String? peerId,
  String phone = '',
  required String unknown,
}) {
  if (!isOpaquePeerName(name, peerId: peerId)) return name.trim();
  final number = phone.trim();
  return number.isEmpty ? unknown : number;
}
