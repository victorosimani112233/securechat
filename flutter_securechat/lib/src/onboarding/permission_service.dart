enum AppPermission { notifications, contacts, microphone, camera }

abstract interface class AppPermissionPlatform {
  Future<bool> request(AppPermission permission);

  /// Kullaniciya sormadan, zaten verilmis izinler.
  Future<Set<AppPermission>> granted();
}

class AppPermissionService {
  const AppPermissionService(this._platform);

  final AppPermissionPlatform _platform;

  Future<bool> request(AppPermission permission) =>
      _platform.request(permission);

  Future<Set<AppPermission>> granted() => _platform.granted();
}
