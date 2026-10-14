import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_securechat/src/background/background_run_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA 2026-10-14: ayni surecteki iki arka plan motoru ayni kuyrugu bosaltip
/// ayni mesaji iki kez cozmeye calisiyordu.
void main() {
  tearDown(
    () => IsolateNameServer.removePortNameMapping(BackgroundRunGuard.portName),
  );

  test('runs in one isolate never overlap', () async {
    final events = <String>[];
    Future<void> job(String name) async {
      await BackgroundRunGuard.run(() async {
        events.add('+$name');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('-$name');
      });
    }

    await Future.wait([job('a'), job('b'), job('c')]);
    expect(events, hasLength(6));
    for (var i = 0; i < events.length; i += 2) {
      expect(events[i][0], '+');
      expect(events[i + 1], '-${events[i].substring(1)}');
    }
    expect(
      IsolateNameServer.lookupPortByName(BackgroundRunGuard.portName),
      isNull,
    );
  });

  test('runs in separate isolates never overlap', () async {
    final dir = await Directory.systemTemp.createTemp('securechat_guard_');
    addTearDown(() => dir.delete(recursive: true));
    final journal = '${dir.path}/journal';

    Future<void> engine(String name) => Isolate.run(() async {
      for (var round = 0; round < 5; round++) {
        await BackgroundRunGuard.run(() async {
          final log = File(journal);
          await log.writeAsString('+$name\n', mode: FileMode.append);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await log.writeAsString('-$name\n', mode: FileMode.append);
        });
      }
    });

    await Future.wait([engine('a'), engine('b')]);
    final lines = await File(journal).readAsLines();
    expect(lines, hasLength(20));
    for (var i = 0; i < lines.length; i += 2) {
      expect(lines[i][0], '+');
      expect(lines[i + 1], '-${lines[i].substring(1)}');
    }
  });

  test('an owner that no longer answers is taken over', () async {
    // Coken bir motorun birakmadigi kayit: port var ama kimse yanitlamiyor.
    final dead = ReceivePort();
    addTearDown(dead.close);
    expect(
      IsolateNameServer.registerPortWithName(
        dead.sendPort,
        BackgroundRunGuard.portName,
      ),
      isTrue,
    );

    final ran = await BackgroundRunGuard.run(
      () async => true,
      probe: const Duration(milliseconds: 100),
    );
    expect(ran, isTrue);
  });

  test('a live owner keeps others out until the wait runs out', () async {
    final release = Completer<void>();
    final owner = BackgroundRunGuard.run(() => release.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    var ran = false;
    final result = await BackgroundRunGuard.run(
      () async => ran = true,
      wait: const Duration(milliseconds: 300),
    );
    expect(result, isNull);
    expect(ran, isFalse);

    release.complete();
    await owner;
    expect(await BackgroundRunGuard.run(() async => 'next'), 'next');
  });
}
