import 'dart:convert';
import 'dart:io';

// Requires ImageMagick only for regeneration; normal/offline builds use the
// committed PNG resources and do not need an image-processing dependency.
Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--check')) {
    throw ArgumentError(
      'Usage: dart tool/generate_launcher_icons.dart [--check]',
    );
  }
  final check = arguments.contains('--check');
  final root = File.fromUri(Platform.script).parent.parent;
  final temporary = await Directory.systemTemp.createTemp('elcim_icons_');
  const background = '#0D1024';
  var count = 0;
  Future<void> convert(List<String> args) async {
    final result = await Process.run('convert', args);
    if (result.exitCode != 0) {
      throw StateError('ImageMagick failed: ${result.stderr}');
    }
  }

  try {
    final logo = '${temporary.path}/logo.png';
    await convert([
      '${root.path}/assets/images/new_logo.png',
      '-trim',
      '+repage',
      '-strip',
      'PNG32:$logo',
    ]);
    Future<void> emit(
      String relative,
      int size, {
      bool adaptive = false,
    }) async {
      final output = '${temporary.path}/${count++}.png';
      final artworkSize = (size * (adaptive ? 2 / 3 : .92)).round();
      await convert([
        logo,
        '-resize',
        '${artworkSize}x$artworkSize',
        '-gravity',
        'center',
        '-background',
        adaptive ? 'none' : background,
        '-extent',
        '${size}x$size',
        if (!adaptive) ...['-alpha', 'remove', '-alpha', 'off'],
        '-strip',
        '-define',
        'png:exclude-chunk=date,time',
        '${adaptive ? 'PNG32' : 'PNG24'}:$output',
      ]);
      final target = File('${root.path}/$relative');
      final bytes = await File(output).readAsBytes();
      if (check) {
        if (!await target.exists() ||
            base64Encode(await target.readAsBytes()) != base64Encode(bytes)) {
          throw StateError('Launcher icon is stale: $relative');
        }
      } else {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes);
      }
    }

    for (final density in {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    }.entries) {
      final path = 'android/app/src/main/res/mipmap-${density.key}';
      await emit('$path/ic_launcher.png', (48 * density.value).round());
      await emit(
        '$path/ic_launcher_foreground.png',
        (108 * density.value).round(),
        adaptive: true,
      );
    }

    const catalog = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final manifest =
        jsonDecode(
              await File('${root.path}/$catalog/Contents.json').readAsString(),
            )
            as Map<String, dynamic>;
    final generated = <String>{};
    for (final icon in manifest['images'] as List<dynamic>) {
      final filename = icon['filename'] as String;
      if (!generated.add(filename)) continue;
      final dimensions = (icon['size'] as String).split('x');
      if (dimensions.first != dimensions.last) {
        throw StateError('App icons must be square');
      }
      final size = double.parse(dimensions.first);
      final scale = double.parse((icon['scale'] as String).replaceAll('x', ''));
      await emit('$catalog/$filename', (size * scale).round());
    }
    stdout.writeln(
      '${check ? 'Verified' : 'Generated'} $count launcher icons.',
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}
