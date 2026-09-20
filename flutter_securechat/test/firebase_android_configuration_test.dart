import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release Firebase app matches the Android application id', () {
    final config =
        jsonDecode(File('android/app/google-services.json').readAsStringSync())
            as Map<String, Object?>;
    final clients = (config['client'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final releaseClient = clients.singleWhere((client) {
      final info = client['client_info'] as Map<String, Object?>;
      final android = info['android_client_info'] as Map<String, Object?>;
      return android['package_name'] == 'com.securechat.app';
    });
    final info = releaseClient['client_info'] as Map<String, Object?>;

    expect(
      info['mobilesdk_app_id'],
      '1:791820453236:android:d570570ff740a58e685821',
    );

    final pushSource = File(
      'lib/src/push/push_service.dart',
    ).readAsStringSync();
    expect(
      pushSource,
      contains("defaultValue: '1:791820453236:android:d570570ff740a58e685821'"),
    );
  });
}
