import 'legal_links.dart';

/// Davet mesajinda paylasilan indirme adresi.
///
/// Magaza sayfalari yayina girince yalniz `SECURECHAT_INVITE_URL` derleme
/// tanimi degisir. Tanimsizsa herkese acik tanitim sitesi kullanilir.
abstract final class InviteLink {
  static const _configured = String.fromEnvironment('SECURECHAT_INVITE_URL');

  static String get url => _configured.isEmpty ? LegalLinks.base : _configured;
}
