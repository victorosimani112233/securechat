import 'package:crypto/crypto.dart';

/// UI-facing identity review contract; the crypto engine owns approval locking.
abstract interface class PeerIdentityReviewService {
  Future<PeerIdentityReview> reviewPeerIdentity(String peerId);
  Future<void> approvePeerIdentity(PeerIdentityReview review);
}

/// Immutable public-key snapshot. Fingerprints are always derived from the
/// same bytes approval checks; callers cannot substitute display labels.
class PeerIdentityReview {
  PeerIdentityReview({
    required this.peerId,
    required List<int>? previousIdentity,
    required List<int> currentIdentity,
    required List<int> localIdentity,
  }) : previousIdentity = previousIdentity == null
           ? null
           : List<int>.unmodifiable(previousIdentity),
       currentIdentity = List<int>.unmodifiable(currentIdentity),
       localIdentity = List<int>.unmodifiable(localIdentity);

  final String peerId;
  final List<int>? previousIdentity;
  final List<int> currentIdentity;
  final List<int> localIdentity;

  bool get identityChanged =>
      !identityBytesEqual(previousIdentity, currentIdentity);

  String? get previousFingerprint =>
      previousIdentity == null ? null : safetyFingerprint(previousIdentity!);
  String get currentFingerprint => safetyFingerprint(currentIdentity);
  String get localFingerprint => safetyFingerprint(localIdentity);

  /// SHA-256 of the complete Signal serialized public key (including type).
  /// This is a key fingerprint, not Signal's pairwise numeric safety number.
  static String safetyFingerprint(List<int> bytes) {
    final hex = sha256.convert(bytes).toString().toUpperCase();
    return [
      for (var offset = 0; offset < hex.length; offset += 4)
        hex.substring(offset, offset + 4),
    ].join(' ');
  }
}

class PeerIdentityReviewStaleException implements Exception {
  const PeerIdentityReviewStaleException();
}

bool identityBytesEqual(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
