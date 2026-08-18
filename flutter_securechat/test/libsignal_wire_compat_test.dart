import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

void main() {
  late _LegacyJavaBridge java;

  setUpAll(() async {
    java = await _LegacyJavaBridge.compile();
  });

  tearDownAll(() async {
    await java.close();
  });

  test(
    'Dart PreKey message and Java 2.8.1 ratchet reply interoperate',
    () async {
      final aliceIdentity = signal.generateIdentityKeyPair();
      final aliceStore = signal.InMemorySignalProtocolStore(
        aliceIdentity,
        signal.generateRegistrationId(false),
      );
      final bobIdentity = signal.generateIdentityKeyPair();
      final bobRegistration = signal.generateRegistrationId(false);
      final bobPreKey = signal.generatePreKeys(0, 1).single;
      final bobSignedPreKey = signal.generateSignedPreKey(bobIdentity, 0);
      final bobBundle = signal.PreKeyBundle(
        bobRegistration,
        1,
        bobPreKey.id,
        bobPreKey.getKeyPair().publicKey,
        bobSignedPreKey.id,
        bobSignedPreKey.getKeyPair().publicKey,
        bobSignedPreKey.signature,
        bobIdentity.getPublicKey(),
      );
      const bobAddress = signal.SignalProtocolAddress('java-client', 1);
      await signal.SessionBuilder.fromSignalStore(
        aliceStore,
        bobAddress,
      ).processPreKeyBundle(bobBundle);
      final aliceCipher = signal.SessionCipher.fromStore(
        aliceStore,
        bobAddress,
      );
      final first = await aliceCipher.encrypt(
        Uint8List.fromList(utf8.encode('dart-prekey-message')),
      );
      expect(first.getType(), signal.CiphertextMessage.prekeyType);

      final result = await java.run([
        'direct',
        base64Encode(bobIdentity.serialize()),
        '$bobRegistration',
        '${bobPreKey.id}',
        base64Encode(bobPreKey.serialize()),
        '${bobSignedPreKey.id}',
        base64Encode(bobSignedPreKey.serialize()),
        base64Encode(first.serialize()),
        'java-ratchet-reply',
      ]);
      expect(utf8.decode(base64Decode(result[0])), 'dart-prekey-message');
      expect(int.parse(result[1]), signal.CiphertextMessage.whisperType);
      final reply = await aliceCipher.decryptFromSignal(
        signal.SignalMessage.fromSerialized(base64Decode(result[2])),
      );
      expect(utf8.decode(reply), 'java-ratchet-reply');
    },
  );

  test(
    'Dart and Java 2.8.1 SenderKey messages interoperate both ways',
    () async {
      final dartStore = signal.InMemorySenderKeyStore();
      const dartName = signal.SenderKeyName(
        'compat-group',
        signal.SignalProtocolAddress('dart-client', 1),
      );
      final distribution = await signal.GroupSessionBuilder(
        dartStore,
      ).create(dartName);
      final ciphertext = await signal.GroupCipher(
        dartStore,
        dartName,
      ).encrypt(Uint8List.fromList(utf8.encode('dart-group-message')));

      final result = await java.run([
        'group',
        base64Encode(distribution.serialize()),
        base64Encode(ciphertext),
      ]);
      expect(utf8.decode(base64Decode(result[0])), 'dart-group-message');

      final javaStore = signal.InMemorySenderKeyStore();
      const javaName = signal.SenderKeyName(
        'compat-group',
        signal.SignalProtocolAddress('java-client', 1),
      );
      await signal.GroupSessionBuilder(javaStore).process(
        javaName,
        signal.SenderKeyDistributionMessageWrapper.fromSerialized(
          base64Decode(result[1]),
        ),
      );
      final reply = await signal.GroupCipher(
        javaStore,
        javaName,
      ).decrypt(base64Decode(result[2]));
      expect(utf8.decode(reply), 'java-group-reply');
    },
  );
}

class _LegacyJavaBridge {
  _LegacyJavaBridge(this._directory, this._classPath);

  final Directory _directory;
  final String _classPath;

  static Future<_LegacyJavaBridge> compile() async {
    final home = Platform.environment['HOME'];
    if (home == null) throw StateError('HOME is required for Gradle cache');
    final signalJar = _singleJar(
      '$home/.gradle/caches/modules-2/files-2.1/'
          'org.whispersystems/signal-protocol-java/2.8.1',
      'signal-protocol-java-2.8.1.jar',
    );
    final curveJar = _singleJar(
      '$home/.gradle/caches/modules-2/files-2.1/'
          'org.whispersystems/curve25519-java/0.5.0',
      'curve25519-java-0.5.0.jar',
    );
    final protobufJar = _singleJar(
      '$home/.gradle/caches/modules-2/files-2.1/'
          'com.google.protobuf/protobuf-javalite/3.10.0',
      'protobuf-javalite-3.10.0.jar',
    );
    final directory = await Directory.systemTemp.createTemp(
      'securechat_libsignal_java_',
    );
    final classPath = [
      signalJar,
      curveJar,
      protobufJar,
    ].join(Platform.isWindows ? ';' : ':');
    final source = File('tool/libsignal_compat/LegacySignalInterop.java');
    final compile = await Process.run('javac', [
      '-cp',
      classPath,
      '-d',
      directory.path,
      source.absolute.path,
    ]);
    if (compile.exitCode != 0) {
      await directory.delete(recursive: true);
      throw StateError('Legacy Java bridge compile failed: ${compile.stderr}');
    }
    return _LegacyJavaBridge(directory, classPath);
  }

  Future<List<String>> run(List<String> arguments) async {
    final separator = Platform.isWindows ? ';' : ':';
    final result = await Process.run('java', [
      '-cp',
      '${_directory.path}$separator$_classPath',
      'LegacySignalInterop',
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Legacy Java bridge failed: ${result.stderr}');
    }
    return LineSplitter.split(
      result.stdout as String,
    ).where((line) => line.trim().isNotEmpty).toList(growable: false);
  }

  Future<void> close() => _directory.delete(recursive: true);
}

String _singleJar(String directory, String name) {
  final matches = Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith(name))
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected one $name under $directory, found ${matches.length}',
    );
  }
  return matches.single.path;
}
