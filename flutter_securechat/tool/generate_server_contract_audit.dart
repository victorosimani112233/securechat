// Hardened sunucu sozlesme denetimi.
//
// Bu aracin onceki hali uc sekilde yaniltiyordu ve CI'da bu yuzden
// `continue-on-error: true` ile isaretlenmisti:
//
//  1. Signal discriminator'larini **olu legacy Kotlin istemcisinden**
//     (`network/src/main/java/.../SignalMessage.kt`) okuyordu. O modul artik
//     calisan urunun parcasi degil; Flutter istemcisi ile karsilastirmasi
//     gurultu uretiyordu. Dogru otorite sunucunun kendisidir.
//  2. Ozet bolumu `${routes.length}/${routes.length}` yaziyordu, yani
//     esleme eksigi olsa bile raporun sonunda "hepsi kararli" goruyordunuz.
//     Rapor fail-open'di.
//  3. Hicbir route'un **hangi yetki guard'i** ardinda oldugunu kaydetmiyordu.
//     Guard'siz yeni bir route sessizce eklenebilirdi — sealed sender'in
//     anonim `/api/v2/sealed-sender/messages` girisi tam boyle fark
//     edilmeden durmustu.
//
// Yeni bolusum: **kod hangi guard'in calistiginin otoritesidir**, asagidaki
// tablo ise ne amaclandiginin. Ikisi ayrilirsa arac hata verir. Guard'siz
// bir route, neden guard'siz oldugu yazilana kadar denetimi kirmis olur.

import 'dart:io';

/// Bir route'un ardinda calisan yetki kontrolu.
enum Guard {
  /// `requireServicePrincipal` — ayri anahtarla imzali servis assertion'i.
  /// Kullanici token'i gecmez, yani normal istemci bu route'u cagiramaz.
  servicePrincipal,

  /// `requirePrincipal` — kullanici veya servis principal'i.
  principal,

  /// `requireAuth` — kullanici access token'i.
  auth,

  /// `MetricsAccess.isAuthorized` — operator bearer token'i.
  bearerToken,

  /// `AbuseReports.requireAdmin` — ayri `REPORTS_ADMIN_TOKEN`. Kullanici
  /// token'i gecmez; token tanimsizsa route 404 doner.
  adminToken,

  /// Guard yok ve olmamasi dogru: istek govdesinden bir kimlik tuketip
  /// token basan kayit/dogrulama yollari. Henuz token'i olmayan bir
  /// istemci cagirir.
  preAuth,

  /// Guard yok ve olmamasi dogru: kimlik tasimayan, sabit cevap donen
  /// yollar.
  public,
}

/// `Guard.preAuth` ve `Guard.public` kodda ikisi de "guard cagrisi yok"
/// olarak gorunur. Ayrimi tablo tasir, cunku ikisinin riski ayni degil:
/// pre-auth bir yol kimlik tuketir, public bir yol tuketmez.
const _detectedAsUnguarded = {Guard.preAuth, Guard.public};

typedef RouteContract = ({
  /// COVERED: Flutter istemcisi cagiriyor ve kanit dosyasi var.
  /// SERVER_ONLY: istemci bilerek cagirmaz.
  /// WS_EQUIVALENT: istemci ayni isi WebSocket uzerinden yapar.
  String status,
  Guard guard,
  String evidence,
  String note,
});

const _serverRoot =
    'flutter_securechat/server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/HttpRoutes.kt';

/// HttpRoutes.kt disinda route tanimlayan ve denetime giren dosyalar.
const _extraRouteSources = [
  'flutter_securechat/server_hardened/signaling-server/src/main/kotlin/'
      'com/securechat/signaling/AbuseReports.kt',
];

const _routeContracts = <String, RouteContract>{
  'GET /': (
    status: 'SERVER_ONLY',
    guard: Guard.public,
    evidence: _serverRoot,
    note: 'Servis karsilama yolu; sabit cevap, kimlik tasimaz.',
  ),
  'GET /health': (
    status: 'COVERED',
    guard: Guard.public,
    evidence: 'flutter_securechat/lib/src/network/socket_diagnostics.dart',
    note:
        'Redakte edilmis uyumluluk yoklamasi; anonim cagrilabilir olmasi '
        'kasitli, stack ayrintisi dondurmez.',
  ),
  'GET /ready': (
    status: 'SERVER_ONLY',
    guard: Guard.bearerToken,
    evidence: _serverRoot,
    note:
        'Readiness; bagimlilik durumu operator bilgisidir, bu yuzden '
        'metrics bearer token ardinda.',
  ),
  'GET /metrics': (
    status: 'SERVER_ONLY',
    guard: Guard.bearerToken,
    evidence: _serverRoot,
    note: 'Prometheus; istemciye acilmaz.',
  ),
  'GET /api/v1/version': (
    status: 'SERVER_ONLY',
    guard: Guard.bearerToken,
    evidence: _serverRoot,
    note:
        'Build kimligi operator bilgisidir; surum/commit anonim '
        'sizdirilmaz.',
  ),
  'GET /api/v1/latest-version': (
    status: 'SERVER_ONLY',
    guard: Guard.public,
    evidence: _serverRoot,
    note: 'Magaza/surum politikasi yolu; Flutter istemcisinde cagiran yok.',
  ),
  'GET /api/v1/directory/config': (
    status: 'COVERED',
    guard: Guard.public,
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note:
        'Pinlenmis blind-RSA OPRF acik yapilandirmasi; kayit oncesi '
        'gerektigi icin public.',
  ),
  'POST /api/v1/directory/evaluate': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Sabit boyutlu korlenmis kisi degerlendirmesi.',
  ),
  'GET /api/v1/directory/snapshot': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Token-etiketli ve token-sealed uyelik anlik goruntusu.',
  ),
  'POST /api/v1/users/directory-token': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Hesap sahibinin dizin anahtari gocu.',
  ),
  'POST /api/v1/otp/request': (
    status: 'COVERED',
    guard: Guard.public,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note:
        'OTP istegi; henuz hesap yok, bu yuzden guard yok. Kotuye '
        'kullanim siniri rate limit ile.',
  ),
  'POST /api/v1/otp/verify': (
    status: 'COVERED',
    guard: Guard.preAuth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note:
        'OTP tuketir ve kayit tokeni basar. Guard yerine gecen sey '
        'OTP\'nin kendisidir.',
  ),
  'POST /api/v1/users/register': (
    status: 'COVERED',
    guard: Guard.preAuth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note:
        'Kayit tokeni tuketir, access+refresh basar. Telefon yalniz '
        'geri cevrilemez ozet olarak girer.',
  ),
  'POST /api/v1/auth/refresh': (
    status: 'COVERED',
    guard: Guard.preAuth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note:
        'Refresh tokeni tuketir ve dondurur. Access token gecerli '
        'olmadiginda da cagrilabilmesi gerekir, bu yuzden requireAuth yok.',
  ),
  'POST /api/v1/auth/logout': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Refresh tokeni iptali.',
  ),
  'POST /api/v1/account/delete': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Kimlik dogrulamali hesap silme.',
  ),
  'POST /api/v1/reports': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note:
        'Kotuye kullanim bildirimi; icerik tasimaz, bilinmeyen alan '
        'reddedilir. Anonim yazma yolu olmasin diye kimlik zorunlu.',
  ),
  'GET /api/v1/admin/reports': (
    status: 'SERVER_ONLY',
    guard: Guard.adminToken,
    evidence: 'flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md',
    note: 'Moderasyon listesi; istemci cagirmaz, kullanici token\'i gecmez.',
  ),
  'POST /api/v1/admin/reports/{reportId}/close': (
    status: 'SERVER_ONLY',
    guard: Guard.adminToken,
    evidence: 'flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md',
    note: 'Moderasyon karari kaydi.',
  ),
  'POST /api/v1/admin/accounts/{userId}/remove': (
    status: 'SERVER_ONLY',
    guard: Guard.adminToken,
    evidence: 'flutter_securechat/server_hardened/docs/ABUSE_REPORTS.md',
    note: 'Moderasyonla hesap kaldirma; kullanici silme yoluyla ayni temizlik.',
  ),
  'GET /api/v1/ice/config': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/media/ice_server_fetcher.dart',
    note: 'Kisa omurlu TURN yapilandirmasi.',
  ),
  'POST /api/v1/prekeys/upload': (
    status: 'COVERED',
    guard: Guard.principal,
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Ilk bundle yuklemesi.',
  ),
  'POST /api/v1/prekeys/refresh': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence:
        'flutter_securechat/lib/src/crypto/pre_key_maintenance_service.dart',
    note: 'One-time prekey tamamlama; basarisiz yuklemede geri alma.',
  ),
  'GET /api/v1/prekeys/status': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence:
        'flutter_securechat/lib/src/crypto/pre_key_maintenance_service.dart',
    note: 'Kalan one-time prekey sayisi; tamamlama kararini bu verir.',
  ),
  'GET /api/v1/users/{userId}/prekeys': (
    status: 'SERVER_ONLY',
    guard: Guard.servicePrincipal,
    evidence: _serverRoot,
    note:
        'DIKKAT: guard servis assertion\'i, yani kullanici token\'iyla '
        'cagrilamaz. Bir istemci peer bundle\'i cekemez. Vodozemac gocunde '
        'bu route requirePrincipal\'a cevrilmeli; bkz. '
        'docs/migration/TASK_05_server.md.',
  ),
  'GET /api/v1/sfu/room/{groupId}': (
    status: 'WS_EQUIVALENT',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/media/call_manager.dart',
    note:
        'Istemci ayni bilgiyi WebSocket grup cagri sinyalleriyle alir; '
        'HTTP yolu operasyon/kurtarma gorunumu.',
  ),
  'POST /api/v1/fcm/register': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/push/push_service.dart',
    note: 'FCM/APNs tasima tokeni kaydi.',
  ),
  'POST /api/v1/fcm/unregister': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/push/push_service.dart',
    note: 'Tasima tokeni silme.',
  ),
  // --- /api/v2 PQXDH yolu: hicbir istemci cagirmiyor, kaldirilacak ---
  'POST /api/v2/prekeys/upload': (
    status: 'SERVER_ONLY',
    guard: Guard.principal,
    evidence: _serverRoot,
    note:
        'PQXDH bundle yuklemesi. Istemci vodozemac\'a gectigi icin '
        'KULLANILMIYOR; kaldirilacak.',
  ),
  'POST /api/v2/prekeys/refresh': (
    status: 'SERVER_ONLY',
    guard: Guard.auth,
    evidence: _serverRoot,
    note: 'PQXDH prekey tamamlama. KULLANILMIYOR; kaldirilacak.',
  ),
  'GET /api/v2/prekeys/status': (
    status: 'SERVER_ONLY',
    guard: Guard.auth,
    evidence: _serverRoot,
    note: 'PQXDH prekey sayaci. KULLANILMIYOR; kaldirilacak.',
  ),
  'GET /api/v2/users/{userId}/prekeys': (
    status: 'SERVER_ONLY',
    guard: Guard.principal,
    evidence: _serverRoot,
    note:
        'PQXDH peer bundle. KULLANILMIYOR; kaldirilacak. Guard deseni '
        'v1 esdegerinden dogru olan budur.',
  ),
  'GET /api/v2/users/{userId}/prekeys/capability': (
    status: 'SERVER_ONLY',
    guard: Guard.principal,
    evidence: _serverRoot,
    note: 'PQXDH yetenek sorgusu. KULLANILMIYOR; kaldirilacak.',
  ),
  'WS /ws': (
    status: 'COVERED',
    guard: Guard.auth,
    evidence: 'flutter_securechat/lib/src/services/signaling_service.dart',
    note:
        'Bearer dogrulamali sinyalleme; reconnect, boyut siniri ve codec '
        'yolu.',
  ),
};

/// Sunucunun acikca REDDETTIGI cerceve turleri ve reddin gerekcesi.
///
/// Sunucuda yeni bir ret eklenirse burada da yazilmali: sessizce dusurulen
/// bir cerceve, istemcide teshisi en zor hata sinifidir.
const _declaredRejections = <String, String>{
  'group_notification':
      'Sabit grup tokeni dis zarfta tasinmaz; grup kontrolu her aliciya '
      'ayri ordinary encrypted_message olarak gider.',
  'group_directory_sync_v2': 'Grup dizini sunucuda tutulmaz.',
  'group_message_fanout':
      'Fanout sunucuya grup grafigi verirdi; istemci her aliciya ayri '
      'zarf gonderir.',
  'admin_encrypted_log':
      'Dis eventType yalniz PRIVATE_EVENT olabilir; gercek olay turu '
      'recipient-specific E2EE payload icindedir.',
};

/// Sunucunun siniflandirdigi ama Flutter istemcisinin hic uretmedigi
/// turler ve bunun neden dogru oldugu.
///
/// Bos olmasi gerekmiyor; gerekcesi YAZILMIS olmasi gerekiyor. Beyan
/// edilmemis yeni bir bosluk denetimi kirar, cunku o durumda ya
/// siniflandirma olu ya istemci bir cerceveyi gondermeyi unutmus olur ve
/// ikisinin farki ancak bakarak anlasilir.
const _declaredClientGaps = <String, String>{
  'audio_data':
      'Legacy Android istemcisinin bant-ici ses cercevesi. Flutter istemcisi '
      'sesi WebRTC ile tasir ve bu turu hic uretmez. Siniflandirma '
      'BILEREK duruyor: savunma amaclidir, sahadaki eski bir istemci '
      'gonderirse cerceve kalici offline kuyruga yazilmasin.',
  'video_data': 'Ayni gerekce; legacy bant-ici video cercevesi.',
};

({Set<String> routes, Map<String, Guard> guards}) _parseHttpRoutes(
  String source,
) {
  final routes = <String>{};
  final guards = <String, Guard>{};
  final pattern = RegExp(r'\b(get|post|put|delete)\("([^"]+)"\)\s*\{');
  for (final match in pattern.allMatches(source)) {
    final key = '${match[1]!.toUpperCase()} ${match[2]}';
    routes.add(key);
    guards[key] = _detectGuard(_routeBody(source, match.end - 1));
  }
  return (routes: routes, guards: guards);
}

/// Route govdesini parantez sayarak alir. Satir sayisina veya girintiye
/// guvenmek kirilgandir; govde ic bloklar icerir.
String _routeBody(String source, int openBraceIndex) {
  var depth = 0;
  for (var i = openBraceIndex; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(openBraceIndex, i);
    }
  }
  return source.substring(openBraceIndex);
}

Guard _detectGuard(String body) {
  if (body.contains('AbuseReports.requireAdmin(')) return Guard.adminToken;
  if (body.contains('requireServicePrincipal(')) return Guard.servicePrincipal;
  if (body.contains('requirePrincipal(')) return Guard.principal;
  if (body.contains('requireAuth(')) return Guard.auth;
  if (body.contains('MetricsAccess.isAuthorized')) return Guard.bearerToken;
  // Kodda ayrim yok; tablo preAuth mi public mi oldugunu soyler.
  return Guard.public;
}

Set<String> _parseKotlinStringSet(String source, String name) {
  final match = RegExp(
    'val\\s+$name\\s*=\\s*setOf\\(([^)]*)\\)',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return const {};
  return RegExp(r'"([^"]+)"').allMatches(match[1]!).map((m) => m[1]!).toSet();
}

void main() {
  final flutterRoot = Directory.current;
  final repositoryRoot = flutterRoot.parent;
  final routesFile = File('${repositoryRoot.path}/$_serverRoot');
  final websocketFile = File(
    '${flutterRoot.path}/server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/WebSocketRoutes.kt',
  );
  final messageTypesFile = File(
    '${flutterRoot.path}/server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/MessageTypes.kt',
  );
  final dartSignals = File(
    '${flutterRoot.path}/lib/src/core/signal_message.dart',
  );
  for (final file in [
    routesFile,
    websocketFile,
    messageTypesFile,
    dartSignals,
  ]) {
    if (!file.existsSync()) {
      stderr.writeln('Eksik sozlesme kaynagi: ${file.path}');
      exitCode = 2;
      return;
    }
  }

  final parsed = _parseHttpRoutes(routesFile.readAsStringSync());
  final actualRoutes = {...parsed.routes};
  final guards = {...parsed.guards};
  for (final path in _extraRouteSources) {
    final file = File('${repositoryRoot.path}/$path');
    if (!file.existsSync()) {
      stderr.writeln('Eksik sozlesme kaynagi: ${file.path}');
      exitCode = 2;
      return;
    }
    final extra = _parseHttpRoutes(file.readAsStringSync());
    actualRoutes.addAll(extra.routes);
    guards.addAll(extra.guards);
  }

  final wsSource = websocketFile.readAsStringSync();
  for (final match in RegExp(
    r'\bwebSocket\("([^"]+)"\)',
  ).allMatches(wsSource)) {
    final key = 'WS ${match[1]}';
    actualRoutes.add(key);
    // WebSocket el sikismasi guard'i route govdesinde degil, baglanti
    // kurulumunda yapilir; sozlesme tablosundaki beyan gecerlidir.
    guards[key] = _routeContracts[key]?.guard ?? Guard.public;
  }

  final declaredRoutes = _routeContracts.keys.toSet();
  final unmapped = actualRoutes.difference(declaredRoutes).toList()..sort();
  final stale = declaredRoutes.difference(actualRoutes).toList()..sort();

  // Kanit dosyasi gercekten var mi.
  final missingEvidence = <String>[];
  for (final entry in _routeContracts.entries) {
    if (!File('${repositoryRoot.path}/${entry.value.evidence}').existsSync()) {
      missingEvidence.add('${entry.key}: ${entry.value.evidence}');
    }
  }

  // Guard uyusmazligi: kodda calisan guard ile beyan edilen ayni mi.
  final guardMismatches = <String>[];
  for (final entry in _routeContracts.entries) {
    final detected = guards[entry.key];
    if (detected == null) continue;
    final declared = entry.value.guard;
    if (detected == declared) continue;
    // preAuth kodda guard'siz gorunur; public ile ayni tespit sonucunu
    // verir. Beyan preAuth ise tespit public olmasi beklenir.
    if (declared == Guard.preAuth && detected == Guard.public) continue;
    guardMismatches.add(
      '${entry.key}: kod ${detected.name}, tablo ${declared.name}',
    );
  }

  // Servis assertion'i ardindaki bir route istemci tarafindan
  // cagrilamaz; COVERED beyani kendi icinde celiskilidir.
  final unreachableClaims = <String>[];
  for (final entry in _routeContracts.entries) {
    if (entry.value.guard == Guard.servicePrincipal &&
        entry.value.status == 'COVERED') {
      unreachableClaims.add(entry.key);
    }
  }

  // Guard'siz route'lar: hepsi public ya da preAuth olarak YAZILMIS olmali.
  final undeclaredUnguarded = <String>[];
  for (final route in actualRoutes) {
    if (guards[route] != Guard.public) continue;
    final contract = _routeContracts[route];
    if (contract == null) continue; // unmapped olarak ayrica raporlanir
    if (!_detectedAsUnguarded.contains(contract.guard)) {
      undeclaredUnguarded.add(route);
    }
  }

  // --- Codec: otorite sunucu, olu legacy istemci degil ---
  final messageTypesSource = messageTypesFile.readAsStringSync();
  final transient = _parseKotlinStringSet(messageTypesSource, 'TRANSIENT');
  final pendingCall = _parseKotlinStringSet(messageTypesSource, 'PENDING_CALL');
  final fileTransfer = RegExp(
    r'FILE_TRANSFER\s*=\s*"([^"]+)"',
  ).firstMatch(messageTypesSource)?.group(1);
  final serverClassified = <String>{
    ...transient,
    ...pendingCall,
    if (fileTransfer != null) fileTransfer,
  };

  final dartTypes = RegExp(r"String get type => '([^']+)'")
      .allMatches(dartSignals.readAsStringSync())
      .map((match) => match[1]!)
      .toSet();

  // Sunucunun siniflandirdigi ama istemcinin hic uretmedigi turler.
  // Ya siniflandirma olu ya istemci eksik; ikisi de bilinmeli.
  final clientGaps = serverClassified.difference(dartTypes);
  final undeclaredClientGaps =
      clientGaps
          .where((type) => !_declaredClientGaps.containsKey(type))
          .toList()
        ..sort();
  // Artik gercek olmayan beyan da hata: istemci o turu uretmeye baslamis
  // ya da siniflandirma kalkmis olabilir.
  final staleClientGaps =
      _declaredClientGaps.keys
          .where((type) => !clientGaps.contains(type))
          .toList()
        ..sort();
  final sortedClientGaps = clientGaps.toList()..sort();

  // Sunucuda acikca reddedilen turler beyan edilmis mi.
  final rejectedInCode = <String>{};
  for (final match in RegExp(r'type\s*==\s*"([^"]+)"').allMatches(wsSource)) {
    rejectedInCode.add(match[1]!);
  }
  final undeclaredRejections =
      _declaredRejections.keys
          .where((type) => !rejectedInCode.contains(type))
          .toList()
        ..sort();

  final mappedCount = actualRoutes.length - unmapped.length;

  final output = StringBuffer()
    ..writeln('# Hardened Ktor Server Contract Audit')
    ..writeln()
    ..writeln(
      'Bu dosya `tool/generate_server_contract_audit.dart` ile uretilir; '
      'elle duzenlenmez.',
    )
    ..writeln()
    ..writeln(
      'Otorite sunucudur. Her route icin **kodda calisan guard** ayristirilir '
      've tablodaki beyanla karsilastirilir; ayrilirsa arac hata koduyla '
      'doner. Guard\'siz bir route, neden guard\'siz oldugu yazilana kadar '
      'denetimi kirar.',
    )
    ..writeln()
    ..writeln('## HTTP ve WebSocket route eslemesi')
    ..writeln()
    ..writeln('| Server route | Guard | Durum | Flutter kaniti | Karar |')
    ..writeln('|---|---|---|---|---|');
  final sortedRoutes = actualRoutes.toList()..sort();
  for (final route in sortedRoutes) {
    final contract = _routeContracts[route];
    final guard = contract?.guard.name ?? guards[route]?.name ?? '-';
    output.writeln(
      '| `$route` | `$guard` | ${contract?.status ?? '**UNMAPPED**'} | '
      '`${contract?.evidence ?? '-'}` | ${contract?.note ?? 'Esleme yok'} |',
    );
  }

  output
    ..writeln()
    ..writeln('## Signal codec')
    ..writeln()
    ..writeln(
      '- Sunucunun siniflandirdigi tur: ${serverClassified.length} '
      '(`MessageTypes.kt`: TRANSIENT, PENDING_CALL, FILE_TRANSFER)',
    )
    ..writeln('- Flutter istemcisinin urettigi tur: ${dartTypes.length}')
    ..writeln(
      '- Sunucu siniflandiriyor ama istemci uretmiyor: '
      '${sortedClientGaps.isEmpty ? 'yok' : sortedClientGaps.join(', ')}',
    )
    ..writeln()
    ..writeln('### Acikca reddedilen turler')
    ..writeln();
  for (final entry in _declaredRejections.entries) {
    output.writeln('- `${entry.key}`: ${entry.value}');
  }
  if (_declaredClientGaps.isNotEmpty) {
    output
      ..writeln()
      ..writeln('### Sunucu siniflandiriyor, istemci uretmiyor — gerekceler')
      ..writeln();
    for (final entry in _declaredClientGaps.entries) {
      output.writeln('- `${entry.key}`: ${entry.value}');
    }
  }

  output
    ..writeln()
    ..writeln('## Sonuc')
    ..writeln()
    ..writeln('- Route: $mappedCount/${actualRoutes.length} eslenmis')
    ..writeln('- Eslenmemis: ${unmapped.isEmpty ? 'yok' : unmapped.join(', ')}')
    ..writeln(
      '- Guard uyusmazligi: '
      '${guardMismatches.isEmpty ? 'yok' : guardMismatches.join('; ')}',
    )
    ..writeln(
      '- Servis guard\'i ardinda olup istemci cagiriyor diye beyan edilen: '
      '${unreachableClaims.isEmpty ? 'yok' : unreachableClaims.join(', ')}',
    )
    ..writeln()
    ..writeln('## Gizlilik nedeniyle kasitli wire daraltmalari')
    ..writeln()
    ..writeln(
      '- Grup kontrolu ve grup mesaji her aliciya ayri ordinary '
      '`encrypted_message` Signal zarfi olarak gider; sabit grup tokeni dis '
      'zarfta bulunmaz.',
    )
    ..writeln(
      '- Grup cagrisi group ID yerine cagri-basina 256-bit routing nonce '
      'kullanir; client `participants` listesini bos gonderir ve server state '
      'yalniz RAM\'de ust sure siniriyla tutulur.',
    )
    ..writeln(
      '- Receipt, edit/delete/reaction/pin, typing ve disappearing timer '
      'typed frame\'leri server tarafindan plaintext kabul edilmez; sabit '
      '16 KiB `CHATCTRL:v2` payload\'i ordinary direct Signal '
      '`encrypted_message` icinde tasir.',
    )
    ..writeln(
      '- Sealed Sender mimarisi kaldirildi. `SEALED:v1:` zarfi artik '
      'uretilmiyor; kimlik dogrulamali socket uzerinde gelirse reddedilir.',
    );

  File(
    '${flutterRoot.path}/docs/SERVER_CONTRACT_AUDIT.md',
  ).writeAsStringSync(output.toString());

  final problems = <String, List<String>>{
    'Eslenmemis route': unmapped,
    'Artik var olmayan esleme': stale,
    'Eksik kanit dosyasi': missingEvidence,
    'Guard uyusmazligi (kod != tablo)': guardMismatches,
    'Guard\'siz ama public/preAuth olarak yazilmamis': undeclaredUnguarded,
    'Servis guard\'i ardinda COVERED beyani': unreachableClaims,
    'Beyan edilmemis istemci boslugu': undeclaredClientGaps,
    'Artik gercek olmayan istemci boslugu beyani': staleClientGaps,
    'Kodda bulunmayan ret beyani': undeclaredRejections,
  };
  final failed = problems.entries.where((e) => e.value.isNotEmpty).toList();
  if (failed.isNotEmpty) {
    for (final entry in failed) {
      stderr.writeln('${entry.key}: ${entry.value.join(', ')}');
    }
    exitCode = 1;
  }
}
