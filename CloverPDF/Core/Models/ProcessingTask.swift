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
    let inputPageCount: Int?
    let inputFileSize: Int64?
    let targetDirectoryPath: String?
    let conversionPageIndices: [Int]?
    var outputPath: String? = nil
    var outputPaths: [String]? = nil
    var state: ProcessingTaskState
    var progress: Double
    var errorCode: String? = nil
    let createdAt: Date
    var finishedAt: Date? = nil

    init(
        id: UUID,
        kind: ProcessingTaskKind,
        title: String,
        inputPaths: [String],
        inputPageCount: Int? = nil,
        inputFileSize: Int64? = nil,
        targetDirectoryPath: String? = nil,
        conversionPageIndices: [Int]? = nil,
        outputPath: String? = nil,
        outputPaths: [String]? = nil,
        state: ProcessingTaskState,
        progress: Double,
        errorCode: String? = nil,
        createdAt: Date,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.inputPaths = inputPaths
        self.inputPageCount = inputPageCount
        self.inputFileSize = inputFileSize
        self.targetDirectoryPath = targetDirectoryPath
        self.conversionPageIndices = conversionPageIndices
        self.outputPath = outputPath
        self.outputPaths = outputPaths
        self.state = state
        self.progress = progress
        self.errorCode = errorCode
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }
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
    let pageIndices: [Int]
}

struct ConversionProgress: Sendable {
    let fraction: Double
    let phase: String
}
