import Foundation

protocol PDFMerging: Sendable {
    func merge(_ request: MergeRequest) async throws -> URL
}

protocol PDFImageExporting: Sendable {
    func export(_ request: BatchImageRequest) async throws -> URL
}

protocol PDFConverting: Sendable {
    func convert(
        _ request: ConversionRequest,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL
}

protocol TaskRepository: Sendable {
    func load() async throws -> [ProcessingTaskRecord]
    func save(_ tasks: [ProcessingTaskRecord]) async throws
}

protocol TrialQuotaStoring: Sendable {
    func remainingConversions() -> Int
    func consumeSuccessfulConversion() throws
}
