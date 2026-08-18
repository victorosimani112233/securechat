import 'dart:async';

import 'package:flutter/services.dart';

import 'call_models.dart';

enum NativeCallActionType { answer, end, mute, unmute, open }

class NativeCallAction {
  const NativeCallAction({required this.type, required this.callId});
  final NativeCallActionType type;
  final String callId;
}

abstract interface class NativeCallIntegration {
  Stream<NativeCallAction> get actions;
  Future<void> initialize();
  Future<void> reportIncoming(CallSession session);
  Future<void> reportOutgoing(CallSession session);
  Future<void> setActive(String callId);
  Future<void> end(String callId);
}

class MethodChannelNativeCallIntegration implements NativeCallIntegration {
  MethodChannelNativeCallIntegration({
    MethodChannel? channel,
    bool Function()? redactIdentity,
  }) : _channel = channel ?? const MethodChannel('com.securechat/native'),
       _redactIdentity = redactIdentity ?? _alwaysRedactIdentity {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final bool Function() _redactIdentity;
  final _actions = StreamController<NativeCallAction>.broadcast();
  bool _disposed = false;

  @override
  Stream<NativeCallAction> get actions => _actions.stream;

  @override
  Future<void> initialize() => _invoke('registerCallIntegration');

  @override
  Future<void> reportIncoming(CallSession session) => _invoke(
    'reportIncomingCall',
    nativeCallArguments(session, redactIdentity: _redactIdentity()),
  );

  @override
  Future<void> reportOutgoing(CallSession session) => _invoke(
    'reportOutgoingCall',
    nativeCallArguments(session, redactIdentity: _redactIdentity()),
  );

  @override
  Future<void> setActive(String callId) =>
      _invoke('setNativeCallActive', {'callId': callId});

  @override
  Future<void> end(String callId) =>
      _invoke('endNativeCall', {'callId': callId});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    await _channel.invokeMethod<void>(method, arguments);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
    if (call.method != 'nativeCallAction' || call.arguments is! Map) return;
    final values = Map<Object?, Object?>.from(call.arguments as Map);
    final callId = values['callId']?.toString();
    final action = values['action']?.toString().toLowerCase();
    if (callId == null || action == null) return;
    final type = switch (action) {
      'answer' => NativeCallActionType.answer,
      'end' => NativeCallActionType.end,
      'mute' => NativeCallActionType.mute,
      'unmute' => NativeCallActionType.unmute,
      'open' => NativeCallActionType.open,
      _ => null,
    };
    if (type != null)
      _actions.add(NativeCallAction(type: type, callId: callId));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _actions.close();
  }
}

bool _alwaysRedactIdentity() => true;

Map<String, Object?> nativeCallArguments(
  CallSession session, {
  required bool redactIdentity,
}) => {
  'callId': session.callId,
  'peerName': redactIdentity ? 'Elçim araması' : session.peerName,
  // A redacted call must not put an account identifier into an OS-owned
  // Telecom/CallKit payload. Dart routes all native actions by the opaque callId.
  'peerId': redactIdentity ? 'private' : session.peerId,
  'redactIdentity': redactIdentity,
  'hasVideo': session.callType == CallType.video,
};
