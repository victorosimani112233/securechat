enum AppPermission { notifications, contacts, microphone, camera }

abstract interface class AppPermissionPlatform {
  Future<bool> request(AppPermission permission);
}

class AppPermissionService {
  const AppPermissionService(this._platform);

  final AppPermissionPlatform _platform;

  Future<bool> request(AppPermission permission) =>
      _platform.request(permission);
}
