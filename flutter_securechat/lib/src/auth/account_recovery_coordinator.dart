/// UI contract for recovery. Implementations must preserve a pending completion
/// across process restarts before publishing replacement identity keys.
abstract class AccountRecoveryCoordinator {
  Future<bool> getEnrollmentStatus();
  Future<RecoveryChallenge> requestEnrollment(String email);
  Future<void> verifyEnrollment(RecoveryChallenge challenge, String code);
  Future<RecoveryChallenge> requestLogin(String email);
  Future<RecoveryLoginApproval> verifyLogin(
    RecoveryChallenge challenge,
    String code,
  );

  /// Kayit kilidi acik hesapta yeni cihaza tasima [registrationLockPin]
  /// ister ([RecoveryLoginApproval.requiresRegistrationLock]).
  Future<void> completeLogin(
    RecoveryLoginApproval approval, {
    required bool acceptIdentityReplacement,
    String? registrationLockPin,
  });
  Future<bool> hasPendingLogin();
  Future<bool> resumePendingLogin();
  Future<void> restartPendingLogin();
}

class RecoveryChallenge {
  const RecoveryChallenge({
    required this.id,
    required this.email,
    required this.expiresAt,
    this.userId,
    this.nonce,
    this.credentialEpoch,
    this.identityProtocol = 'v1',
  });
  final String id;
  final String email;
  final DateTime expiresAt;
  final String? userId;
  final String? nonce;
  final String? credentialEpoch;
  final String identityProtocol;
}

class RecoveryLoginApproval {
  const RecoveryLoginApproval({
    required this.userId,
    required this.requiresIdentityReplacement,
    required this.capability,
    required this.identityPublicKey,
    required this.expiresAt,
    this.identityProtocol = 'v1',
    this.registrationId,
    this.requiresRegistrationLock = false,
  });
  final String userId;
  final bool requiresIdentityReplacement;
  final String capability;
  final String identityPublicKey;
  final DateTime expiresAt;
  final String identityProtocol;
  final int? registrationId;

  /// Hesapta kayit kilidi acik; yeni cihaza tasima PIN ister.
  final bool requiresRegistrationLock;
}

/// Kayit kilidi PIN'ini acip kapatan oturum islemleri.
abstract class RegistrationLockSettings {
  Future<bool> registrationLockEnabled();
  Future<void> enableRegistrationLock(String pin);
  Future<void> disableRegistrationLock();
}
