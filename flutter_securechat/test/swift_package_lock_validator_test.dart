import 'package:flutter_test/flutter_test.dart';

import '../tool/validate_swift_package_lock.dart';

void main() {
  test('accepts current SwiftPM resolved format', () {
    final failures = validateSwiftPackageLock({
      'originHash': 'fixture',
      'pins': [
        {
          'identity': 'firebase-ios-sdk',
          'kind': 'remoteSourceControl',
          'location': 'https://github.com/firebase/firebase-ios-sdk',
          'state': {'revision': '0123456789abcdef', 'version': '12.17.0'},
        },
      ],
      'version': 3,
    });

    expect(failures, isEmpty);
  });

  test('accepts legacy SwiftPM resolved format', () {
    final failures = validateSwiftPackageLock({
      'object': {
        'pins': [
          {
            'package': 'Firebase',
            'repositoryURL': 'https://github.com/firebase/firebase-ios-sdk',
            'state': {'revision': '0123456789abcdef', 'version': '10.0.0'},
          },
        ],
      },
      'version': 1,
    });

    expect(failures, isEmpty);
  });

  test('rejects an unpinned or malformed package graph', () {
    final failures = validateSwiftPackageLock({
      'pins': [
        {
          'identity': 'firebase-ios-sdk',
          'location': 'https://github.com/firebase/firebase-ios-sdk',
          'state': {'version': '12.17.0'},
        },
      ],
      'version': 3,
    });

    expect(failures, contains('pins[0] has no pinned revision'));
    expect(validateSwiftPackageLock('{"version":3}'), isNotEmpty);
  });
}
