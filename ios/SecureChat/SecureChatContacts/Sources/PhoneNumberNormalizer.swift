import Foundation

/// Telefon numarası normalizasyon servisi.
/// Çeşitli formatlardaki telefon numaralarını E.164 formatına dönüştürür.
/// libphonenumber bağımlılığı olmadan çalışan hafif bir yardımcıdır.
public final class PhoneNumberNormalizer: @unchecked Sendable {

    // MARK: - Properties

    /// Varsayılan ülke kodu (Türkiye)
    private let defaultCountryCode: String

    // MARK: - Initialization

    public init(defaultCountryCode: String = "90") {
        self.defaultCountryCode = defaultCountryCode
    }

    // MARK: - Normalization

    /// Kullanıcının girdiği telefon numarasını E.164 formatına normalize eder.
    /// - Parameter input: Ham telefon numarası
    /// - Returns: E.164 formatında telefon numarası (örn: "+905551234567")
    public func normalizeToE164(_ input: String) -> String? {
        // Boş string kontrolü
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Tüm özel karakterleri kaldır (+, boşluk, tire, parantez)
        let digits = input.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        guard !digits.isEmpty else {
            return nil
        }

        let normalizedDigits = normalizeDigits(digits)
        guard isValidPhoneNumber(normalizedDigits) else {
            return nil
        }

        // E.164 formatında döner (+90 ile başlar)
        return "+\(normalizedDigits)"
    }

    /// Kullanıcı girişindeki telefon numarasını userId formatına normalize eder (+ işareti olmadan).
    /// - Parameter input: Ham telefon numarası
    /// - Returns: Yalnızca rakamlardan oluşan normalize edilmiş numara (örn: "905551234567")
    public func normalizeToUserId(_ input: String) -> String? {
        guard let e164 = normalizeToE164(input) else {
            return nil
        }
        // + işaretini kaldır
        return String(e164.dropFirst())
    }

    /// Telefon numarasını gösterim formatına çevirir.
    /// - Parameter userId: Normalize edilmiş userId (yalnızca rakam)
    /// - Returns: Okunabilir telefon numarası formatı
    public func formatForDisplay(_ userId: String) -> String {
        // Türkiye numarası: 90XXXXXXXXXX (12 hane)
        if userId.count == 12 && userId.hasPrefix("90") {
            let areaCode = String(userId[userId.index(userId.startIndex, offsetBy: 2)..<userId.index(userId.startIndex, offsetBy: 5)])
            let part1 = String(userId[userId.index(userId.startIndex, offsetBy: 5)..<userId.index(userId.startIndex, offsetBy: 8)])
            let part2 = String(userId[userId.index(userId.startIndex, offsetBy: 8)..<userId.index(userId.startIndex, offsetBy: 10)])
            let part3 = String(userId[userId.index(userId.startIndex, offsetBy: 10)..<userId.index(userId.startIndex, offsetBy: 12)])
            return "+90 \(areaCode) \(part1) \(part2) \(part3)"
        }
        // Diğer formatlar: başına + ekle
        return "+\(userId)"
    }

    // MARK: - Batch Operations

    /// Birden çok telefon numarasını toplu normalize eder
    /// - Parameter phoneNumbers: Ham telefon numaraları
    /// - Returns: Başarılı normalize edilenler
    public func normalizeToE164Batch(_ phoneNumbers: [String]) -> [String] {
        return phoneNumbers.compactMap { normalizeToE164($0) }
    }

    /// Telefon numarası ve normalize edilmiş halini eşleştirir
    /// - Parameter phoneNumbers: Ham telefon numaraları
    /// - Returns: Ham numara -> E.164 mapping
    public func createNormalizationMapping(_ phoneNumbers: [String]) -> [String: String] {
        var mapping: [String: String] = [:]
        for rawNumber in phoneNumbers {
            if let normalized = normalizeToE164(rawNumber) {
                mapping[rawNumber] = normalized
            }
        }
        return mapping
    }

    // MARK: - Private Methods

    /// Rakamları normalize eder (ülke kodunu ekler)
    private func normalizeDigits(_ digits: String) -> String {
        switch (digits.count, digits.hasPrefix("0"), digits.hasPrefix("90"), digits.hasPrefix("5")) {
        case (11, true, _, _):
            // "05551234567" -> "905551234567" (başındaki 0'ı atla, 90 ön eki ekle)
            return defaultCountryCode + String(digits.dropFirst())

        case (10, _, _, true):
            // "5551234567" -> "905551234567" (Türk cep numarası: 5 ile başlar, 10 hane)
            return defaultCountryCode + digits

        case (12, _, true, _):
            // Zaten "905551234567" formatında
            return digits

        default:
            // Diğer durumlar için olduğu gibi döner (uluslararası formatlar)
            return digits
        }
    }

    /// Telefon numarasının geçerli olup olmadığını kontrol eder
    private func isValidPhoneNumber(_ digits: String) -> Bool {
        // Minimum 7, maksimum 15 hane
        guard digits.count >= 7 && digits.count <= 15 else {
            return false
        }

        // Sadece rakam içermeli
        guard digits.allSatisfy({ $0.isNumber }) else {
            return false
        }

        // Türkiye numarası kontrolü
        if digits.count == 12 && digits.hasPrefix("90") {
            let mobilePrefix = String(digits.prefix(5))
            // Türk cep numarası 905XX ile başlamalı (50X-55X, 56X)
            let validPrefixes = ["90500", "90501", "90502", "90503", "90504", "90505", "90506", "90507", "90508", "90509",
                                "90530", "90531", "90532", "90533", "90534", "90535", "90536", "90537", "90538", "90539",
                                "90540", "90541", "90542", "90543", "90544", "90545", "90546", "90547", "90548", "90549",
                                "90550", "90551", "90552", "90553", "90554", "90555", "90556", "90557", "90558", "90559",
                                "90560", "90561", "90562", "90563", "90564", "90565", "90566", "90567", "90568", "90569"]
            return validPrefixes.contains(mobilePrefix)
        }

        return true // Diğer ülke kodları için temel kontrol
    }

    // MARK: - Validation

    /// E.164 formatında telefon numarasının geçerli olup olmadığını kontrol eder
    public func isValidE164(_ phoneNumber: String) -> Bool {
        guard phoneNumber.hasPrefix("+") else {
            return false
        }

        let digits = String(phoneNumber.dropFirst())
        return isValidPhoneNumber(digits)
    }

    /// Türk cep numarası olup olmadığını kontrol eder
    public func isTurkishMobile(_ phoneNumber: String) -> Bool {
        let clean = phoneNumber.replacingOccurrences(of: "+", with: "")
        return clean.count == 12 && clean.hasPrefix("905") && isValidPhoneNumber(clean)
    }

    // MARK: - Country Code Detection

    /// Telefon numarasından ülke kodunu çıkarır
    public func extractCountryCode(_ phoneNumber: String) -> String? {
        guard let normalized = normalizeToE164(phoneNumber) else {
            return nil
        }

        let digits = String(normalized.dropFirst()) // + işaretini kaldır

        // Türkiye
        if digits.hasPrefix("90") {
            return "90"
        }

        // ABD/Kanada
        if digits.hasPrefix("1") {
            return "1"
        }

        // Almanya
        if digits.hasPrefix("49") {
            return "49"
        }

        // İngiltere
        if digits.hasPrefix("44") {
            return "44"
        }

        // Fransa
        if digits.hasPrefix("33") {
            return "33"
        }

        // Diğer ülke kodları için basit heuristik
        // 1-3 haneli ülke kodları mümkün
        for length in 1...3 {
            if digits.count > length {
                let potentialCode = String(digits.prefix(length))
                if isValidCountryCode(potentialCode) {
                    return potentialCode
                }
            }
        }

        return nil
    }

    private func isValidCountryCode(_ code: String) -> Bool {
        // ITU-T E.164 standardına göre geçerli ülke kodları
        let validCodes = ["1", "33", "44", "49", "90", "86", "81", "91", "55", "52", "61", "39", "34", "31", "46", "47", "41", "43", "32", "30"]
        return validCodes.contains(code)
    }
}