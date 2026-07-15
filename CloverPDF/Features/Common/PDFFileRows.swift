import AppKit
import QuickLookThumbnailing
import SwiftUI

struct PDFFileRow: View {
    @Binding var item: WorkspacePDF
    let actions: PDFFileRowActions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PDFThumbnail(source: item.source)
                .frame(width: 48, height: 60)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.source.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(directoryPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.source.isLocked {
                    SecureField("PDF Password", text: $item.password)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                } else if item.source.appearsScanned {
                    Label("Scanned PDF: OCR is not included", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if actions.showsMoveActions {
                Button("Move Up", action: actions.moveUp)
                    .disabled(!actions.canMoveUp)
                Button("Move Down", action: actions.moveDown)
                    .disabled(!actions.canMoveDown)
                Divider()
            }
            Button("Show in Finder", action: actions.revealInFinder)
            Divider()
            Button("Delete", role: .destructive, action: actions.remove)
        }
    }

    private var metadata: String {
        let pages = String(localized: "\(item.source.pageCount) pages")
        let size = ByteCountFormatStyle(style: .file).format(item.source.fileSize)
        return "\(pages) · \(size)"
    }

    private var directoryPath: String {
        URL(fileURLWithPath: item.source.path).deletingLastPathComponent().path
    }
}

struct PDFFileRowActions {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let revealInFinder: () -> Void

    var showsMoveActions: Bool { canMoveUp || canMoveDown }
}

struct PDFThumbnail: NSViewRepresentable {
    let source: PDFSource

    func makeNSView(context: Context) -> PDFThumbnailContainerView {
        PDFThumbnailContainerView()
    }

    func updateNSView(_ view: PDFThumbnailContainerView, context: Context) {
        let key = source.id.uuidString
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.task?.cancel()
        view.image = nil
        context.coordinator.task = Task { @MainActor in
            let thumbnail = await PDFThumbnailLoader.load(source: source)
            guard !Task.isCancelled, context.coordinator.key == key else { return }
            view.image = thumbnail
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var key: String?
        var task: Task<Void, Never>?
    }

    static func dismantleNSView(_ nsView: PDFThumbnailContainerView, coordinator: Coordinator) {
        coordinator.task?.cancel()
    }
}

final class PDFThumbnailContainerView: NSView {
    private let imageView = NSImageView()

    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum PDFThumbnailLoader {
    @MainActor
    static func load(source: PDFSource) async -> NSImage? {
        guard !Task.isCancelled, let url = try? BookmarkService.resolve(source) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: 48, height: 60),
            scale: scale,
            representationTypes: .thumbnail
        )
        let thumbnail: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
        return thumbnail ?? NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct EmptyPDFState: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
