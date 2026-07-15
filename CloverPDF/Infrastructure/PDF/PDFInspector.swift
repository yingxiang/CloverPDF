import Foundation
import PDFKit

struct PDFInspector: Sendable {
    func inspect(url: URL) throws -> PDFSource {
        try BookmarkService.withAccess(to: url) {
            guard url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) else {
                throw CloverPDFError.invalidPDF
            }
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            let locked = document.isLocked
            let pageCount = document.pageCount
            let sampleCount = min(pageCount, 3)
            let hasText = !locked && (0..<sampleCount).contains { index in
                guard let text = document.page(at: index)?.string else { return false }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return PDFSource(
                displayName: url.lastPathComponent,
                path: url.path,
                bookmark: BookmarkService.create(for: url),
                pageCount: pageCount,
                fileSize: Int64(resourceValues?.fileSize ?? 0),
                isLocked: locked,
                appearsScanned: !locked && pageCount > 0 && !hasText
            )
        }
    }
}
