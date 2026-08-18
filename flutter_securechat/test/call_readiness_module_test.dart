import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'readiness state accepts granted and not-applicable capabilities',
    () async {
      final platform = _FakePlatform({
        'battery': 'granted',
        'fullScreenIntent': 'notApplicable',
        'notification': 'granted',
        'overlay': 'notApplicable',
      });
      final state = await CallReadinessService(platform: platform).refresh();

      expect(state.battery, ReadinessStatus.granted);
      expect(state.fullScreenIntent, ReadinessStatus.notApplicable);
      expect(state.allGranted, isTrue);
    },
  );

  test('unknown or denied capability keeps readiness incomplete', () async {
    final platform = _FakePlatform({
      'battery': 'granted',
      'fullScreenIntent': 'unexpected',
      'notification': 'denied',
      'overlay': 'granted',
    });
    final state = await CallReadinessService(platform: platform).refresh();

    expect(state.fullScreenIntent, ReadinessStatus.denied);
    expect(state.notification, ReadinessStatus.denied);
    expect(state.allGranted, isFalse);
  });

  test('setting action is delegated to the native platform', () async {
    final platform = _FakePlatform(const {});
    final service = CallReadinessService(platform: platform);

    expect(await service.openSetting('battery'), isTrue);
    expect(platform.opened, ['battery']);
  });
}

class _FakePlatform implements CallReadinessPlatform {
  _FakePlatform(this.values);

  final Map<String, Object?> values;
  final opened = <String>[];

  @override
  Future<Map<String, Object?>> current() async => values;

  @override
  Future<bool> open(String kind) async {
    opened.add(kind);
    return true;
  }
}
