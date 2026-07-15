import XCTest
@testable import CloverPDF

final class LocalizationTests: XCTestCase {
    func testAllCatalogEntriesHaveSixTranslations() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repository.appendingPathComponent("CloverPDF/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let required = Set(["en", "zh-Hans", "ko", "ja", "de", "ru"])
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], "Invalid entry for \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "Missing localizations for \(key)")
            XCTAssertTrue(required.isSubset(of: Set(localizations.keys)), "Missing localization for \(key)")
        }
    }
}
