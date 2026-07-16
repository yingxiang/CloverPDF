import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanel {
    struct MergeDestination {
        let url: URL
        let format: MergeOutputFormat
    }

    struct BatchImageDestination {
        let directoryURL: URL
        let format: RasterImageFormat
    }

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

    static func saveMergedOutput(suggestedName: String = MergeFilenameGenerator.filename()) -> MergeDestination? {
        let panel = FileSavePanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = URL(fileURLWithPath: suggestedName)
            .deletingPathExtension()
            .lastPathComponent
        panel.title = String(localized: "Save Merged File")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let contentType = panel.selectedContentType
        return MergeDestination(
            url: outputURL(url, contentType: contentType),
            format: mergeOutputFormat(for: contentType)
        )
    }

    static func chooseBatchImageDestination() -> BatchImageDestination? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = String(localized: "Choose")
        panel.title = String(localized: "Choose Batch Output Folder")
        let accessory = FileFormatAccessory(contentTypes: [.png, .jpeg])
        panel.accessoryView = accessory.view
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return BatchImageDestination(
            directoryURL: url,
            format: rasterImageFormat(for: accessory.selectedContentType)
        )
    }

    private static func outputURL(_ url: URL, contentType: UTType) -> URL {
        guard let fileExtension = contentType.preferredFilenameExtension else { return url }
        let knownExtensions = Set(["pdf", "png", "jpg", "jpeg"])
        let baseURL = knownExtensions.contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension()
            : url
        return baseURL.appendingPathExtension(fileExtension)
    }

    private static func mergeOutputFormat(for contentType: UTType) -> MergeOutputFormat {
        contentType == .png ? .image(.png) : (contentType == .jpeg ? .image(.jpeg) : .pdf)
    }

    private static func rasterImageFormat(for contentType: UTType) -> RasterImageFormat {
        contentType == .jpeg ? .jpeg : .png
    }
}

@MainActor
private final class FileSavePanel: NSSavePanel {
    private(set) var selectedContentType: UTType = .pdf
    private var formatAccessory: FileFormatAccessory?

    override var allowedContentTypes: [UTType] {
        get { super.allowedContentTypes }
        set {
            isExtensionHidden = true
            allowsOtherFileTypes = false
            showsResizeIndicator = true
            super.allowedContentTypes = newValue
            let accessory = FileFormatAccessory(contentTypes: newValue) { [weak self] contentType in
                self?.selectedContentType = contentType
            }
            formatAccessory = accessory
            accessoryView = accessory.view
        }
    }
}

@MainActor
private final class FileFormatAccessory: NSObject {
    let view: NSView
    private let popup = NSPopUpButton()
    private let contentTypes: [UTType]
    private let selectionChanged: ((UTType) -> Void)?

    init(contentTypes: [UTType], selectionChanged: ((UTType) -> Void)? = nil) {
        self.contentTypes = contentTypes
        self.selectionChanged = selectionChanged
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        super.init()
        popup.addItems(withTitles: contentTypes.map(Self.displayName))
        popup.target = self
        popup.action = #selector(formatChanged)
        let label = NSTextField(labelWithString: String(localized: "Format"))
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
        selectionChanged?(selectedContentType)
    }

    var selectedContentType: UTType {
        contentTypes[max(0, popup.indexOfSelectedItem)]
    }

    @objc private func formatChanged() {
        selectionChanged?(selectedContentType)
    }

    private static func displayName(for contentType: UTType) -> String {
        contentType.localizedDescription
            ?? contentType.preferredFilenameExtension?.uppercased()
            ?? contentType.identifier
    }
}
