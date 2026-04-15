import Foundation

/// Uzak kimlik güven seviyesi.
public enum TrustLevel: String, CaseIterable, Codable {
    case untrusted = "UNTRUSTED"
    case trustedUnverified = "TRUSTED_UNVERIFIED"
    case trustedVerified = "TRUSTED_VERIFIED"
}