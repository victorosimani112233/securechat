import 'dart:io';

const _routeEvidence = <String, ({String status, String evidence, String note})>{
  'GET /': (
    status: 'SERVER_ONLY',
    evidence:
        'flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt',
    note: 'Service landing endpoint; mobile runtime does not consume it.',
  ),
  'GET /metrics': (
    status: 'SERVER_ONLY',
    evidence:
        'flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt',
    note:
        'Prometheus operations endpoint; intentionally not exposed in the client.',
  ),
  'GET /health': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/network/socket_diagnostics.dart',
    note: 'Redacted server compatibility probe.',
  ),
  'GET /api/v1/latest-version': (
    status: 'SERVER_ONLY',
    evidence:
        'flutter_securechat/server_hardened/signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt',
    note: 'No Kotlin Android caller exists; store/version policy endpoint.',
  ),
  'GET /api/v1/directory/config': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Pinned blind-RSA OPRF public configuration.',
  ),
  'POST /api/v1/directory/evaluate': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Authenticated fixed-size blinded contact evaluation.',
  ),
  'GET /api/v1/directory/snapshot': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Token-labeled and token-sealed private membership snapshot.',
  ),
  'POST /api/v1/users/directory-token': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/contacts/private_contact_discovery.dart',
    note: 'Authenticated account owner directory-key migration.',
  ),
  'POST /api/v1/otp/request': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'OTP request.',
  ),
  'POST /api/v1/otp/verify': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'OTP verification and registration token.',
  ),
  'POST /api/v1/users/register': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'OTP-bound hash-only registration; no reversible phone envelope.',
  ),
  'POST /api/v1/auth/logout': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Refresh-token revocation.',
  ),
  'POST /api/v1/account/delete': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Authenticated account deletion.',
  ),
  'POST /api/v1/auth/refresh': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Access and refresh token rotation.',
  ),
  'GET /api/v1/ice/config': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/media/ice_server_fetcher.dart',
    note: 'Authenticated short-lived TURN configuration.',
  ),
  'POST /api/v1/prekeys/upload': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/auth/auth_api.dart',
    note: 'Initial Signal V3 bundle upload.',
  ),
  'POST /api/v1/prekeys/refresh': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/crypto/pre_key_maintenance_service.dart',
    note: 'One-time prekey replenishment with failed-upload rollback.',
  ),
  'GET /api/v1/users/{userId}/prekeys': (
    status: 'COVERED',
    evidence:
        'flutter_securechat/lib/src/crypto/signal_protocol_crypto_service.dart',
    note: 'Authenticated peer bundle fetch.',
  ),
  'GET /api/v1/sfu/room/{groupId}': (
    status: 'WS_EQUIVALENT',
    evidence: 'flutter_securechat/lib/src/media/call_manager.dart',
    note:
        'Kotlin client also uses authenticated group status/SFU WebSocket messages; HTTP route is an operations/recovery view.',
  ),
  'POST /api/v1/fcm/register': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/push/push_service.dart',
    note: 'FCM/APNs transport token registration.',
  ),
  'POST /api/v1/fcm/unregister': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/push/push_service.dart',
    note: 'Transport token removal.',
  ),
  'WS /ws': (
    status: 'COVERED',
    evidence: 'flutter_securechat/lib/src/services/signaling_service.dart',
    note:
        'Bearer-authenticated signaling, reconnect, size limit and codec path.',
  ),
};

void main() {
  final flutterRoot = Directory.current;
  final repositoryRoot = flutterRoot.parent;
  final routesFile = File(
    '${flutterRoot.path}/server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/HttpRoutes.kt',
  );
  final websocketFile = File(
    '${flutterRoot.path}/server_hardened/signaling-server/src/main/kotlin/'
    'com/securechat/signaling/WebSocketRoutes.kt',
  );
  final kotlinSignals = File(
    '${repositoryRoot.path}/network/src/main/java/'
    'com/securechat/network/SignalMessage.kt',
  );
  final dartSignals = File(
    '${flutterRoot.path}/lib/src/core/signal_message.dart',
  );
  for (final file in [routesFile, websocketFile, kotlinSignals, dartSignals]) {
    if (!file.existsSync()) {
      stderr.writeln('Missing contract source: ${file.path}');
      exitCode = 2;
      return;
    }
  }

  final routeSource = routesFile.readAsStringSync();
  final actualRoutes = <String>{};
  final routePattern = RegExp(r'\b(get|post|put|delete)\("([^"]+)"\)');
  for (final match in routePattern.allMatches(routeSource)) {
    actualRoutes.add('${match[1]!.toUpperCase()} ${match[2]}');
  }
  final wsSource = websocketFile.readAsStringSync();
  for (final match in RegExp(
    r'\bwebSocket\("([^"]+)"\)',
  ).allMatches(wsSource)) {
    actualRoutes.add('WS ${match[1]}');
  }

  final missingMappings = actualRoutes.difference(_routeEvidence.keys.toSet());
  final staleMappings = _routeEvidence.keys.toSet().difference(actualRoutes);
  final missingEvidence = <String>[];
  for (final entry in _routeEvidence.entries) {
    if (!File('${repositoryRoot.path}/${entry.value.evidence}').existsSync()) {
      missingEvidence.add('${entry.key}: ${entry.value.evidence}');
    }
  }

  final kotlinTypes = RegExp(r'@SerialName\("([^"]+)"\)')
      .allMatches(kotlinSignals.readAsStringSync())
      .map((match) => match[1]!)
      .toSet();
  final dartTypes = RegExp(r"String get type => '([^']+)'")
      .allMatches(dartSignals.readAsStringSync())
      .map((match) => match[1]!)
      .toSet();
  final missingDartTypes = kotlinTypes.difference(dartTypes);
  final extraDartTypes = dartTypes.difference(kotlinTypes);

  final output = StringBuffer()
    ..writeln('# Hardened Ktor Server Contract Audit')
    ..writeln()
    ..writeln(
      'Bu dosya `tool/generate_server_contract_audit.dart` ile uretilir.',
    )
    ..writeln(
      'Server route veya Signal discriminator degisirse esleme eksigi CI-benzeri',
    )
    ..writeln('kontrolde hata koduyla yakalanir.')
    ..writeln()
    ..writeln('## HTTP ve WebSocket route eslemesi')
    ..writeln()
    ..writeln('| Server route | Durum | Flutter kaniti | Karar |')
    ..writeln('|---|---|---|---|');
  final sortedRoutes = actualRoutes.toList()..sort();
  for (final route in sortedRoutes) {
    final evidence = _routeEvidence[route];
    output.writeln(
      '| `$route` | ${evidence?.status ?? 'UNMAPPED'} | '
      '`${evidence?.evidence ?? '-'}` | ${evidence?.note ?? 'Esleme yok'} |',
    );
  }
  output
    ..writeln()
    ..writeln('## Signal codec')
    ..writeln()
    ..writeln('- Kotlin discriminator: ${kotlinTypes.length}')
    ..writeln('- Flutter discriminator: ${dartTypes.length}')
    ..writeln(
      '- Flutter eksigi: ${missingDartTypes.isEmpty ? 'yok' : missingDartTypes.join(', ')}',
    )
    ..writeln(
      '- Flutter fazlasi: ${extraDartTypes.isEmpty ? 'yok' : extraDartTypes.join(', ')}',
    )
    ..writeln()
    ..writeln('## Sonuc')
    ..writeln()
    ..writeln(
      '- Route: ${actualRoutes.length}/${actualRoutes.length} kararli esleme',
    )
    ..writeln(
      '- Codec: ${kotlinTypes.length}/${kotlinTypes.length} birebir discriminator',
    )
    ..writeln()
    ..writeln('## Gizlilik nedeniyle kasitli wire daraltmalari')
    ..writeln()
    ..writeln(
      '- `group_notification`, `group_directory_sync_v2` ve '
      '`group_message_fanout` production server tarafindan reddedilir.',
    )
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
      '- Admin audit outer `eventType` yalniz `PRIVATE_EVENT` olabilir; gercek '
      'olay turu recipient-specific E2EE payload icindedir.',
    );
  final outputFile = File('${flutterRoot.path}/docs/SERVER_CONTRACT_AUDIT.md');
  outputFile.writeAsStringSync(output.toString());

  if (missingMappings.isNotEmpty ||
      staleMappings.isNotEmpty ||
      missingEvidence.isNotEmpty ||
      missingDartTypes.isNotEmpty ||
      extraDartTypes.isNotEmpty) {
    stderr
      ..writeln('Unmapped routes: $missingMappings')
      ..writeln('Stale mappings: $staleMappings')
      ..writeln('Missing evidence: $missingEvidence')
      ..writeln('Missing Dart signal types: $missingDartTypes')
      ..writeln('Extra Dart signal types: $extraDartTypes');
    exitCode = 1;
  }
}
