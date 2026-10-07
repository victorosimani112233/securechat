/// Store'larin uygulama icinden erisilebilir olmasini istedigi herkese acik
/// hukuki sayfalar (`server_hardened/deploy/site`).
///
/// Alan adi kesinlesince yalniz `SECURECHAT_LEGAL_BASE_URL` derleme
/// tanimi degisir; nginx uzantisiz adresleri `.html` dosyasina cozer.
abstract final class LegalLinks {
  static const base = String.fromEnvironment(
    'SECURECHAT_LEGAL_BASE_URL',
    defaultValue: 'https://tereaiqos.online',
  );

  static Uri get privacy => Uri.parse('$base/privacy');
  static Uri get terms => Uri.parse('$base/terms');
  static Uri get childSafety => Uri.parse('$base/child-safety');
}
