import Foundation

struct PDFSource: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let path: String
    let bookmark: Data?
    let pageCount: Int
    let fileSize: Int64
    let isLocked: Bool
    let appearsScanned: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        bookmark: Data?,
        pageCount: Int,
        fileSize: Int64,
        isLocked: Bool,
        appearsScanned: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmark = bookmark
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.isLocked = isLocked
        self.appearsScanned = appearsScanned
    }
}

struct PDFInput: Sendable {
    let source: PDFSource
    let password: String?
}
