import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS catalog icons have correct dimensions and no transparency',
    () async {
      const root = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final catalog = jsonDecode(
        File('$root/Contents.json').readAsStringSync(),
      );
      for (final entry in catalog['images'] as List) {
        final points = double.parse((entry['size'] as String).split('x').first);
        final scale = double.parse(
          (entry['scale'] as String).replaceAll('x', ''),
        );
        await _checkImage(
          '$root/${entry['filename']}',
          (points * scale).round(),
          opaque: true,
        );
      }
    },
  );

  test('Android launcher icons cover all density buckets', () async {
    for (final entry in {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    }.entries) {
      final root = 'android/app/src/main/res/mipmap-${entry.key}';
      await _checkImage(
        '$root/ic_launcher.png',
        (48 * entry.value).round(),
        opaque: true,
      );
      await _checkImage(
        '$root/ic_launcher_foreground.png',
        (108 * entry.value).round(),
        opaque: false,
      );
    }
  });

  test('Android manifest and adaptive layer use the branded launcher', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));
  });
}

Future<void> _checkImage(String path, int size, {required bool opaque}) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  try {
    expect(frame.image.width, size, reason: path);
    expect(frame.image.height, size, reason: path);
    final pixels = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var transparent = 0;
    var visible = 0;
    for (var offset = 3; offset < pixels.lengthInBytes; offset += 4) {
      if (pixels.getUint8(offset) < 255) transparent++;
      if (pixels.getUint8(offset) > 0) visible++;
    }
    expect(visible, greaterThan(size * size ~/ 4), reason: path);
    expect(transparent, opaque ? 0 : greaterThan(0), reason: path);
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}
