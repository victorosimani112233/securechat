import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/config/legal_links.dart';
import 'package:flutter_securechat/src/platform/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/legal-links');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('https legal pages are handed to the native browser intent', () async {
    const bridge = NativeBridge(channel: channel);

    expect(await bridge.openExternalUrl(LegalLinks.privacy), isTrue);
    expect(calls.single.method, 'openExternalUrl');
    expect(calls.single.arguments, {'url': '${LegalLinks.base}/privacy'});
  });

  test('non-https urls never reach the platform', () async {
    const bridge = NativeBridge(channel: channel);

    expect(await bridge.openExternalUrl(Uri.parse('http://x.test')), isFalse);
    expect(await bridge.openExternalUrl(Uri.parse('file:///etc')), isFalse);
    expect(await bridge.openExternalUrl(Uri.parse('intent://x')), isFalse);
    expect(calls, isEmpty);
  });

  test('legal links point at the public site pages', () {
    expect(LegalLinks.privacy.scheme, 'https');
    expect(LegalLinks.terms.path, '/terms');
    expect(LegalLinks.childSafety.path, '/child-safety');
  });
}
