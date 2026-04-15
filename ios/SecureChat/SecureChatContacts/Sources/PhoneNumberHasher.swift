import Foundation
import CryptoKit

/// Gizlilik-preserving telefon numarası hash'leme servisi.
/// Telefon numaralarını SHA-256 ile hash'leyerek sunucuya gönderir,
/// plaintext numara ASLA sunucuya iletilmez.
public final class PhoneNumberHasher: @unchecked Sendable {

    // MARK: - Initialization

    public init() {}

    // MARK: - Phone Number Hashing

    /// Telefon numarasını SHA-256 ile hash'ler.
    /// - Parameter phoneNumber: E.164 formatında telefon numarası
    /// - Returns: 64 karakterlik hex string hash
    public func hashPhoneNumber(_ phoneNumber: String) -> String? {
        guard !phoneNumber.isEmpty else {
            return nil
        }

        let data = Data(phoneNumber.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Birden çok telefon numarasını toplu hash'ler
    /// - Parameter phoneNumbers: E.164 formatında telefon numaraları
    /// - Returns: Telefon numarası -> hash eşleşmesi
    public func hashPhoneNumbers(_ phoneNumbers: [String]) -> [String: String] {
        var hashMap: [String: String] = [:]

        for phoneNumber in phoneNumbers {
            if let hash = hashPhoneNumber(phoneNumber) {
                hashMap[phoneNumber] = hash
            }
        }

        return hashMap
    }

    /// Hash'leri toplu olarak oluşturur (performans için)
    /// - Parameter phoneNumbers: E.164 formatında telefon numaraları
    /// - Returns: Yalnızca hash'ler listesi
    public func createHashes(from phoneNumbers: [String]) -> [String] {
        return phoneNumbers.compactMap { hashPhoneNumber($0) }
    }

    // MARK: - Hash Validation

    /// Hash'in geçerli olup olmadığını kontrol eder
    /// - Parameter hash: Kontrol edilecek hash string
    /// - Returns: Geçerli hash mi (64 karakter hex)
    public func isValidHash(_ hash: String) -> Bool {
        // SHA-256 hash 64 karakter hex string olmalı
        guard hash.count == 64 else {
            return false
        }

        // Sadece hex karakterler içermeli (0-9, a-f)
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        return hash.lowercased().rangeOfCharacter(from: hexCharacterSet.inverted) == nil
    }

    // MARK: - Hash Mapping

    /// Hash'ler ile DeviceContact'ları eşleştirir
    /// - Parameters:
    ///   - contacts: Cihaz rehberinden okunan kişiler
    ///   - hasher: Phone number hasher instance
    /// - Returns: Hash -> DeviceContact mapping
    public func createHashMapping(from contacts: [DeviceContact]) -> [String: DeviceContact] {
        var mapping: [String: DeviceContact] = [:]

        for contact in contacts {
            if let hash = hashPhoneNumber(contact.phoneNumber) {
                mapping[hash] = contact
            }
        }

        return mapping
    }

    // MARK: - Security Utilities

    /// Hash collision kontrolü (test amaçlı)
    /// - Parameter hashes: Kontrol edilecek hash listesi
    /// - Returns: Çakışma var mı
    public func hasCollisions(in hashes: [String]) -> Bool {
        let uniqueHashes = Set(hashes)
        return uniqueHashes.count != hashes.count
    }

    /// İstatistik amaçlı hash dağılımını kontrol eder
    /// - Parameter hashes: Analiz edilecek hash'ler
    /// - Returns: Hash dağılım istatistiği
    public func analyzeHashDistribution(_ hashes: [String]) -> HashDistributionAnalysis {
        let uniqueHashes = Set(hashes)
        let collisions = hashes.count - uniqueHashes.count

        // İlk karaktere göre dağılım analizi
        var prefixDistribution: [Character: Int] = [:]
        for hash in hashes {
            if let firstChar = hash.first {
                prefixDistribution[firstChar, default: 0] += 1
            }
        }

        return HashDistributionAnalysis(
            totalHashes: hashes.count,
            uniqueHashes: uniqueHashes.count,
            collisions: collisions,
            prefixDistribution: prefixDistribution
        )
    }
}

// MARK: - Hash Distribution Analysis

/// Hash dağılım analizi sonucu (test ve debug amaçlı)
public struct HashDistributionAnalysis {
    public let totalHashes: Int
    public let uniqueHashes: Int
    public let collisions: Int
    public let prefixDistribution: [Character: Int]

    public var collisionRate: Double {
        guard totalHashes > 0 else { return 0.0 }
        return Double(collisions) / Double(totalHashes)
    }

    public var uniquenessRate: Double {
        guard totalHashes > 0 else { return 0.0 }
        return Double(uniqueHashes) / Double(totalHashes)
    }
}

// MARK: - Hashing Extensions

extension PhoneNumberHasher {

    /// Telefon numarası normalizasyonu ile birlikte hash'leme
    /// - Parameter rawPhoneNumber: Ham telefon numarası
    /// - Returns: Normalize edilmiş numaranın hash'i
    public func hashNormalizedPhoneNumber(_ rawPhoneNumber: String) -> String? {
        let normalizer = PhoneNumberNormalizer()
        guard let normalizedNumber = normalizer.normalizeToE164(rawPhoneNumber) else {
            return nil
        }
        return hashPhoneNumber(normalizedNumber)
    }

    /// Batch normalization ve hashing
    /// - Parameter rawPhoneNumbers: Ham telefon numaraları
    /// - Returns: Ham numara -> hash mapping (sadece başarılı normalize olanlar)
    public func hashNormalizedPhoneNumbers(_ rawPhoneNumbers: [String]) -> [String: String] {
        let normalizer = PhoneNumberNormalizer()
        var results: [String: String] = [:]

        for rawNumber in rawPhoneNumbers {
            if let normalizedNumber = normalizer.normalizeToE164(rawNumber),
               let hash = hashPhoneNumber(normalizedNumber) {
                results[rawNumber] = hash
            }
        }

        return results
    }
}