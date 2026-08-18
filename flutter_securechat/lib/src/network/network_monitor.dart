import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../storage/storage_management_service.dart';

enum NetworkTransport {
  none,
  wifi,
  cellular,
  ethernet,
  vpn,
  bluetooth,
  satellite,
  other,
}

class NetworkSnapshot {
  NetworkSnapshot(Iterable<NetworkTransport> transports)
    : transports = Set.unmodifiable(transports);

  const NetworkSnapshot.disconnected()
    : transports = const {NetworkTransport.none};

  final Set<NetworkTransport> transports;

  bool get isAvailable =>
      transports.isNotEmpty && !transports.contains(NetworkTransport.none);

  NetworkKind get kind {
    if (transports.contains(NetworkTransport.wifi)) return NetworkKind.wifi;
    if (transports.contains(NetworkTransport.cellular)) {
      return NetworkKind.cellular;
    }
    return NetworkKind.other;
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkSnapshot &&
      transports.length == other.transports.length &&
      transports.containsAll(other.transports);

  @override
  int get hashCode => Object.hashAllUnordered(transports);
}

abstract interface class ConnectivityGateway {
  Future<List<NetworkTransport>> checkConnectivity();
  Stream<List<NetworkTransport>> get connectivityChanges;
}

class PluginConnectivityGateway implements ConnectivityGateway {
  PluginConnectivityGateway({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<NetworkTransport>> checkConnectivity() async =>
      (await _connectivity.checkConnectivity()).map(_map).toList();

  @override
  Stream<List<NetworkTransport>> get connectivityChanges => _connectivity
      .onConnectivityChanged
      .map((results) => results.map(_map).toList());

  static NetworkTransport _map(ConnectivityResult result) => switch (result) {
    ConnectivityResult.none => NetworkTransport.none,
    ConnectivityResult.wifi => NetworkTransport.wifi,
    ConnectivityResult.mobile => NetworkTransport.cellular,
    ConnectivityResult.ethernet => NetworkTransport.ethernet,
    ConnectivityResult.vpn => NetworkTransport.vpn,
    ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
    ConnectivityResult.satellite => NetworkTransport.satellite,
    ConnectivityResult.other => NetworkTransport.other,
  };
}

abstract interface class NetworkStatusMonitor implements NetworkKindProvider {
  NetworkSnapshot get current;
  Stream<NetworkSnapshot> get changes;
  Future<NetworkSnapshot> start();
  Future<void> stop();
  Future<void> dispose();
}

class SystemNetworkMonitor implements NetworkStatusMonitor {
  SystemNetworkMonitor({ConnectivityGateway? gateway})
    : _gateway = gateway ?? PluginConnectivityGateway();

  final ConnectivityGateway _gateway;
  final _changes = StreamController<NetworkSnapshot>.broadcast();
  StreamSubscription<List<NetworkTransport>>? _subscription;
  NetworkSnapshot _current = const NetworkSnapshot.disconnected();
  bool _disposed = false;

  @override
  NetworkSnapshot get current => _current;

  @override
  NetworkKind get currentNetworkKind => _current.kind;

  @override
  Stream<NetworkSnapshot> get changes => _changes.stream;

  @override
  Future<NetworkSnapshot> start() async {
    if (_disposed) throw StateError('Network monitor is disposed');
    if (_subscription != null) return _current;
    _subscription = _gateway.connectivityChanges.listen(_publish);
    _publish(await _gateway.checkConnectivity());
    return _current;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _changes.close();
  }

  void _publish(List<NetworkTransport> transports) {
    if (_disposed) return;
    final normalized = transports.isEmpty
        ? const NetworkSnapshot.disconnected()
        : NetworkSnapshot(transports);
    if (normalized == _current) return;
    _current = normalized;
    _changes.add(normalized);
  }
}
