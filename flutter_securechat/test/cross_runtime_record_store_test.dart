import 'dart:io';

import 'package:flutter_securechat/src/storage/encrypted_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late EncryptedRecordStore first;
  late EncryptedRecordStore second;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cross_runtime_records_');
    final file = File('${root.path}/records');
    final key = List.filled(32, 32);
    first = await EncryptedRecordStore.open(file: file, key: key);
    second = await EncryptedRecordStore.open(file: file, key: key);
  });
  tearDown(() async {
    first.close();
    second.close();
    await root.delete(recursive: true);
  });

  void write(EncryptedRecordStore store, int value) => store.applyChanges(
    upserts: {
      'conversations': {
        'c': {'unread': value},
      },
      'messages': {
        'm': {'revision': value},
      },
    },
    deletions: const {},
  );

  test(
    'data_version is connection-local and changes only on external commits',
    () {
      final initial = first.dataVersion;
      write(first, 1);
      expect(first.dataVersion, initial);
      final secondVersion = second.dataVersion;
      write(second, 2);
      expect(second.dataVersion, secondVersion);
      expect(first.dataVersion, isNot(initial));
    },
  );

  test(
    'all collections and version are pinned despite a mid-read external commit',
    () {
      write(first, 1);
      late int version;
      first.readTransaction(() {
        version = first.dataVersion;
        expect(first.loadCollection('conversations')['c']!['unread'], 1);
        write(second, 2);
        expect(first.loadCollection('messages')['m']!['revision'], 1);
        expect(first.dataVersion, version);
      });
      expect(first.dataVersion, isNot(version));
      expect(first.loadCollection('messages')['m']!['revision'], 2);
    },
  );

  test('nested applyChanges cannot commit an outer transaction', () {
    write(first, 1);
    final version = second.dataVersion;
    expect(
      () => first.writeTransaction(() {
        write(first, 2);
        expect(second.loadCollection('messages')['m']!['revision'], 1);
        throw StateError('outer rollback');
      }),
      throwsStateError,
    );
    expect(first.loadCollection('messages')['m']!['revision'], 1);
    expect(second.dataVersion, version);
    first.writeTransaction(() => write(first, 3));
    expect(second.loadCollection('messages')['m']!['revision'], 3);
  });

  test(
    'failed nested clear rolls back its savepoint, outer writer remains usable',
    () {
      write(first, 1);
      first.writeTransaction(() {
        first.failMidTransaction = true;
        expect(
          () => first.applyChanges(
            upserts: const {},
            deletions: const {},
            clearFirst: true,
          ),
          throwsStateError,
        );
        expect(first.loadCollection('messages')['m']!['revision'], 1);
        write(first, 2);
      });
      expect(second.loadCollection('messages')['m']!['revision'], 2);
    },
  );
}
