import Foundation
import PDFKit

struct PDFInspector: Sendable {
    func inspect(url: URL) throws -> PDFSource {
        let fileURL = url.standardizedFileURL
        return try BookmarkService.withAccess(to: fileURL) {
            guard fileURL.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: fileURL) else {
                throw CloverPDFError.invalidPDF
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let locked = document.isLocked
            let pageCount = document.pageCount
            let sampleCount = min(pageCount, 3)
            let hasText = !locked && (0..<sampleCount).contains { index in
                guard let text = document.page(at: index)?.string else { return false }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return PDFSource(
                displayName: fileURL.lastPathComponent,
                path: fileURL.path(percentEncoded: false),
                bookmark: try BookmarkService.create(for: fileURL),
                pageCount: pageCount,
                fileSize: Int64(resourceValues?.fileSize ?? 0),
                isLocked: locked,
                appearsScanned: !locked && pageCount > 0 && !hasText
            )
        }
    }
}
