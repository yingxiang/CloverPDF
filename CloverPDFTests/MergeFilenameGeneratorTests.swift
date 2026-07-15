import XCTest
@testable import CloverPDF

final class MergeFilenameGeneratorTests: XCTestCase {
    func testFilenameUsesMinuteTimestamp() throws {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 7,
            day: 15,
            hour: 16,
            minute: 24
        )
        let date = try XCTUnwrap(components.date)

        let filename = MergeFilenameGenerator.filename(at: date, timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertEqual(filename, "202607151624.pdf")
    }
}
