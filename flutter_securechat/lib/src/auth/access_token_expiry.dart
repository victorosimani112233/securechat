import 'dart:convert';

/// Erisim jetonunun (JWT) bitis zamani; okunamazsa null.
///
/// Imza dogrulanmaz: deger yalniz "yenilemek gerekir mi" karari icindir,
/// guvenlik karari sunucudadir.
DateTime? accessTokenExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (exp * 1000).toInt(),
      isUtc: true,
    );
  } on FormatException {
    return null;
  }
}

/// Jeton yoksa, okunamiyorsa ya da [margin] icinde bitecekse true.
///
/// Erisim jetonu bir saat gecerli; arka plan isi 15 dakikada bir calisir.
/// Her calismada yenilemek refresh jetonunu gereksiz yere donduruyor ve
/// her seferinde ag istegi yapiyordu. Sapan cihaz saatine karsi pay
/// birakilir; jeton yine de reddedilirse soket ve HTTP istemcileri 401'de
/// kendileri yeniler.
bool accessTokenNeedsRefresh(
  String? token, {
  DateTime? now,
  Duration margin = const Duration(minutes: 10),
}) {
  if (token == null || token.isEmpty) return true;
  final expiry = accessTokenExpiry(token);
  if (expiry == null) return true;
  return !expiry.isAfter((now ?? DateTime.now()).toUtc().add(margin));
}
