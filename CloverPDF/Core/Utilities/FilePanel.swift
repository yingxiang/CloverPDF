import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanel {
    struct MergeDestination {
        let url: URL
        let format: MergeOutputFormat
    }

    enum ConversionFormat {
        case pdf
        case word
        case image(RasterImageFormat)
    }

    struct ConversionDestination {
        let directoryURL: URL
        let outputURL: URL?
        let format: ConversionFormat
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
        panel.allowedContentTypes = [.pdf, .png, .jpeg, wordContentType]
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

    static func chooseConversionDestination(suggestedName: String, isBatch: Bool) -> ConversionDestination? {
        if !isBatch {
            return saveConvertedOutput(suggestedName: suggestedName)
        }
        let panel = FileDirectoryPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [wordContentType, .pdf, .png, .jpeg]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = String(localized: "Choose")
        panel.title = String(localized: "Choose Conversion Output Folder")
        guard panel.runModalWithVisibleFormat() == .OK, let url = panel.url else { return nil }
        let format: ConversionFormat = switch panel.selectedContentType {
        case .pdf: .pdf
        case .png: .image(.png)
        case .jpeg: .image(.jpeg)
        default: .word
        }
        return ConversionDestination(
            directoryURL: url,
            outputURL: nil,
            format: format
        )
    }

    private static func saveConvertedOutput(suggestedName: String) -> ConversionDestination? {
        let panel = FileSavePanel()
        panel.allowedContentTypes = [wordContentType, .pdf, .png, .jpeg]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = URL(fileURLWithPath: suggestedName)
            .deletingPathExtension()
            .lastPathComponent
        panel.title = String(localized: "Save Converted File")
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let contentType = panel.selectedContentType
        let format: ConversionFormat = switch contentType {
        case .pdf: .pdf
        case .png: .image(.png)
        case .jpeg: .image(.jpeg)
        default: .word
        }
        let outputURL = outputURL(selectedURL, contentType: contentType)
        return ConversionDestination(
            directoryURL: outputURL.deletingLastPathComponent(),
            outputURL: outputURL,
            format: format
        )
    }

    private static func outputURL(_ url: URL, contentType: UTType) -> URL {
        guard let fileExtension = contentType.preferredFilenameExtension else { return url }
        let knownExtensions = Set(["pdf", "png", "jpg", "jpeg", "docx"])
        let baseURL = knownExtensions.contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension()
            : url
        return baseURL.appendingPathExtension(fileExtension)
    }

    private static func mergeOutputFormat(for contentType: UTType) -> MergeOutputFormat {
        if contentType == .png { return .image(.png) }
        if contentType == .jpeg { return .image(.jpeg) }
        if contentType == wordContentType { return .word }
        return .pdf
    }

    private static var wordContentType: UTType {
        UTType(filenameExtension: "docx") ?? .data
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
private final class FileDirectoryPanel: NSOpenPanel {
    private(set) var selectedContentType: UTType = .data
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

    func runModalWithVisibleFormat() -> NSApplication.ModalResponse {
        isAccessoryViewDisclosed = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidUpdate),
            name: NSWindow.didUpdateNotification,
            object: self
        )
        DispatchQueue.main.async { [weak self] in
            self?.hideAccessoryDisclosureButton()
        }
        let response = runModal()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didUpdateNotification,
            object: self
        )
        return response
    }

    @objc private func panelDidUpdate() {
        hideAccessoryDisclosureButton()
    }

    private func hideAccessoryDisclosureButton() {
        guard let rootView = contentView else { return }
        hideAccessoryDisclosureButton(in: rootView)
    }

    private func hideAccessoryDisclosureButton(in view: NSView) {
        if let button = view as? NSButton {
            if button.bezelStyle == .disclosure
                || actionControlsAccessory(button.action)
                || titleControlsOptions(button.title) {
                button.isHidden = true
            }
        }
        for subview in view.subviews {
            hideAccessoryDisclosureButton(in: subview)
        }
    }

    private func actionControlsAccessory(_ action: Selector?) -> Bool {
        guard let action else { return false }
        return NSStringFromSelector(action).localizedCaseInsensitiveContains("accessory")
    }

    private func titleControlsOptions(_ title: String) -> Bool {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let optionTerms = [
            "options", "optionen", "opciones", "opzioni", "opcoes", "opties",
            "选项", "選項", "オプション", "옵션", "параметр",
        ]
        return optionTerms.contains { normalized.localizedCaseInsensitiveContains($0) }
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
        contentType.preferredFilenameExtension?.uppercased() ?? contentType.identifier
    }
}
