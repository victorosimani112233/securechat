import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/onboarding/onboarding_service.dart';
import 'package:flutter_securechat/src/onboarding/permission_service.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'permission service delegates every platform permission explicitly',
    () async {
      final platform = _RecordingPermissionPlatform();
      final service = AppPermissionService(platform);

      for (final permission in AppPermission.values) {
        expect(await service.request(permission), isTrue);
      }

      expect(platform.requested, AppPermission.values);
    },
  );

  test('onboarding acknowledgements persist only in encrypted state', () async {
    final root = await Directory.systemTemp.createTemp('onboarding_test_');
    final file = File('${root.path}/db.securejson');
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => 200 - index)),
    );
    final database = await SecureChatDatabase.open(file: file, crypto: crypto);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final service = OnboardingService(database);
    expect(await service.isIntroSeen(), isFalse);
    expect(await service.isPermissionWalkthroughSeen(), isFalse);
    await service.markIntroSeen();
    await service.markPermissionWalkthroughSeen();
    expect(await service.isIntroSeen(), isTrue);
    expect(await service.isPermissionWalkthroughSeen(), isTrue);
    final disk = await file.readAsString();
    expect(disk, isNot(contains('onboarding_intro_seen')));
    expect(disk, isNot(contains('permission_walkthrough_seen')));
  });
}

class _RecordingPermissionPlatform implements AppPermissionPlatform {
  final requested = <AppPermission>[];

  @override
  Future<bool> request(AppPermission permission) async {
    requested.add(permission);
    return true;
  }
}
