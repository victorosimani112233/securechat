import XCTest
@testable import SecureChatContacts

final class PhoneNumberNormalizerTests: XCTestCase {

    var normalizer: PhoneNumberNormalizer!

    override func setUp() {
        super.setUp()
        normalizer = PhoneNumberNormalizer()
    }

    override func tearDown() {
        normalizer = nil
        super.tearDown()
    }

    // MARK: - E.164 Normalization Tests

    func testNormalizeToE164_TurkishMobileWithCountryCode() {
        // "+90 555 123 45 67" -> "+905551234567"
        let input = "+90 555 123 45 67"
        let expected = "+905551234567"

        let result = normalizer.normalizeToE164(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToE164_TurkishMobileWithoutCountryCode() {
        // "0555 123 45 67" -> "+905551234567"
        let input = "0555 123 45 67"
        let expected = "+905551234567"

        let result = normalizer.normalizeToE164(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToE164_TurkishMobileShortFormat() {
        // "555 123 45 67" -> "+905551234567"
        let input = "555 123 45 67"
        let expected = "+905551234567"

        let result = normalizer.normalizeToE164(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToE164_WithParenthesesAndSpaces() {
        // "(0555) 123-45-67" -> "+905551234567"
        let input = "(0555) 123-45-67"
        let expected = "+905551234567"

        let result = normalizer.normalizeToE164(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToE164_InternationalFormat() {
        // "+1 555 123 4567" (US number) -> "+15551234567"
        let normalizer = PhoneNumberNormalizer(defaultCountryCode: "1")
        let input = "+1 555 123 4567"
        let expected = "+15551234567"

        let result = normalizer.normalizeToE164(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToE164_EmptyString() {
        let input = ""

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result)
    }

    func testNormalizeToE164_OnlySpaces() {
        let input = "   "

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result)
    }

    func testNormalizeToE164_NoDigits() {
        let input = "abc def"

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result)
    }

    // MARK: - UserID Normalization Tests

    func testNormalizeToUserId_TurkishMobile() {
        let input = "+90 555 123 45 67"
        let expected = "905551234567"

        let result = normalizer.normalizeToUserId(input)

        XCTAssertEqual(result, expected)
    }

    func testNormalizeToUserId_RemovesPlusSign() {
        let input = "+15551234567"
        let expected = "15551234567"

        let result = normalizer.normalizeToUserId(input)

        XCTAssertEqual(result, expected)
    }

    // MARK: - Display Format Tests

    func testFormatForDisplay_TurkishMobile() {
        let input = "905551234567"
        let expected = "+90 555 123 45 67"

        let result = normalizer.formatForDisplay(input)

        XCTAssertEqual(result, expected)
    }

    func testFormatForDisplay_NonTurkishMobile() {
        let input = "15551234567"
        let expected = "+15551234567"

        let result = normalizer.formatForDisplay(input)

        XCTAssertEqual(result, expected)
    }

    func testFormatForDisplay_EmptyString() {
        let input = ""
        let expected = "+"

        let result = normalizer.formatForDisplay(input)

        XCTAssertEqual(result, expected)
    }

    // MARK: - Batch Operations Tests

    func testNormalizeToE164Batch() {
        let inputs = [
            "+90 555 123 45 67",
            "0555 987 65 43",
            "invalid number",
            "+1 555 123 4567"
        ]
        let normalizer = PhoneNumberNormalizer()

        let results = normalizer.normalizeToE164Batch(inputs)

        XCTAssertEqual(results.count, 3) // 1 invalid should be filtered out
        XCTAssertTrue(results.contains("+905551234567"))
        XCTAssertTrue(results.contains("+905559876543"))
        XCTAssertTrue(results.contains("+15551234567"))
    }

    func testCreateNormalizationMapping() {
        let inputs = [
            "+90 555 123 45 67",
            "0555 987 65 43",
            "invalid number"
        ]

        let mapping = normalizer.createNormalizationMapping(inputs)

        XCTAssertEqual(mapping.count, 2) // 1 invalid should be filtered out
        XCTAssertEqual(mapping["+90 555 123 45 67"], "+905551234567")
        XCTAssertEqual(mapping["0555 987 65 43"], "+905559876543")
        XCTAssertNil(mapping["invalid number"])
    }

    // MARK: - Validation Tests

    func testIsValidE164() {
        XCTAssertTrue(normalizer.isValidE164("+905551234567"))
        XCTAssertTrue(normalizer.isValidE164("+15551234567"))

        XCTAssertFalse(normalizer.isValidE164("905551234567")) // No plus
        XCTAssertFalse(normalizer.isValidE164("+")) // Only plus
        XCTAssertFalse(normalizer.isValidE164(""))
        XCTAssertFalse(normalizer.isValidE164("+abc"))
    }

    func testIsTurkishMobile() {
        XCTAssertTrue(normalizer.isTurkishMobile("+905551234567"))
        XCTAssertTrue(normalizer.isTurkishMobile("905551234567"))

        XCTAssertFalse(normalizer.isTurkishMobile("+15551234567"))
        XCTAssertFalse(normalizer.isTurkishMobile("+905321234567")) // Invalid prefix
        XCTAssertFalse(normalizer.isTurkishMobile(""))
    }

    // MARK: - Country Code Detection Tests

    func testExtractCountryCode() {
        XCTAssertEqual(normalizer.extractCountryCode("+905551234567"), "90")
        XCTAssertEqual(normalizer.extractCountryCode("+15551234567"), "1")
        XCTAssertEqual(normalizer.extractCountryCode("+4915551234567"), "49")
        XCTAssertEqual(normalizer.extractCountryCode("+441234567890"), "44")

        XCTAssertNil(normalizer.extractCountryCode("invalid"))
        XCTAssertNil(normalizer.extractCountryCode(""))
    }

    // MARK: - Edge Cases Tests

    func testNormalizeToE164_VeryLongNumber() {
        let input = "90555123456789012345"

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result) // Should be rejected as too long
    }

    func testNormalizeToE164_VeryShortNumber() {
        let input = "123"

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result) // Should be rejected as too short
    }

    func testNormalizeToE164_LeadingZeros() {
        let input = "0000555123456"

        let result = normalizer.normalizeToE164(input)

        XCTAssertNil(result) // Should handle leading zeros gracefully
    }

    // MARK: - Performance Tests

    func testPerformanceBatchNormalization() {
        let inputs = Array(repeating: "+90 555 123 45 67", count: 1000)

        measure {
            _ = normalizer.normalizeToE164Batch(inputs)
        }
    }

    func testPerformanceCreateMapping() {
        let inputs = Array(repeating: "+90 555 123 45 67", count: 1000)

        measure {
            _ = normalizer.createNormalizationMapping(inputs)
        }
    }
}