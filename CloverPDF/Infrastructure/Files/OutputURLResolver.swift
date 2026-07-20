import Foundation

enum OutputURLResolver {
    static func availableURL(directory: URL, baseName: String, extension fileExtension: String) -> URL {
        let sanitized = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = sanitized.isEmpty ? "WPDF" : sanitized
        var candidate = directory.appendingPathComponent(effectiveName).appendingPathExtension(fileExtension)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(effectiveName) (\(index))")
                .appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    static func temporaryURL(extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloverPDF", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
    }
}
