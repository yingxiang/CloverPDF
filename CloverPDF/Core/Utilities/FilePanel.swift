import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanel {
    static func openPDFs() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseDirectory(current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveMergedPDF(suggestedName: String = MergeFilenameGenerator.filename()) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = suggestedName
        panel.title = String(localized: "Save Merged PDF")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
