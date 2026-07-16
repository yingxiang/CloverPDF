import Foundation

enum ProcessingTaskKind: String, Codable, Sendable {
    case merge
    case convert
    case batchImage
}

enum ProcessingTaskState: String, Codable, Sendable {
    case pending
    case validating
    case running
    case succeeded
    case failed
    case cancelled
    case interrupted
}

struct ProcessingTaskRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let kind: ProcessingTaskKind
    let title: String
    let inputPaths: [String]
    var outputPath: String? = nil
    var outputPaths: [String]? = nil
    var state: ProcessingTaskState
    var progress: Double
    var errorCode: String? = nil
    let createdAt: Date
    var finishedAt: Date? = nil
}

struct MergeRequest: Sendable {
    let inputs: [PDFInput]
    let outputURL: URL
    let outputFormat: MergeOutputFormat
}

enum RasterImageFormat: String, Sendable {
    case png
    case jpeg

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
}

enum MergeOutputFormat: Sendable {
    case pdf
    case image(RasterImageFormat)
}

struct BatchImageRequest: Sendable {
    let inputs: [PDFInput]
    let outputDirectory: URL
    let imageFormat: RasterImageFormat
}

struct ConversionRequest: Sendable {
    let input: PDFInput
    let outputDirectory: URL
    let pageRange: ClosedRange<Int>?
}

struct ConversionProgress: Sendable {
    let fraction: Double
    let phase: String
}
