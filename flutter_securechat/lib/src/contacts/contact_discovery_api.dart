class RegisteredUserMatch {
  const RegisteredUserMatch({required this.userId, required this.phoneHash});

  final String userId;
  final String phoneHash;
}

/// Private membership lookup boundary used by the contacts domain.
///
/// Implementations must not transmit [phoneHashes] directly. They are local
/// correlation handles only and may leave the device solely through a
/// privacy-preserving protocol such as the blind-RSA OPRF implementation.
abstract interface class ContactDiscoveryApi {
  Future<List<RegisteredUserMatch>> checkUsers(
    List<String> phoneHashes,
    String accessToken, {
    String? ownPhoneHash,
    String? ownUserId,
  });
}
