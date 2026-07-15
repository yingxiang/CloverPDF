import AppKit
import PDFKit
import XCTest
@testable import CloverPDF

final class PDFKitMergerTests: XCTestCase {
    func testMergePreservesTotalPageCount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makePDF(pageCount: 2, name: "first", directory: directory)
        let second = try makePDF(pageCount: 1, name: "second", directory: directory)
        let inspector = PDFInspector()
        let request = MergeRequest(
            inputs: [
                PDFInput(source: try inspector.inspect(url: first), password: nil),
                PDFInput(source: try inspector.inspect(url: second), password: nil),
            ],
            outputURL: directory.appendingPathComponent("merged.pdf")
        )

        let output = try await PDFKitMerger().merge(request)

        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 3)
    }

    func testMergeReplacesConfirmedOutputAndRemovesTemporaryFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = try makePDF(pageCount: 2, name: "source", directory: directory)
        let outputURL = try makePDF(pageCount: 1, name: "selected-output", directory: directory)
        let source = try PDFInspector().inspect(url: sourceURL)
        let request = MergeRequest(
            inputs: [PDFInput(source: source, password: nil)],
            outputURL: outputURL
        )

        let result = try await PDFKitMerger().merge(request)

        XCTAssertEqual(result, outputURL)
        XCTAssertEqual(PDFDocument(url: outputURL)?.pageCount, 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".cloverpdf-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    private func makePDF(pageCount: Int, name: String, directory: URL) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 200, height: 200))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSString(string: "Page \(index + 1)").draw(at: NSPoint(x: 20, y: 100))
            image.unlockFocus()
            guard let page = PDFPage(image: image) else { throw CloverPDFError.outputFailed }
            document.insert(page, at: index)
        }
        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        guard document.write(to: url) else { throw CloverPDFError.outputFailed }
        return url
    }
}
