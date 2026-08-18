import 'dart:convert';
import 'dart:io';

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<String> validateSwiftPackageLock(Object? decoded) {
  final root = _stringMap(decoded);
  if (root == null) return ['root must be a JSON object'];

  final failures = <String>[];
  final version = root['version'];
  if (version is! num || version <= 0 || version != version.round()) {
    failures.add('version must be a positive integer');
  }

  Object? pinsValue = root['pins'];
  final legacyObject = _stringMap(root['object']);
  pinsValue ??= legacyObject?['pins'];
  if (pinsValue is! List) {
    failures.add('pins must be a JSON array');
    return failures;
  }
  if (pinsValue.isEmpty) {
    failures.add('pins must contain at least one resolved package');
    return failures;
  }

  for (var index = 0; index < pinsValue.length; index++) {
    final pin = _stringMap(pinsValue[index]);
    if (pin == null) {
      failures.add('pins[$index] must be a JSON object');
      continue;
    }
    final identity = pin['identity'] ?? pin['package'];
    if (identity is! String || identity.trim().isEmpty) {
      failures.add('pins[$index] has no package identity');
    }
    final location = pin['location'] ?? pin['repositoryURL'];
    if (location is! String || location.trim().isEmpty) {
      failures.add('pins[$index] has no package location');
    }
    final state = _stringMap(pin['state']);
    if (state == null) {
      failures.add('pins[$index] has no resolution state');
      continue;
    }
    final revision = state['revision'];
    if (revision is! String || revision.trim().isEmpty) {
      failures.add('pins[$index] has no pinned revision');
    }
  }
  return failures;
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart tool/validate_swift_package_lock.dart <Package.resolved>',
    );
    exitCode = 2;
    return;
  }

  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('Swift package lock is missing: ${file.path}');
    exitCode = 2;
    return;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('Invalid Swift package lock JSON: $error');
    exitCode = 1;
    return;
  }

  final failures = validateSwiftPackageLock(decoded);
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('Invalid Swift package lock: $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Swift package lock: PASS (${file.path})');
}
