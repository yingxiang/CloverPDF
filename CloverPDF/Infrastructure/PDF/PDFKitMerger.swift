import AppKit
import Foundation
import PDFKit

final class PDFKitMerger: PDFMerging, @unchecked Sendable {
    func merge(_ request: MergeRequest) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            switch request.outputFormat {
            case .pdf:
                let pages = try PDFPagePipeline.loadPages(
                    from: request.inputs,
                    pageIndicesBySource: request.pageIndicesBySource
                )
                try PDFPagePipeline.writePDF(pages, to: request.outputURL)
            case .image(let format):
                let pages = try PDFPagePipeline.loadNamedPages(
                    from: request.inputs,
                    pageIndicesBySource: request.pageIndicesBySource
                )
                try PDFPageImageRenderer.writeLongImage(pages, format: format, to: request.outputURL)
            case .word:
                throw CloverPDFError.converterProtocol
            }
            return request.outputURL
        }.value
    }
}

final class PDFImageExporter: PDFImageExporting, @unchecked Sendable {
    func export(_ request: BatchImageRequest) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let pages = try PDFPagePipeline.loadNamedPages(
                from: request.inputs,
                pageIndicesBySource: request.pageIndicesBySource
            )
            return try PDFPageImageRenderer.writeDocumentImages(
                pages,
                format: request.imageFormat,
                to: request.outputDirectory
            )
        }.value
    }
}

enum PDFPagePipeline {
    struct NamedPage {
        let sourceIndex: Int
        let sourceName: String
        let page: PDFPage
        let document: PDFDocument
    }

    static func loadPages(
        from inputs: [PDFInput],
        pageIndicesBySource: [UUID: [Int]] = [:]
    ) throws -> [PDFPage] {
        try loadNamedPages(from: inputs, pageIndicesBySource: pageIndicesBySource)
            .compactMap { $0.page.copy() as? PDFPage }
    }

    static func loadNamedPages(
        from inputs: [PDFInput],
        pageIndicesBySource: [UUID: [Int]] = [:]
    ) throws -> [NamedPage] {
        guard !inputs.isEmpty else { throw CloverPDFError.noPages }
        var pages: [NamedPage] = []
        for (sourceIndex, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let url = try BookmarkService.resolve(input.source)
            try BookmarkService.withAccess(to: url) {
                let document = try openDocument(at: url, password: input.password)
                let requestedPages = pageIndicesBySource[input.source.id] ?? Array(0..<document.pageCount)
                for pageIndex in requestedPages where pageIndex >= 0 && pageIndex < document.pageCount {
                    try Task.checkCancellation()
                    guard let page = document.page(at: pageIndex) else { continue }
                    pages.append(NamedPage(
                        sourceIndex: sourceIndex,
                        sourceName: input.source.displayName,
                        page: page,
                        document: document
                    ))
                }
            }
        }
        guard !pages.isEmpty else { throw CloverPDFError.noPages }
        return pages
    }

    static func writePDF(_ pages: [PDFPage], to finalURL: URL) throws {
        let document = PDFDocument()
        for (index, page) in pages.enumerated() {
            document.insert(page, at: index)
        }
        let temporaryURL = temporarySibling(of: finalURL, extension: "pdf")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try BookmarkService.withAccess(to: finalURL) {
            guard document.write(to: temporaryURL), PDFDocument(url: temporaryURL)?.pageCount == pages.count else {
                throw CloverPDFError.outputFailed
            }
            try replaceOrMove(temporaryURL, to: finalURL)
        }
    }

    static func temporarySibling(of finalURL: URL, extension fileExtension: String) -> URL {
        finalURL.deletingLastPathComponent()
            .appendingPathComponent(".cloverpdf-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    static func replaceOrMove(_ temporaryURL: URL, to finalURL: URL) throws {
        if FileManager.default.fileExists(atPath: finalURL.path) {
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        }
    }

    private static func openDocument(at url: URL, password: String?) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw CloverPDFError.invalidPDF }
        if document.isLocked {
            guard let password, !password.isEmpty else { throw CloverPDFError.lockedPDF }
            guard document.unlock(withPassword: password) else { throw CloverPDFError.incorrectPassword }
        }
        return document
    }
}

enum PDFPageImageRenderer {
    private static let maximumWidth = 1_600
    private static let maximumTotalPixels = 100_000_000

    static func writeLongImage(
        _ pages: [PDFPagePipeline.NamedPage],
        format: RasterImageFormat,
        to finalURL: URL
    ) throws {
        try writeImage(makeLongImage(pages), format: format, to: finalURL)
    }

    static func writeDocumentImages(
        _ pages: [PDFPagePipeline.NamedPage],
        format: RasterImageFormat,
        to directory: URL
    ) throws -> [URL] {
        let staging = directory.appendingPathComponent(".cloverpdf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        return try BookmarkService.withAccess(to: directory) {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var stagedFiles: [(URL, String)] = []
            for documentPages in groupedBySource(pages) {
                try Task.checkCancellation()
                guard let firstPage = documentPages.first else { continue }
                let image = try makeLongImage(documentPages)
                let baseName = URL(fileURLWithPath: firstPage.sourceName)
                    .deletingPathExtension()
                    .lastPathComponent
                let temporaryURL = staging
                    .appendingPathComponent("\(firstPage.sourceIndex)-\(UUID().uuidString)")
                    .appendingPathExtension(format.fileExtension)
                try writeImageData(image, format: format, to: temporaryURL)
                stagedFiles.append((temporaryURL, baseName))
            }
            var outputURLs: [URL] = []
            for (temporaryURL, baseName) in stagedFiles {
                let finalURL = OutputURLResolver.availableURL(
                    directory: directory,
                    baseName: baseName,
                    extension: format.fileExtension
                )
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                outputURLs.append(finalURL)
            }
            return outputURLs
        }
    }

    static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw CloverPDFError.noPages }
        let width = min(maximumWidth, max(1, Int((bounds.width * 2).rounded())))
        let height = max(1, Int((CGFloat(width) * bounds.height / bounds.width).rounded()))
        guard let context = bitmapContext(width: width, height: height) else {
            throw CloverPDFError.outputFailed
        }
        fillWhite(context, width: width, height: height)
        let scale = CGFloat(width) / bounds.width
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw CloverPDFError.outputFailed }
        return image
    }

    private static func writeImage(_ image: CGImage, format: RasterImageFormat, to finalURL: URL) throws {
        let temporaryURL = PDFPagePipeline.temporarySibling(of: finalURL, extension: format.fileExtension)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try BookmarkService.withAccess(to: finalURL) {
            try writeImageData(image, format: format, to: temporaryURL)
            try PDFPagePipeline.replaceOrMove(temporaryURL, to: finalURL)
        }
    }

    private static func writeImageData(_ image: CGImage, format: RasterImageFormat, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        let type: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg
            ? [.compressionFactor: 0.9]
            : [:]
        guard let data = representation.representation(using: type, properties: properties) else {
            throw CloverPDFError.outputFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func fillWhite(_ context: CGContext, width: Int, height: Int) {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func makeLongImage(_ pages: [PDFPagePipeline.NamedPage]) throws -> CGImage {
        let images = try pages.map { try render($0.page) }
        let width = images.map(\.width).max() ?? 0
        let height = images.reduce(0) { $0 + $1.height }
        guard width > 0, height > 0, width * height <= maximumTotalPixels,
              let context = bitmapContext(width: width, height: height) else {
            throw CloverPDFError.outputFailed
        }
        fillWhite(context, width: width, height: height)
        var top = height
        for image in images {
            try Task.checkCancellation()
            top -= image.height
            let x = (width - image.width) / 2
            context.draw(image, in: CGRect(x: x, y: top, width: image.width, height: image.height))
        }
        guard let combined = context.makeImage() else { throw CloverPDFError.outputFailed }
        return combined
    }

    private static func groupedBySource(
        _ pages: [PDFPagePipeline.NamedPage]
    ) -> [[PDFPagePipeline.NamedPage]] {
        Dictionary(grouping: pages, by: \.sourceIndex)
            .sorted { $0.key < $1.key }
            .map(\.value)
    }
}
