import 'dart:async';

typedef AsyncResourceDisposer = FutureOr<void> Function();

class ResourceCleanupFailure {
  const ResourceCleanupFailure({
    required this.resourceName,
    required this.error,
    required this.stackTrace,
  });

  final String resourceName;
  final Object error;
  final StackTrace stackTrace;
}

/// Owns long-lived production resources created by the composition root.
///
/// Resources are released in reverse registration order so dependants stop
/// before the lower-level socket, database, and HTTP clients they use. Cleanup
/// is idempotent and best-effort: one failing disposer never prevents the
/// remaining resources from being released.
class AppResourceScope {
  final List<_OwnedResource> _resources = [];
  final List<ResourceCleanupFailure> _failures = [];
  Future<void>? _disposeTask;
  bool _acceptingResources = true;

  List<ResourceCleanupFailure> get cleanupFailures =>
      List.unmodifiable(_failures);

  bool get isDisposed => _disposeTask != null;

  T own<T>(String name, T resource, AsyncResourceDisposer disposer) {
    register(name, disposer);
    return resource;
  }

  void register(String name, AsyncResourceDisposer disposer) {
    if (!_acceptingResources) {
      throw StateError('Cannot register $name after resource disposal began');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Resource name is required');
    }
    _resources.add(_OwnedResource(name, disposer));
  }

  Future<void> dispose() {
    final active = _disposeTask;
    if (active != null) return active;
    _acceptingResources = false;
    final operation = _disposeAll();
    _disposeTask = operation;
    return operation;
  }

  Future<void> _disposeAll() async {
    for (final resource in _resources.reversed) {
      try {
        await resource.dispose();
      } catch (error, stackTrace) {
        _failures.add(
          ResourceCleanupFailure(
            resourceName: resource.name,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    _resources.clear();
  }
}

class _OwnedResource {
  const _OwnedResource(this.name, this.dispose);

  final String name;
  final AsyncResourceDisposer dispose;
}
