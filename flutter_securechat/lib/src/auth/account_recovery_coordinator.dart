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
  Future<void> completeLogin(
    RecoveryLoginApproval approval, {
    required bool acceptIdentityReplacement,
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
  });
  final String userId;
  final bool requiresIdentityReplacement;
  final String capability;
  final String identityPublicKey;
  final DateTime expiresAt;
  final String identityProtocol;
  final int? registrationId;
}
