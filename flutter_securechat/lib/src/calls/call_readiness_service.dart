import '../platform/native_bridge.dart';

enum ReadinessStatus { granted, denied, notApplicable }

class CallReadinessState {
  const CallReadinessState({
    required this.battery,
    required this.fullScreenIntent,
    required this.notification,
    required this.overlay,
  });

  final ReadinessStatus battery;
  final ReadinessStatus fullScreenIntent;
  final ReadinessStatus notification;
  final ReadinessStatus overlay;

  bool get allGranted =>
      [battery, fullScreenIntent, notification, overlay].every(
        (status) =>
            status == ReadinessStatus.granted ||
            status == ReadinessStatus.notApplicable,
      );

  factory CallReadinessState.fromMap(Map<String, Object?> map) =>
      CallReadinessState(
        battery: _status(map['battery']),
        fullScreenIntent: _status(map['fullScreenIntent']),
        notification: _status(map['notification']),
        overlay: _status(map['overlay']),
      );
}

abstract interface class CallReadinessPlatform {
  Future<Map<String, Object?>> current();
  Future<bool> open(String kind);
}

class NativeCallReadinessPlatform implements CallReadinessPlatform {
  const NativeCallReadinessPlatform({
    NativeBridge bridge = const NativeBridge(),
  }) : _bridge = bridge;

  final NativeBridge _bridge;

  @override
  Future<Map<String, Object?>> current() => _bridge.getCallReadiness();

  @override
  Future<bool> open(String kind) => _bridge.openCallReadinessSetting(kind);
}

class CallReadinessService {
  const CallReadinessService({required CallReadinessPlatform platform})
    : _platform = platform;

  final CallReadinessPlatform _platform;

  Future<CallReadinessState> refresh() async =>
      CallReadinessState.fromMap(await _platform.current());

  Future<bool> openSetting(String kind) => _platform.open(kind);
}

class NotApplicableCallReadinessPlatform implements CallReadinessPlatform {
  const NotApplicableCallReadinessPlatform();

  @override
  Future<Map<String, Object?>> current() async => const {
    'battery': 'notApplicable',
    'fullScreenIntent': 'notApplicable',
    'notification': 'notApplicable',
    'overlay': 'notApplicable',
  };

  @override
  Future<bool> open(String kind) async => false;
}

ReadinessStatus _status(Object? value) => switch (value?.toString()) {
  'granted' => ReadinessStatus.granted,
  'notApplicable' => ReadinessStatus.notApplicable,
  _ => ReadinessStatus.denied,
};
