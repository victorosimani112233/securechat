import '../storage/secure_chat_database.dart';

class OnboardingService {
  const OnboardingService(this._database);
  static const _introKey = 'onboarding_intro_seen_v1';
  static const _permissionsKey = 'permission_walkthrough_seen_v1';
  final SecureChatDatabase _database;

  Future<bool> isIntroSeen() async =>
      await _database.cryptoState.get(_introKey) == 'true';
  Future<bool> isPermissionWalkthroughSeen() async =>
      await _database.cryptoState.get(_permissionsKey) == 'true';
  Future<void> markIntroSeen() => _database.cryptoState.put(_introKey, 'true');
  Future<void> markPermissionWalkthroughSeen() =>
      _database.cryptoState.put(_permissionsKey, 'true');
}
