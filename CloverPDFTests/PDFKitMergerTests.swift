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
            outputURL: directory.appendingPathComponent("merged.pdf"),
            outputFormat: .pdf
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
            outputURL: outputURL,
            outputFormat: .pdf
        )

        let result = try await PDFKitMerger().merge(request)

        XCTAssertEqual(result, outputURL)
        XCTAssertEqual(PDFDocument(url: outputURL)?.pageCount, 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".cloverpdf-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testMergeCanWriteOneLongPNG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makePDF(pageCount: 2, name: "first", directory: directory)
        let second = try makePDF(pageCount: 1, name: "second", directory: directory)
        let inspector = PDFInspector()
        let outputURL = directory.appendingPathComponent("merged.png")
        let request = MergeRequest(
            inputs: [
                PDFInput(source: try inspector.inspect(url: first), password: nil),
                PDFInput(source: try inspector.inspect(url: second), password: nil),
            ],
            outputURL: outputURL,
            outputFormat: .image(.png)
        )

        let output = try await PDFKitMerger().merge(request)
        let image = try XCTUnwrap(NSImage(contentsOf: output))
        let representation = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        XCTAssertEqual(output.pathExtension, "png")
        XCTAssertGreaterThan(representation.pixelsHigh, representation.pixelsWide * 2)
        XCTAssertTrue(containsNonWhitePixel(representation))
    }

    func testBatchImageExportWritesOneLongImagePerPDFUsingOriginalName() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let sourceURL = try makePDF(pageCount: 3, name: "source", directory: directory)
        let source = try PDFInspector().inspect(url: sourceURL)
        let request = BatchImageRequest(
            inputs: [PDFInput(source: source, password: nil)],
            outputDirectory: outputDirectory,
            imageFormat: .jpeg
        )

        let output = try await PDFImageExporter().export(request)
        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)

        XCTAssertEqual(files.map(\.lastPathComponent), ["source.jpg"])
        let firstImage = try XCTUnwrap(NSImage(contentsOf: files[0]))
        let firstRepresentation = try XCTUnwrap(
            firstImage.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )
        XCTAssertGreaterThan(firstRepresentation.pixelsHigh, firstRepresentation.pixelsWide * 2)
        XCTAssertTrue(containsNonWhitePixel(firstRepresentation))
    }

    func testImageExportPreservesVerticalOrientation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = try makeOrientationPDF(name: "orientation", directory: directory)
        let source = try PDFInspector().inspect(url: sourceURL)
        let outputURL = directory.appendingPathComponent("orientation.png")
        let request = MergeRequest(
            inputs: [PDFInput(source: source, password: nil)],
            outputURL: outputURL,
            outputFormat: .image(.png)
        )

        _ = try await PDFKitMerger().merge(request)
        let image = try XCTUnwrap(NSImage(contentsOf: outputURL))
        let representation = try bitmapRepresentation(of: image)
        let document = try XCTUnwrap(PDFDocument(url: sourceURL))
        let page = try XCTUnwrap(document.page(at: 0))
        let reference = try bitmapRepresentation(of: page.thumbnail(of: NSSize(width: 400, height: 400), for: .mediaBox))
        let top = try sampleColor(in: representation, verticalFraction: 0.75)
        let bottom = try sampleColor(in: representation, verticalFraction: 0.25)
        let referenceTop = try sampleColor(in: reference, verticalFraction: 0.75)
        let referenceBottom = try sampleColor(in: reference, verticalFraction: 0.25)

        XCTAssertEqual(top.redComponent > top.blueComponent, referenceTop.redComponent > referenceTop.blueComponent)
        XCTAssertEqual(
            bottom.redComponent > bottom.blueComponent,
            referenceBottom.redComponent > referenceBottom.blueComponent
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func containsNonWhitePixel(_ representation: NSBitmapImageRep) -> Bool {
        guard let data = representation.bitmapData else { return false }
        let byteCount = representation.bytesPerRow * representation.pixelsHigh
        guard byteCount >= 4 else { return false }
        for index in stride(from: 0, to: byteCount - 3, by: 4) {
            if data[index] < 240 || data[index + 1] < 240 || data[index + 2] < 240 {
                return true
            }
        }
        return false
    }

    private func bitmapRepresentation(of image: NSImage) throws -> NSBitmapImageRep {
        if let representation = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return representation
        }
        return try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    }

    private func sampleColor(
        in representation: NSBitmapImageRep,
        verticalFraction: Double
    ) throws -> NSColor {
        let x = representation.pixelsWide / 2
        let y = Int(Double(representation.pixelsHigh) * verticalFraction)
        return try XCTUnwrap(representation.colorAt(x: x, y: y))
            .usingColorSpace(.deviceRGB) ?? .clear
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

    private func makeOrientationPDF(name: String, directory: URL) throws -> URL {
        let size = NSSize(width: 200, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height / 2).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2).fill()
        image.unlockFocus()
        guard let page = PDFPage(image: image) else { throw CloverPDFError.outputFailed }
        let document = PDFDocument()
        document.insert(page, at: 0)
        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        guard document.write(to: url) else { throw CloverPDFError.outputFailed }
        return url
    }
}

final class TaskQueueActorTests: XCTestCase {
    func testDeletingRunningTaskCancelsOperationAndRemovesPersistedRecord() async throws {
        let repository = TestTaskRepository()
        let probe = CancellationProbe()
        let queue = TaskQueueActor(
            merger: TestMerger(),
            imageExporter: TestImageExporter(),
            converter: BlockingConverter(probe: probe),
            repository: repository,
            trialStore: TestTrialStore()
        )
        let source = PDFSource(
            displayName: "source.pdf",
            path: "/tmp/source.pdf",
            bookmark: nil,
            pageCount: 1,
            fileSize: 1,
            isLocked: false,
            appearsScanned: false
        )
        let request = ConversionRequest(
            input: PDFInput(source: source, password: nil),
            outputDirectory: FileManager.default.temporaryDirectory,
            pageRange: nil
        )

        try await queue.enqueueConversions([request], premiumUnlocked: true)
        try await waitUntil { await probe.hasStarted }
        let queuedTasks = await queue.snapshot()
        let taskID = try XCTUnwrap(queuedTasks.first?.id)
        await queue.delete(taskID)
        try await waitUntil { await repository.records.isEmpty }

        let wasCancelled = await probe.wasCancelled
        let remainingTasks = await queue.snapshot()
        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(remainingTasks.isEmpty)
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous state")
    }
}

private actor TestTaskRepository: TaskRepository {
    private(set) var records: [ProcessingTaskRecord] = []

    func load() async throws -> [ProcessingTaskRecord] { records }
    func save(_ tasks: [ProcessingTaskRecord]) async throws { records = tasks }
}

private actor CancellationProbe {
    private(set) var hasStarted = false
    private(set) var wasCancelled = false

    func markStarted() { hasStarted = true }
    func markCancelled() { wasCancelled = true }
}

private struct BlockingConverter: PDFConverting {
    let probe: CancellationProbe

    func convert(
        _ request: ConversionRequest,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL {
        await probe.markStarted()
        do {
            try await Task.sleep(for: .seconds(30))
            return request.outputDirectory.appendingPathComponent("output.docx")
        } catch {
            await probe.markCancelled()
            throw error
        }
    }
}

private struct TestMerger: PDFMerging {
    func merge(_ request: MergeRequest) async throws -> URL { request.outputURL }
}

private struct TestImageExporter: PDFImageExporting {
    func export(_ request: BatchImageRequest) async throws -> URL { request.outputDirectory }
}

private struct TestTrialStore: TrialQuotaStoring {
    func remainingConversions() -> Int { 3 }
    func consumeSuccessfulConversion() throws {}
}
