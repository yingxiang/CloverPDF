import AppKit
import Foundation
import PDFKit
import Vision

enum OCRSettings {
    static let enabledKey = "ocrScannedDocumentsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

private struct OCRBlockPayload: Encodable, Sendable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct OCRPagePayload: Encodable, Sendable {
    let page: Int
    let width: Double
    let height: Double
    let blocks: [OCRBlockPayload]
}

private struct ConverterRequestPayload: Encodable {
    let input: String
    let output: String
    let password: String?
    let pages: [Int]
    let ocrPages: [OCRPagePayload]?
}

private struct ConverterEvent: Decodable {
    let type: String
    let progress: Double?
    let phase: String?
    let output: String?
    let code: String?
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
}

final class PythonConverterService: PDFConverting, @unchecked Sendable {
    func convert(
        _ request: ConversionRequest,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await run(request, progress: progress, box: box)
        } onCancel: {
            box.terminate()
        }
    }

    private func run(
        _ request: ConversionRequest,
        progress: @escaping @Sendable (ConversionProgress) -> Void,
        box: ProcessBox
    ) async throws -> URL {
        let inputURL = try BookmarkService.resolve(request.input.source)
        let workingInputURL = try OutputURLResolver.temporaryURL(extension: "pdf")
        let temporaryURL = try OutputURLResolver.temporaryURL(extension: "docx")
        let finalURL = request.outputURL ?? OutputURLResolver.availableURL(
            directory: request.outputDirectory,
            baseName: inputURL.deletingPathExtension().lastPathComponent,
            extension: "docx"
        )
        defer {
            try? FileManager.default.removeItem(at: workingInputURL)
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }
        try BookmarkService.withAccess(to: inputURL) {
            try FileManager.default.copyItem(at: inputURL, to: workingInputURL)
        }
        let ocrPages = try await prepareOCR(request, pdfURL: workingInputURL, progress: progress)
        return try await {
            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            try configure(process: process)
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            box.set(process)

            let payload = ConverterRequestPayload(
                input: workingInputURL.path,
                output: temporaryURL.path,
                password: request.input.password,
                pages: request.pageIndices,
                ocrPages: ocrPages
            )
            let payloadData = try JSONEncoder().encode(payload) + Data([0x0A])
            try process.run()
            stdinPipe.fileHandleForWriting.write(payloadData)
            try stdinPipe.fileHandleForWriting.close()

            var completedOutput: String?
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let event = try? JSONDecoder().decode(ConverterEvent.self, from: data) else {
                    continue
                }
                if event.type == "progress" {
                    progress(ConversionProgress(fraction: event.progress ?? 0, phase: event.phase ?? "convert"))
                } else if event.type == "completed" {
                    completedOutput = event.output
                } else if event.type == "failed" {
                    throw CloverPDFError.conversionFailed(event.code ?? "unknown")
                }
            }
            process.waitUntilExit()
            if Task.isCancelled { throw CloverPDFError.cancelled }
            guard process.terminationStatus == 0,
                  completedOutput == temporaryURL.path,
                  FileManager.default.fileExists(atPath: temporaryURL.path) else {
                let diagnostics = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown"
                throw CloverPDFError.conversionFailed(diagnostics.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            try BookmarkService.withAccess(to: request.outputDirectory) {
                try PDFPagePipeline.replaceOrMove(temporaryURL, to: finalURL)
            }
            return finalURL
        }()
    }

    private func configure(process: Process) throws {
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Converter/cloverpdf-converter/cloverpdf-converter")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw CloverPDFError.converterUnavailable
        }
        process.executableURL = helper
    }

    private func prepareOCR(
        _ request: ConversionRequest,
        pdfURL: URL,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> [OCRPagePayload]? {
        guard request.input.source.appearsScanned, OCRSettings.isEnabled else { return nil }
        return try await SystemPDFOCR.recognize(
            pdfURL: pdfURL,
            password: request.input.password,
            pageIndices: request.pageIndices
        ) { completed, total in
            let fraction = 0.05 + (Double(completed) / Double(max(total, 1))) * 0.65
            progress(ConversionProgress(fraction: fraction, phase: "ocr"))
        }
    }
}

private enum SystemPDFOCR {
    static func recognize(
        pdfURL: URL,
        password: String?,
        pageIndices: [Int],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [OCRPagePayload] {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: pdfURL) else { throw CloverPDFError.invalidPDF }
            if document.isLocked && !document.unlock(withPassword: password ?? "") {
                throw CloverPDFError.incorrectPassword
            }
            var results: [OCRPagePayload] = []
            for (offset, pageIndex) in pageIndices.enumerated() {
                try Task.checkCancellation()
                guard let page = document.page(at: pageIndex),
                      let image = render(page: page) else {
                    throw CloverPDFError.conversionFailed("ocr_render_failed")
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                let observations = request.results ?? []
                let bounds = page.bounds(for: .mediaBox)
                let rotation = ((page.rotation % 360) + 360) % 360
                let isQuarterTurn = rotation == 90 || rotation == 270
                let pageWidth = isQuarterTurn ? bounds.height : bounds.width
                let pageHeight = isQuarterTurn ? bounds.width : bounds.height
                let blocks = observations
                    .sorted(by: readingOrder)
                    .compactMap { observation -> OCRBlockPayload? in
                        guard let text = observation.topCandidates(1).first?.string,
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        let box = observation.boundingBox
                        return OCRBlockPayload(
                            text: text,
                            x: box.minX * pageWidth,
                            y: (1 - box.maxY) * pageHeight,
                            width: box.width * pageWidth,
                            height: box.height * pageHeight
                        )
                    }
                results.append(OCRPagePayload(
                    page: pageIndex,
                    width: pageWidth,
                    height: pageHeight,
                    blocks: blocks
                ))
                progress(offset + 1, pageIndices.count)
            }
            return results
        }.value
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(3, 2400 / max(bounds.width, bounds.height))
        let rotation = ((page.rotation % 360) + 360) % 360
        let isQuarterTurn = rotation == 90 || rotation == 270
        let displayWidth = isQuarterTurn ? bounds.height : bounds.width
        let displayHeight = isQuarterTurn ? bounds.width : bounds.height
        let width = max(1, Int((displayWidth * scale).rounded(.up)))
        let height = max(1, Int((displayHeight * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        if rotation == 90 {
            context.translateBy(x: bounds.height, y: 0)
            context.rotate(by: .pi / 2)
        } else if rotation == 270 {
            context.translateBy(x: 0, y: bounds.width)
            context.rotate(by: -.pi / 2)
        } else if rotation == 180 {
            context.translateBy(x: bounds.width, y: bounds.height)
            context.rotate(by: .pi)
        }
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func readingOrder(_ lhs: VNRecognizedTextObservation, _ rhs: VNRecognizedTextObservation) -> Bool {
        let verticalTolerance: CGFloat = 0.015
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > verticalTolerance {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}
