import 'package:flutter_securechat/src/services/app_resource_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resources close once in reverse dependency order', () async {
    final events = <String>[];
    final scope = AppResourceScope()
      ..register('http', () => events.add('http'))
      ..register('database', () async => events.add('database'))
      ..register('socket', () => events.add('socket'));

    final first = scope.dispose();
    final second = scope.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(events, ['socket', 'database', 'http']);
    expect(scope.isDisposed, isTrue);
    expect(scope.cleanupFailures, isEmpty);
  });

  test(
    'cleanup continues after a disposer fails and records evidence',
    () async {
      final events = <String>[];
      final scope = AppResourceScope()
        ..register('first', () => events.add('first'))
        ..register('broken', () => throw StateError('cleanup failed'))
        ..register('last', () => events.add('last'));

      await scope.dispose();

      expect(events, ['last', 'first']);
      expect(scope.cleanupFailures, hasLength(1));
      expect(scope.cleanupFailures.single.resourceName, 'broken');
      expect(scope.cleanupFailures.single.error, isA<StateError>());
      expect(() => scope.register('too-late', () {}), throwsStateError);
    },
  );
}
