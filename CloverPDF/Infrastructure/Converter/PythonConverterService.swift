import Foundation

private struct ConverterRequestPayload: Encodable {
    let input: String
    let output: String
    let password: String?
    let startPage: Int?
    let endPage: Int?
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
        let finalURL = OutputURLResolver.availableURL(
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
        return try await {
            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            configure(process: process)
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            box.set(process)

            let payload = ConverterRequestPayload(
                input: workingInputURL.path,
                output: temporaryURL.path,
                password: request.input.password,
                startPage: request.pageRange?.lowerBound,
                endPage: request.pageRange?.upperBound
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
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            }
            return finalURL
        }()
    }

    private func configure(process: Process) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cloverpdf-converter")
        if FileManager.default.isExecutableFile(atPath: helper.path) {
            process.executableURL = helper
            return
        }
        guard let script = Bundle.main.url(forResource: "cloverpdf_converter", withExtension: "py") else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
            return
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
    }
}
