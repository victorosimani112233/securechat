import 'package:flutter_securechat/src/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug ADB transport requires all endpoints to be loopback', () {
    const loopback = AppConfig(
      apiBaseUrl: 'https://127.0.0.1:18443',
      signalingUrl: 'wss://127.0.0.1:18443',
      certificatePinHost: '127.0.0.1',
      certificatePins: ['primary', 'backup'],
    );
    const mixed = AppConfig(
      apiBaseUrl: 'https://127.0.0.1:18443',
      signalingUrl: 'wss://chat.example.invalid',
      certificatePinHost: '127.0.0.1',
      certificatePins: ['primary', 'backup'],
    );

    expect(loopback.allowsDebugLoopbackTransport, isTrue);
    expect(mixed.allowsDebugLoopbackTransport, isFalse);
  });
}
