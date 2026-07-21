import AppKit
import PDFKit
import XCTest
@testable import CloverPDF

final class PDFKitMergerTests: XCTestCase {
    func testSecurityScopedBookmarkPreservesChineseDirectoryPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("请款单", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let sourceURL = try makePDF(pageCount: 1, name: "20250210", directory: directory)

        let source = try PDFInspector().inspect(url: sourceURL)
        let resolvedURL = try BookmarkService.resolve(source)

        XCTAssertEqual(source.path, sourceURL.standardizedFileURL.path(percentEncoded: false))
        XCTAssertEqual(resolvedURL.path(percentEncoded: false), source.path)
    }

    @MainActor
    func testThumbnailContainerDoesNotExpandToLoadedImageSize() {
        let view = PDFThumbnailContainerView()

        XCTAssertEqual(view.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

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
            imageFormat: .jpeg,
            pageIndicesBySource: [:]
        )

        let files = try await PDFImageExporter().export(request)

        XCTAssertEqual(files.map(\.lastPathComponent), ["source.jpg"])
        XCTAssertEqual(files.first?.deletingLastPathComponent(), outputDirectory)
        let firstImage = try XCTUnwrap(NSImage(contentsOf: files[0]))
        let firstRepresentation = try XCTUnwrap(
            firstImage.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )
        XCTAssertGreaterThan(firstRepresentation.pixelsHigh, firstRepresentation.pixelsWide * 2)
        XCTAssertTrue(containsNonWhitePixel(firstRepresentation))
    }

    func testEveryBatchOutputProducesANonBlackRasterThumbnail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let inspector = PDFInspector()
        let inputs = try (1...3).map { index in
            let url = try makePDF(pageCount: index, name: "source-\(index)", directory: directory)
            return PDFInput(source: try inspector.inspect(url: url), password: nil)
        }
        let request = BatchImageRequest(
            inputs: inputs,
            outputDirectory: outputDirectory,
            imageFormat: .png,
            pageIndicesBySource: [:]
        )

        let outputs = try await PDFImageExporter().export(request)

        XCTAssertEqual(outputs.count, 3)
        for output in outputs {
            let image = await RasterThumbnailLoader.load(fileURL: output)
            let thumbnail = try XCTUnwrap(image)
            let representation = try bitmapRepresentation(of: thumbnail)
            XCTAssertTrue(containsLightPixel(representation), "Black thumbnail for \(output.lastPathComponent)")
        }
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

    private func containsLightPixel(_ representation: NSBitmapImageRep) -> Bool {
        guard let data = representation.bitmapData else { return false }
        let byteCount = representation.bytesPerRow * representation.pixelsHigh
        guard byteCount >= 4 else { return false }
        for index in stride(from: 0, to: byteCount - 3, by: 4) {
            if data[index] > 80 || data[index + 1] > 80 || data[index + 2] > 80 {
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
    @MainActor
    func testPurchaseServiceRecognizesTestProcess() {
        let isRunningTests = PurchaseService.isRunningTests
        XCTAssertTrue(isRunningTests)
    }

    func testCompanionTrialUsesOneThreeDayPeriodForEitherOrBothApps() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mapleStart = try XCTUnwrap(WPDFPromotionTrialPolicy.startDate(
            storedStartDate: nil,
            isCloverInstalled: false,
            isMapleInstalled: true,
            now: now
        ))
        let later = now.addingTimeInterval(24 * 60 * 60)
        let bothInstalledStart = try XCTUnwrap(WPDFPromotionTrialPolicy.startDate(
            storedStartDate: mapleStart,
            isCloverInstalled: true,
            isMapleInstalled: true,
            now: later
        ))

        XCTAssertEqual(bothInstalledStart, mapleStart)
        XCTAssertEqual(
            WPDFPromotionTrialPolicy.state(startDate: bothInstalledStart).expirationDate,
            mapleStart.addingTimeInterval(3 * 24 * 60 * 60)
        )
    }

    func testCompanionTrialDoesNotStartWithoutEitherApp() {
        XCTAssertNil(WPDFPromotionTrialPolicy.startDate(
            storedStartDate: nil,
            isCloverInstalled: false,
            isMapleInstalled: false,
            now: Date()
        ))
    }

    func testCompanionTrialRequiresAClaimedAppToRemainInstalled() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let duringTrial = start.addingTimeInterval(24 * 60 * 60)

        XCTAssertTrue(WPDFPromotionTrialPolicy.isEntitled(
            storedStartDate: start,
            hasClaimedInstalledApp: true,
            now: duringTrial
        ))
        XCTAssertFalse(WPDFPromotionTrialPolicy.isEntitled(
            storedStartDate: start,
            hasClaimedInstalledApp: false,
            now: duringTrial
        ))
        XCTAssertFalse(WPDFPromotionTrialPolicy.isEntitled(
            storedStartDate: start,
            hasClaimedInstalledApp: true,
            now: start.addingTimeInterval(3 * 24 * 60 * 60)
        ))
    }

    func testCompanionCatalogExcludesTheHostApplication() {
        XCTAssertEqual(
            MacPaywallCompanionCatalog.apps(excluding: "com.lingchen.pdf").map(\.bundleIdentifier),
            ["com.lingchen.clover", "com.lingchen.omnicapture"]
        )
        XCTAssertEqual(
            MacPaywallCompanionCatalog.apps(excluding: "com.lingchen.clover").map(\.bundleIdentifier),
            ["com.lingchen.omnicapture"]
        )
        XCTAssertEqual(
            MacPaywallCompanionCatalog.apps(excluding: "com.lingchen.omnicapture").map(\.bundleIdentifier),
            ["com.lingchen.clover"]
        )
    }

    func testWorkspacePDFSelectsEveryPageByDefault() {
        let source = PDFSource(
            displayName: "source.pdf",
            path: "/tmp/source.pdf",
            bookmark: nil,
            pageCount: 3,
            fileSize: 1,
            isLocked: false,
            appearsScanned: false
        )

        XCTAssertEqual(WorkspacePDF(source: source).selectedPageIndices, [0, 1, 2])
    }

    func testDeletingSelectedTasksCancelsRunningOperationAndRemovesAllRecords() async throws {
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
            pageIndices: [0]
        )

        try await queue.enqueueConversions([request, request], premiumUnlocked: true)
        try await waitUntil { await probe.hasStarted }
        let queuedTasks = await queue.snapshot()
        XCTAssertEqual(queuedTasks.count, 2)
        XCTAssertTrue(queuedTasks.allSatisfy { $0.conversionPageIndices == [0] })
        XCTAssertTrue(queuedTasks.allSatisfy { $0.inputPageCount == 1 })
        await queue.delete(Set(queuedTasks.map(\.id)))
        try await waitUntil { await repository.records.isEmpty }

        let wasCancelled = await probe.wasCancelled
        let remainingTasks = await queue.snapshot()
        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(remainingTasks.isEmpty)
    }

    func testBatchConversionCreatesOneTaskPerInputUnderTheSameTimestamp() async throws {
        let repository = TestTaskRepository()
        let queue = TaskQueueActor(
            merger: TestMerger(),
            imageExporter: TestImageExporter(),
            converter: BlockingConverter(probe: CancellationProbe()),
            repository: repository,
            trialStore: TestTrialStore()
        )
        let inputs = ["first.pdf", "second.pdf"].enumerated().map { index, name in
            PDFInput(source: PDFSource(
                displayName: name,
                path: "/tmp/\(name)",
                bookmark: nil,
                pageCount: index + 1,
                fileSize: Int64((index + 1) * 1_000),
                isLocked: false,
                appearsScanned: false
            ), password: nil)
        }
        let request = BatchImageRequest(
            inputs: inputs,
            outputDirectory: URL(fileURLWithPath: "/tmp/output"),
            imageFormat: .png,
            pageIndicesBySource: [:]
        )

        let taskIDs = await queue.enqueueBatchImages(request)
        XCTAssertEqual(taskIDs.count, 2)
        try await waitUntil {
            let tasks = await queue.snapshot().filter { taskIDs.contains($0.id) }
            return tasks.count == 2 && tasks.allSatisfy { $0.state == .succeeded }
        }

        let tasks = await queue.snapshot().filter { taskIDs.contains($0.id) }
        XCTAssertEqual(Set(tasks.map(\.createdAt)).count, 1)
        XCTAssertEqual(tasks.map(\.inputPaths), [["/tmp/first.pdf"], ["/tmp/second.pdf"]])
        XCTAssertEqual(tasks.map(\.inputPageCount), [1, 2])
        XCTAssertEqual(tasks.map(\.inputFileSize), [1_000, 2_000])
        XCTAssertTrue(tasks.allSatisfy { $0.targetDirectoryPath == "/tmp/output" })
        XCTAssertEqual(tasks.map(\.outputPaths), [
            ["/tmp/output/first.png"],
            ["/tmp/output/second.png"],
        ])
        XCTAssertTrue(tasks.allSatisfy { $0.outputPath == $0.outputPaths?.first })
    }

    func testTaskRecordDecodesWithoutInputMetadata() throws {
        let task = ProcessingTaskRecord(
            id: UUID(),
            kind: .convert,
            title: "source.docx",
            inputPaths: ["/tmp/source.pdf"],
            state: .succeeded,
            progress: 1,
            createdAt: Date(timeIntervalSince1970: 1_768_000_000)
        )
        let encoded = try JSONEncoder().encode(task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "inputPageCount")
        object.removeValue(forKey: "inputFileSize")
        object.removeValue(forKey: "targetDirectoryPath")
        object.removeValue(forKey: "conversionPageIndices")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ProcessingTaskRecord.self, from: legacyData)

        XCTAssertNil(decoded.inputPageCount)
        XCTAssertNil(decoded.inputFileSize)
        XCTAssertNil(decoded.targetDirectoryPath)
        XCTAssertNil(decoded.conversionPageIndices)
    }

    func testTaskSectionsGroupBySecondAndUseRequiredTimestampFormat() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 17,
            hour: 9,
            minute: 19,
            second: 24
        )))
        let secondDate = firstDate.addingTimeInterval(0.8)
        let tasks = [firstDate, secondDate].map { date in
            ProcessingTaskRecord(
                id: UUID(),
                kind: .batchImage,
                title: "output.png",
                inputPaths: [],
                state: .succeeded,
                progress: 1,
                createdAt: date
            )
        }

        let sections = TaskSectionModel.group(tasks)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].tasks.count, 2)
        XCTAssertEqual(sections[0].taskIDs, Set(tasks.map(\.id)))
        XCTAssertEqual(TaskTimestampFormatter.string(from: sections[0].date), "2026/07/17 09:19:24")
    }

    func testRestoreSplitsLegacyCombinedBatchTaskIntoIndividualItems() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_768_000_000)
        let originalID = UUID()
        let legacyTask = ProcessingTaskRecord(
            id: originalID,
            kind: .batchImage,
            title: "images",
            inputPaths: ["/tmp/first.pdf", "/tmp/second.pdf"],
            outputPath: "/tmp/first.png",
            outputPaths: ["/tmp/first.png", "/tmp/second.png"],
            state: .succeeded,
            progress: 1,
            createdAt: createdAt
        )
        let repository = TestTaskRepository(records: [legacyTask])
        let queue = TaskQueueActor(
            merger: TestMerger(),
            imageExporter: TestImageExporter(),
            converter: BlockingConverter(probe: CancellationProbe()),
            repository: repository,
            trialStore: TestTrialStore()
        )

        await queue.restore()
        let tasks = await queue.snapshot()

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.first?.id, originalID)
        XCTAssertEqual(Set(tasks.map(\.createdAt)), [createdAt])
        XCTAssertEqual(tasks.map(\.inputPaths), [["/tmp/first.pdf"], ["/tmp/second.pdf"]])
        XCTAssertEqual(tasks.map(\.outputPaths), [["/tmp/first.png"], ["/tmp/second.png"]])
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
    private(set) var records: [ProcessingTaskRecord]

    init(records: [ProcessingTaskRecord] = []) {
        self.records = records
    }

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
    func export(_ request: BatchImageRequest) async throws -> [URL] {
        let sourceName = request.inputs[0].source.displayName
        let outputName = URL(fileURLWithPath: sourceName)
            .deletingPathExtension()
            .appendingPathExtension(request.imageFormat.fileExtension)
            .lastPathComponent
        return [request.outputDirectory.appendingPathComponent(outputName)]
    }
}

private struct TestTrialStore: TrialQuotaStoring {
    func remainingConversions() -> Int { 3 }
    func consumeSuccessfulConversion() throws {}
}
