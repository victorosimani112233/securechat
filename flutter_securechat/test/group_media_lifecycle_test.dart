import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/media/call_media_key.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real group engine disposes call key provider and creates a fresh ring',
    () async {
      final calls = <MethodCall>[];
      var providers = 0;
      const channel = MethodChannel('FlutterWebRTC.Method');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'frameCryptorFactoryCreateKeyProvider') {
              return {'keyProviderId': 'provider-${++providers}'};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final engine = WebRtcGroupMediaEngine();
      addTearDown(engine.dispose);
      await engine.enableMediaEncryption(
        CallMediaKey.generate(callId: 'first'),
      );
      expect(engine.mediaEncryptionEnabled, isTrue);
      await engine.close();
      expect(engine.mediaEncryptionEnabled, isFalse);
      expect(
        calls.where((c) => c.method == 'keyProviderDispose'),
        hasLength(1),
      );
      await engine.enableMediaEncryption(
        CallMediaKey.generate(callId: 'second'),
      );
      expect(providers, 2);
      final creates = calls.where(
        (c) => c.method == 'frameCryptorFactoryCreateKeyProvider',
      );
      final options = creates.last.arguments['keyProviderOptions'] as Map;
      expect(options['discardFrameWhenCryptorNotReady'], isTrue);
      expect(options['keyRingSize'], CallMediaKey.keyRingSize);
    },
  );
}
