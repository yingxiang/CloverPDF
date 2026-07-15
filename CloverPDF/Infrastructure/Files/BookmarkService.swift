import Foundation

enum BookmarkService {
    static func create(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ source: PDFSource) throws -> URL {
        guard let bookmark = source.bookmark else { return URL(fileURLWithPath: source.path) }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return url
    }

    static func withAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try operation()
    }

    static func withAccess<T>(to url: URL, operation: () async throws -> T) async rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try await operation()
    }
}
