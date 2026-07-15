import Foundation
import PDFKit

final class PDFKitMerger: PDFMerging, @unchecked Sendable {
    func merge(_ request: MergeRequest) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !request.inputs.isEmpty else { throw CloverPDFError.noPages }
            let output = PDFDocument()
            var outputIndex = 0
            for input in request.inputs {
                try Task.checkCancellation()
                let url = try BookmarkService.resolve(input.source)
                try BookmarkService.withAccess(to: url) {
                    guard let document = PDFDocument(url: url) else { throw CloverPDFError.invalidPDF }
                    if document.isLocked {
                        guard let password = input.password, !password.isEmpty else {
                            throw CloverPDFError.lockedPDF
                        }
                        guard document.unlock(withPassword: password) else {
                            throw CloverPDFError.incorrectPassword
                        }
                    }
                    for pageIndex in 0..<document.pageCount {
                        try Task.checkCancellation()
                        guard let page = document.page(at: pageIndex)?.copy() as? PDFPage else { continue }
                        output.insert(page, at: outputIndex)
                        outputIndex += 1
                    }
                }
            }
            guard outputIndex > 0 else { throw CloverPDFError.noPages }
            let temporaryURL = try OutputURLResolver.temporaryURL(extension: "pdf")
            guard output.write(to: temporaryURL) else { throw CloverPDFError.outputFailed }
            guard PDFDocument(url: temporaryURL)?.pageCount == outputIndex else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw CloverPDFError.outputFailed
            }
            let finalURL = OutputURLResolver.availableURL(
                directory: request.outputDirectory,
                baseName: request.outputName,
                extension: "pdf"
            )
            try BookmarkService.withAccess(to: request.outputDirectory) {
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            }
            return finalURL
        }.value
    }
}
