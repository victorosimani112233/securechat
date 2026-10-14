import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-14: bir APK guncellemesinden sonra gelen arama push'u uygulamayi
/// soguk baslatti; ayni surecte iki arka plan motoru (iki isolate) ayni anda
/// token yeniledi ve oturumu ayni `.tmp` dosyasi uzerinden yazdi. Biri
/// digerinin dosyasini silip yeniden adlandirmayi kacirinca
/// `session.securejson` hic kalmadi; on plan acilisi bos oturumla kayit
/// ekranina dustu ve hesap cihazda kayboldu.
void main() {
  LocalAeadCryptoService crypto() =>
      LocalAeadCryptoService(SecretKey(List<int>.generate(32, (i) => i + 7)));

  Future<PersistentSessionStore> loggedIn(File file, String access) async {
    final store = await PersistentSessionStore.open(
      file: file,
      crypto: crypto(),
    );
    store.login(
      userId: 'user-1',
      displayName: 'A',
      phoneNumber: '+900000000000',
      accessToken: access,
      refreshToken: 'refresh-$access',
    );
    return store;
  }

  test('concurrent writers never leave the session file missing', () async {
    final dir = await Directory.systemTemp.createTemp('securechat_session_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/session.securejson');
    final first = await loggedIn(file, 'access-a');
    final second = await loggedIn(file, 'access-b');

    for (var round = 0; round < 200; round++) {
      await Future.wait([first.persist(), second.persist()]);
      expect(await file.exists(), isTrue, reason: 'round $round');
    }
    final reopened = await PersistentSessionStore.open(
      file: file,
      crypto: crypto(),
    );
    expect(reopened.userId, 'user-1');
    expect(reopened.isLoggedIn, isTrue);
    await first.close();
    await second.close();
    await reopened.close();
  });

  test('writers in separate isolates keep a readable session', () async {
    final dir = await Directory.systemTemp.createTemp('securechat_session_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/session.securejson';

    Future<void> writer(String access) => Isolate.run(() async {
      final store = await loggedIn(File(path), access);
      for (var round = 0; round < 100; round++) {
        await store.persist();
      }
      await store.close();
    });

    await Future.wait([writer('access-a'), writer('access-b')]);
    final reopened = await PersistentSessionStore.open(
      file: File(path),
      crypto: crypto(),
    );
    expect(reopened.userId, 'user-1');
    expect(reopened.accessToken, anyOf('access-a', 'access-b'));
    await reopened.close();
  });

  test('refreshes in separate isolates never overlap', () async {
    final dir = await Directory.systemTemp.createTemp('securechat_session_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/session.securejson';
    final journal = '${dir.path}/journal';
    await (await loggedIn(File(path), 'access-0')).persist();

    Future<void> refresher(String name) => Isolate.run(() async {
      final store = await PersistentSessionStore.open(
        file: File(path),
        crypto: crypto(),
      );
      for (var round = 0; round < 10; round++) {
        await store.withRefreshLock(() async {
          final log = File(journal);
          await log.writeAsString('+$name\n', mode: FileMode.append);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await log.writeAsString('-$name\n', mode: FileMode.append);
        });
      }
      await store.close();
    });

    await Future.wait([refresher('a'), refresher('b')]);
    final lines = await File(journal).readAsLines();
    expect(lines, hasLength(40));
    // Kilit altinda her giris kendi cikisiyla hemen kapanir.
    for (var i = 0; i < lines.length; i += 2) {
      expect(lines[i].substring(1), lines[i + 1].substring(1));
      expect(lines[i][0], '+');
      expect(lines[i + 1][0], '-');
    }
    expect(await File('$path.refresh.owner').exists(), isFalse);
  });

  test(
    'a failing refresh action runs once and still releases the lock',
    () async {
      final dir = await Directory.systemTemp.createTemp('securechat_session_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/session.securejson');
      final store = await loggedIn(file, 'access-a');
      var runs = 0;
      await expectLater(
        store.withRefreshLock<void>(() async {
          runs++;
          throw const FileSystemException('persist failed');
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(runs, 1);
      expect(await File('${file.path}.refresh.owner').exists(), isFalse);
      await store.withRefreshLock(() async => runs++);
      expect(runs, 2);
      await store.close();
    },
  );
}
