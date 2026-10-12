import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_securechat/src/media/media_vault.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-12 Bulgu 11: alinan dosyalar cihazda duz duruyordu.
void main() {
  late Directory root;
  late Directory media;
  late MediaVault vault;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media_vault_test_');
    media = Directory('${root.path}/media')..createSync();
    vault = MediaVault(keyBytes: List.filled(32, 7), mediaDirectory: media);
  });
  tearDown(() => root.delete(recursive: true));

  Uint8List bytes(int length) {
    final random = Random(length);
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  for (final size in [
    0,
    1,
    MediaVault.recordSize - 1,
    MediaVault.recordSize,
    MediaVault.recordSize + 1,
    3 * MediaVault.recordSize + 5,
  ]) {
    test('round trip keeps $size bytes and hides them on disk', () async {
      final plain = bytes(size);
      final source = File('${root.path}/plain.bin')..writeAsBytesSync(plain);
      final stored = File('${media.path}/received_files/x_photo.jpg');
      await stored.parent.create(recursive: true);

      await vault.sealFiles([source], stored);

      final sealed = stored.readAsBytesSync();
      expect(await MediaVault.isSealed(stored), isTrue);
      expect(MediaVault.plaintextLength(sealed.length), size);
      if (size >= 16) {
        expect(_contains(sealed, plain.sublist(0, 16)), isFalse);
      }
      final opened = await vault.openForUse(stored);
      expect(opened.path, startsWith(vault.openDirectory.path));
      expect(opened.uri.pathSegments.last, 'x_photo.jpg');
      expect(opened.readAsBytesSync(), plain);
    });
  }

  test('tampering, truncation and extension are rejected', () async {
    final plain = bytes(2 * MediaVault.recordSize + 10);
    final stored = File('${media.path}/a.bin');
    await vault.sealFiles([
      File('${root.path}/p')..writeAsBytesSync(plain),
    ], stored);
    final good = stored.readAsBytesSync();

    Future<void> expectRejected(List<int> variant) async {
      final file = File('${media.path}/variant.bin')..writeAsBytesSync(variant);
      await vault.discardOpened(file.path);
      await expectLater(vault.openForUse(file), throwsA(anything));
    }

    await expectRejected(List.of(good)..[MediaVault.headerLength + 3] ^= 1);
    await expectRejected(
      good.sublist(
        0,
        MediaVault.headerLength + MediaVault.recordSize + MediaVault.tagLength,
      ),
    );
    await expectRejected([...good, 1, 2, 3]);
    await expectRejected([...good.sublist(0, good.length - 1)]);
  });

  test('a different key cannot open the file', () async {
    final stored = File('${media.path}/a.bin');
    await vault.sealFiles([
      File('${root.path}/p')..writeAsBytesSync(bytes(100)),
    ], stored);
    final other = MediaVault(
      keyBytes: List.filled(32, 8),
      mediaDirectory: media,
    );
    await expectLater(other.openForUse(stored), throwsA(anything));
  });

  test('sealed transfer parts combine without plaintext on disk', () async {
    final first = bytes(MediaVault.recordSize + 3);
    final second = bytes(17);
    final partA = File('${root.path}/0.part')
      ..writeAsBytesSync(await vault.sealBytes(first));
    final partB = File('${root.path}/1.part')
      ..writeAsBytesSync(await vault.sealBytes(second));
    expect(await vault.openBytes(partA.readAsBytesSync()), first);
    expect(
      MediaVault.plaintextLength(partA.lengthSync()) +
          MediaVault.plaintextLength(partB.lengthSync()),
      first.length + second.length,
    );

    final target = File('${media.path}/received_files/joined.bin');
    await target.parent.create(recursive: true);
    await vault.sealSealedParts([partA, partB], target);

    final opened = await vault.openForUse(target);
    expect(opened.readAsBytesSync(), [...first, ...second]);
  });

  test('plain legacy files stay usable and are sealed in place once', () async {
    final legacy = File('${media.path}/sent/old.txt');
    await legacy.parent.create(recursive: true);
    legacy.writeAsStringSync('eski');
    expect((await vault.openForUse(legacy)).path, legacy.path);

    expect(await vault.sealExisting([Directory('${media.path}/sent')]), 1);
    expect(await vault.sealExisting([Directory('${media.path}/sent')]), 0);
    expect(await MediaVault.isSealed(legacy), isTrue);
    expect((await vault.openForUse(legacy)).readAsStringSync(), 'eski');
  });

  test('concurrent opens of one file share a single decryption', () async {
    final data = bytes(3 * MediaVault.recordSize);
    final stored = File('${media.path}/a.bin');
    await vault.sealFiles([
      File('${root.path}/p')..writeAsBytesSync(data),
    ], stored);
    final opened = await Future.wait([
      for (var i = 0; i < 5; i++) vault.openForUse(stored),
    ]);
    expect(opened.map((file) => file.path).toSet(), hasLength(1));
    expect(opened.first.readAsBytesSync(), data);
  });

  test('migration leaves an in-progress write alone', () async {
    final sent = Directory('${media.path}/sent')..createSync();
    final writing = File('${sent.path}/x.jpg.sealing')..writeAsStringSync('w');
    final stale = File('${sent.path}/y.jpg.sealing')..writeAsStringSync('s');
    stale.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 2)),
    );
    await vault.sealExisting([sent]);
    expect(writing.existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
  });

  test('opened copies are reused, discarded and purged', () async {
    final stored = File('${media.path}/a.bin');
    await vault.sealFiles([
      File('${root.path}/p')..writeAsBytesSync(bytes(10)),
    ], stored);
    final first = await vault.openForUse(stored);
    final second = await vault.openForUse(stored);
    expect(second.path, first.path);

    await vault.discardOpened(stored.path);
    expect(first.existsSync(), isFalse);

    await vault.openForUse(stored);
    await vault.purgeOpened(
      olderThan: const Duration(minutes: 10),
      now: DateTime.now(),
    );
    expect(vault.openDirectory.existsSync(), isTrue);
    await vault.purgeOpened(
      olderThan: const Duration(minutes: 10),
      now: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(vault.openDirectory.listSync(), isEmpty);
    await vault.purgeOpened();
    expect(vault.openDirectory.existsSync(), isFalse);
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
