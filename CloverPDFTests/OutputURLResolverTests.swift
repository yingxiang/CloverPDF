import XCTest
@testable import CloverPDF

final class OutputURLResolverTests: XCTestCase {
    func testAvailableURLAddsNumericSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("Report.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path, contents: Data()))

        let result = OutputURLResolver.availableURL(
            directory: directory,
            baseName: "Report",
            extension: "pdf"
        )

        XCTAssertEqual(result.lastPathComponent, "Report (1).pdf")
    }
}
