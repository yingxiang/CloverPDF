import Foundation

actor JSONTaskRepository: TaskRepository {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CloverPDF", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tasks.json")
    }

    func load() async throws -> [ProcessingTaskRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.cloverPDF.decode([ProcessingTaskRecord].self, from: data).map { task in
            var updated = task
            if task.state == .running || task.state == .validating {
                updated.state = .interrupted
                updated.finishedAt = Date()
            }
            return updated
        }
    }

    func save(_ tasks: [ProcessingTaskRecord]) async throws {
        let data = try JSONEncoder.cloverPDF.encode(tasks)
        let temporary = fileURL.deletingLastPathComponent().appendingPathComponent("tasks-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }
}

private extension JSONEncoder {
    static var cloverPDF: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var cloverPDF: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
