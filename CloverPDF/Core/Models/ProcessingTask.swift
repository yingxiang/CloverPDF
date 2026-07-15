import Foundation

enum ProcessingTaskKind: String, Codable, Sendable {
    case merge
    case convert
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
    var state: ProcessingTaskState
    var progress: Double
    var errorCode: String? = nil
    let createdAt: Date
    var finishedAt: Date? = nil
}

struct MergeRequest: Sendable {
    let inputs: [PDFInput]
    let outputDirectory: URL
    let outputName: String
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
