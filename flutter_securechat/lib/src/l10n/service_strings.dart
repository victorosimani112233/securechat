import 'dart:ui';

import '../l10n/generated/app_localizations.dart';

/// `BuildContext` olmayan servisler icin yerellestirilmis metin saglayicisi.
///
/// Bildirim, sohbet onizlemesi ve grup sistem mesajlari gibi kullaniciya
/// gorunen metinler servis katmaninda uretiliyor. Bu katmanda `BuildContext`
/// bulunmadigi icin metinler kaynak koda Turkce olarak gomulmustu; sonuc,
/// uygulama Ingilizce/Almanca/Arapca'ya alinsa bile bu metinlerin Turkce
/// kalmasiydi.
///
/// [AppLocalizations.delegate] context olmadan da yuklenebildigi icin dogru
/// cozum budur: aktif dil tercihi verilir, metinler oradan okunur.
class ServiceStrings {
  ServiceStrings({required Future<String?> Function() languageCode})
    : _languageCode = languageCode;

  /// Test ve varsayilan kullanim icin sabit dilli saglayici.
  ServiceStrings.fixed(String code)
    : _languageCode = (() async => code);

  final Future<String?> Function() _languageCode;
  AppLocalizations? _cached;
  String? _cachedCode;

  static const _supported = {'tr', 'en', 'de', 'ar'};

  Future<AppLocalizations> load() async {
    final requested = await _languageCode();
    final code = _supported.contains(requested)
        ? requested!
        : _resolveSystem();
    final cached = _cached;
    if (cached != null && _cachedCode == code) return cached;
    final loaded = await AppLocalizations.delegate.load(Locale(code));
    _cached = loaded;
    _cachedCode = code;
    return loaded;
  }

  /// Dil tercihi 'system' ise cihaz dilini kullanir, desteklenmiyorsa
  /// sablon dile (Ingilizce) duser.
  static String _resolveSystem() {
    final device = PlatformDispatcher.instance.locale.languageCode;
    return _supported.contains(device) ? device : 'en';
  }

  /// Dil tercihi degistiginde onbellek gecersiz kilinir.
  void invalidate() {
    _cached = null;
    _cachedCode = null;
  }
}
