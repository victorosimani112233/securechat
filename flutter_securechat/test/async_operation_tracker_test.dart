import 'dart:async';

import 'package:flutter_securechat/src/services/async_operation_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('close waits for owned work and contains reported failures', () async {
    final gate = Completer<void>();
    final failures = <String>[];
    final tracker = AsyncOperationTracker(
      onFailure: (operation, error, stackTrace) {
        failures.add('$operation:$error');
      },
    );
    tracker.run('slow', gate.future);
    tracker.run('broken', Future<void>.error(StateError('boom')));

    var closed = false;
    final first = tracker.close().then((_) => closed = true);
    expect(closed, isFalse);
    gate.complete();
    await first;
    await tracker.close();

    expect(closed, isTrue);
    expect(failures.single, contains('broken:Bad state: boom'));
    expect(
      () => tracker.run('too-late', Future<void>.value()),
      throwsStateError,
    );
  });
}
