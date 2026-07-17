import AppKit
import ImageIO
import PDFKit
import QuickLookThumbnailing
import SwiftUI

struct PDFFileRow: View {
    static let baseHeight: CGFloat = 74

    @Binding var item: WorkspacePDF
    let actions: PDFFileRowActions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PDFThumbnail(source: item.source)
                .frame(width: 48, height: 60)
                .clipped()
            PDFItemDetails(
                title: item.source.displayName,
                pageCount: item.source.pageCount,
                fileSize: item.source.fileSize,
                path: directoryPath
            ) {
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

    private var directoryPath: String {
        URL(fileURLWithPath: item.source.path).deletingLastPathComponent().path
    }
}

struct PDFPageSelectionStrip: View {
    @Binding var item: WorkspacePDF
    let onNavigate: (Int) -> Void
    @State private var pageFrames: [Int: CGRect] = [:]
    @State private var dragSelectionValue: Bool?
    @State private var lastDragLocation: CGPoint?

    private var coordinateSpaceName: String {
        "pdf-page-selection-\(item.id.uuidString)"
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: 10)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(0..<item.source.pageCount, id: \.self) { pageIndex in
                pageItem(pageIndex)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PDFPageFramePreferenceKey.self,
                                value: [pageIndex: proxy.frame(in: .named(coordinateSpaceName))]
                            )
                        }
                    }
            }
        }
        .padding(8)
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(PDFPageFramePreferenceKey.self) { pageFrames = $0 }
        .simultaneousGesture(pageSelectionGesture)
    }

    private func pageItem(_ pageIndex: Int) -> some View {
        let isSelected = item.selectedPageIndices.contains(pageIndex)
        return VStack(spacing: 10) {
            PDFPageThumbnail(source: item.source, password: item.password, pageIndex: pageIndex)
                .frame(width: 48, height: 42)
                .background(Color.white)
                .overlay {
                    Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Button {
                        toggleSelection(pageIndex)
                    } label: {
                        PageSelectionIndicator(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .offset(y: 7)
                }

            Button((pageIndex + 1).formatted()) {
                onNavigate(pageIndex)
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel(Text((pageIndex + 1).formatted()))
    }

    private func toggleSelection(_ pageIndex: Int) {
        if item.selectedPageIndices.contains(pageIndex) {
            item.selectedPageIndices.remove(pageIndex)
        } else {
            item.selectedPageIndices.insert(pageIndex)
        }
    }

    private var pageSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                updateDragSelection(from: lastDragLocation ?? value.startLocation, to: value.location)
                lastDragLocation = value.location
            }
            .onEnded { _ in
                dragSelectionValue = nil
                lastDragLocation = nil
            }
    }

    private func updateDragSelection(from start: CGPoint, to end: CGPoint) {
        let pageIndices = pageIndicesAlongPath(from: start, to: end)
        guard let firstPageIndex = pageIndices.first else { return }
        let shouldSelect = dragSelectionValue ?? !item.selectedPageIndices.contains(firstPageIndex)
        dragSelectionValue = shouldSelect
        for pageIndex in pageIndices {
            if shouldSelect {
                item.selectedPageIndices.insert(pageIndex)
            } else {
                item.selectedPageIndices.remove(pageIndex)
            }
        }
    }

    private func pageIndicesAlongPath(from start: CGPoint, to end: CGPoint) -> [Int] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let stepCount = max(1, Int(ceil(distance / 4)))
        var result: [Int] = []
        for step in 0...stepCount {
            let progress = CGFloat(step) / CGFloat(stepCount)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            guard let pageIndex = pageFrames.first(where: { $0.value.contains(point) })?.key,
                  result.last != pageIndex else { continue }
            result.append(pageIndex)
        }
        return result
    }
}

private struct PDFPageFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct PageSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? Color.green : Color(nsColor: .windowBackgroundColor))
            .overlay {
                Circle().stroke(isSelected ? Color.green : Color.secondary, lineWidth: 1)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
            .opacity(isSelected ? 1 : 0.5)
    }
}

private struct PDFPageThumbnail: NSViewRepresentable {
    let source: PDFSource
    let password: String
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFThumbnailContainerView {
        PDFThumbnailContainerView()
    }

    func updateNSView(_ view: PDFThumbnailContainerView, context: Context) {
        let key = "\(source.id.uuidString):\(password):\(pageIndex)"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.task?.cancel()
        view.image = nil
        context.coordinator.task = Task { @MainActor in
            let image = await PDFPageThumbnailLoader.load(
                source: source,
                password: password,
                pageIndex: pageIndex
            )
            guard !Task.isCancelled, context.coordinator.key == key else { return }
            view.image = image
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

private enum PDFPageThumbnailLoader {
    static func load(source: PDFSource, password: String, pageIndex: Int) async -> NSImage? {
        let result = await Task.detached(priority: .utility) {
            guard let url = try? BookmarkService.resolve(source) else {
                return SendableThumbnail(image: nil)
            }
            let image = BookmarkService.withAccess(to: url) {
                guard let document = PDFDocument(url: url) else { return nil as NSImage? }
                if document.isLocked && !document.unlock(withPassword: password) { return nil }
                guard let page = document.page(at: pageIndex) else { return nil }
                return page.thumbnail(of: NSSize(width: 96, height: 120), for: .mediaBox)
            }
            return SendableThumbnail(image: image)
        }.value
        return result.image
    }
}

private struct SendableThumbnail: @unchecked Sendable {
    let image: NSImage?
}

struct PDFItemDetails<Footer: View>: View {
    let title: String
    let titleIsUnavailable: Bool
    let pageCount: Int?
    let fileSize: Int64?
    let path: String
    let footer: Footer

    init(
        title: String,
        titleIsUnavailable: Bool = false,
        pageCount: Int?,
        fileSize: Int64?,
        path: String,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.titleIsUnavailable = titleIsUnavailable
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.path = path
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .strikethrough(titleIsUnavailable)
                .foregroundStyle(titleIsUnavailable ? .secondary : .primary)
            if let metadata {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var metadata: String? {
        guard let pageCount, let fileSize else { return nil }
        let pages = String(localized: "\(pageCount) pages")
        let size = ByteCountFormatStyle(style: .file).format(fileSize)
        return "\(pages) · \(size)"
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

struct ItemSelectionUpdate<ID: Hashable> {
    let selection: Set<ID>
    let anchor: ID?
}

enum ItemSelectionController {
    static func update<ID: Hashable>(
        id: ID,
        orderedIDs: [ID],
        selection: Set<ID>,
        anchor: ID?
    ) -> ItemSelectionUpdate<ID> {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift),
           let anchor,
           let anchorIndex = orderedIDs.firstIndex(of: anchor),
           let itemIndex = orderedIDs.firstIndex(of: id) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            let rangeIDs = Set(range.map { orderedIDs[$0] })
            let updated = modifiers.contains(.command) ? selection.union(rangeIDs) : rangeIDs
            return ItemSelectionUpdate(selection: updated, anchor: anchor)
        }
        if modifiers.contains(.command) {
            var updated = selection
            if updated.contains(id) {
                updated.remove(id)
            } else {
                updated.insert(id)
            }
            return ItemSelectionUpdate(selection: updated, anchor: id)
        }
        return ItemSelectionUpdate(selection: [id], anchor: id)
    }
}

extension View {
    func itemSelectionOutline(isSelected: Bool) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    func itemSelectionTap(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(TapGesture().onEnded(action))
    }

    func selectableItem(isSelected: Bool, action: @escaping () -> Void) -> some View {
        itemSelectionTap(action)
            .itemSelectionOutline(isSelected: isSelected)
    }
}

struct PDFThumbnail: NSViewRepresentable {
    private let source: PDFSource?
    private let fileURL: URL?

    init(source: PDFSource) {
        self.source = source
        fileURL = nil
    }

    init(fileURL: URL) {
        source = nil
        self.fileURL = fileURL
    }

    func makeNSView(context: Context) -> PDFThumbnailContainerView {
        PDFThumbnailContainerView()
    }

    func updateNSView(_ view: PDFThumbnailContainerView, context: Context) {
        let key = source?.id.uuidString ?? fileURL?.path
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.task?.cancel()
        view.image = nil
        context.coordinator.task = Task { @MainActor in
            let thumbnail: NSImage?
            if let source {
                thumbnail = await PDFThumbnailLoader.load(source: source)
            } else if let fileURL {
                thumbnail = await PDFThumbnailLoader.load(fileURL: fileURL)
            } else {
                thumbnail = nil
            }
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
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
        return await load(fileURL: url)
    }

    @MainActor
    static func load(fileURL: URL) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if isRasterImage(fileURL), let image = await RasterThumbnailLoader.load(fileURL: fileURL) {
            return image
        }
        let url = fileURL
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

    private static func isRasterImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

}

enum RasterThumbnailLoader {
    @MainActor
    static func load(fileURL url: URL) async -> NSImage? {
        let cgImage: CGImage? = await Task.detached(priority: .utility) { () -> CGImage? in
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

struct EmptyPDFState: View {
    let title: LocalizedStringKey
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            emptyStateIcon
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyStateIcon: some View {
        if let action {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add PDF")
            .help("Add PDF")
        } else {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
        }
    }
}
