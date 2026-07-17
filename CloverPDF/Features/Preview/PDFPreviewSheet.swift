import PDFKit
import SwiftUI

struct PDFPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    let item: WorkspacePDF

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.source.displayName).font(.headline).lineLimit(1)
                    Text(String(localized: "\(item.source.pageCount) pages"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.previewItem = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            PDFKitView(source: item.source, password: item.password)
                .frame(minWidth: 700, minHeight: 500)
            Divider()
            HStack {
                if item.source.appearsScanned {
                    Label("Scanned PDF: OCR is not included", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    model.usePreviewForMerge()
                } label: {
                    Label("Add to Merge", systemImage: "square.stack.3d.up")
                }
                Button {
                    model.usePreviewForConversion()
                } label: {
                    Label("Convert to Word", systemImage: "doc.text")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let source: PDFSource
    var password = ""
    var selectedPageIndices: Binding<Set<Int>>?
    var navigationRequest: PDFPageNavigationRequest?

    init(
        source: PDFSource,
        password: String = "",
        selectedPageIndices: Binding<Set<Int>>? = nil,
        navigationRequest: PDFPageNavigationRequest? = nil
    ) {
        self.source = source
        self.password = password
        self.selectedPageIndices = selectedPageIndices
        self.navigationRequest = navigationRequest
    }

    func makeNSView(context: Context) -> PDFView {
        let view = AutoScalingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.updateSelection(selectedPageIndices)
        view.pageOverlayViewProvider = selectedPageIndices == nil ? nil : context.coordinator

        let key = "\(source.id.uuidString):\(password)"
        if context.coordinator.key != key {
            context.coordinator.key = key
            guard let url = try? BookmarkService.resolve(source) else { return }
            BookmarkService.withAccess(to: url) {
                guard let document = PDFDocument(url: url) else { return }
                if document.isLocked && !document.unlock(withPassword: password) {
                    view.document = nil
                    return
                }
                view.document = document
                view.autoScales = true
            }
        }

        guard let request = navigationRequest,
              context.coordinator.lastNavigationRequestID != request.id,
              let page = view.document?.page(at: request.pageIndex) else { return }
        context.coordinator.lastNavigationRequestID = request.id
        view.go(to: page)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        var key: String?
        var lastNavigationRequestID: UUID?
        private var selectedPageIndices: Set<Int> = []
        private var selectionBinding: Binding<Set<Int>>?
        private var buttons: [Int: PageSelectionButton] = [:]

        func updateSelection(_ binding: Binding<Set<Int>>?) {
            selectionBinding = binding
            selectedPageIndices = binding?.wrappedValue ?? []
            for (pageIndex, button) in buttons {
                button.updateAppearance(isSelected: selectedPageIndices.contains(pageIndex))
            }
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
            guard selectionBinding != nil,
                  let document = view.document else { return nil }
            let pageIndex = document.index(for: page)
            let overlay = PageSelectionOverlayView()
            let button = PageSelectionButton(pageIndex: pageIndex)
            button.target = self
            button.action = #selector(togglePage(_:))
            button.updateAppearance(isSelected: selectedPageIndices.contains(pageIndex))
            overlay.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
                button.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 8),
                button.widthAnchor.constraint(equalToConstant: 18),
                button.heightAnchor.constraint(equalToConstant: 18)
            ])
            buttons[pageIndex] = button
            return overlay
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: NSView, for page: PDFPage) {
            guard let document = pdfView.document else { return }
            buttons.removeValue(forKey: document.index(for: page))
        }

        @objc private func togglePage(_ sender: PageSelectionButton) {
            if selectedPageIndices.contains(sender.pageIndex) {
                selectedPageIndices.remove(sender.pageIndex)
            } else {
                selectedPageIndices.insert(sender.pageIndex)
            }
            sender.updateAppearance(isSelected: selectedPageIndices.contains(sender.pageIndex))
            selectionBinding?.wrappedValue = selectedPageIndices
        }
    }
}

struct PDFPageNavigationRequest: Equatable {
    let id = UUID()
    let pageIndex: Int
}

private final class PageSelectionOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

private final class PageSelectionButton: NSButton {
    let pageIndex: Int
    private var isPageSelected = false

    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        title = ""
        setAccessibilityLabel((pageIndex + 1).formatted())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func updateAppearance(isSelected: Bool) {
        isPageSelected = isSelected
        alphaValue = isSelected ? 1 : 0.5
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height) - 1
        let circleRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = NSBezierPath(ovalIn: circleRect)
        (isPageSelected ? NSColor.systemGreen : NSColor.windowBackgroundColor).setFill()
        circle.fill()
        (isPageSelected ? NSColor.systemGreen : NSColor.secondaryLabelColor).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        guard isPageSelected else { return }
        let yDirection: CGFloat = isFlipped ? -1 : 1
        let checkmark = NSBezierPath()
        checkmark.move(to: NSPoint(x: bounds.midX - 4, y: bounds.midY))
        checkmark.line(to: NSPoint(x: bounds.midX - 1, y: bounds.midY - 3 * yDirection))
        checkmark.line(to: NSPoint(x: bounds.midX + 4, y: bounds.midY + 3 * yDirection))
        checkmark.lineWidth = 1.5
        checkmark.lineCapStyle = .round
        checkmark.lineJoinStyle = .round
        NSColor.white.setStroke()
        checkmark.stroke()
    }
}

private final class AutoScalingPDFView: PDFView {
    override func layout() {
        super.layout()
        guard document != nil else { return }
        autoScales = true
        let fittingScale = scaleFactorForSizeToFit
        if fittingScale.isFinite, fittingScale > 0 {
            scaleFactor = fittingScale
        }
    }
}

struct PDFWorkspacePreview: View {
    let item: WorkspacePDF
    private let selectedPageIndices: Binding<Set<Int>>?
    private let navigationRequest: PDFPageNavigationRequest?

    init(item: WorkspacePDF) {
        self.item = item
        selectedPageIndices = nil
        navigationRequest = nil
    }

    init(item: Binding<WorkspacePDF>, navigationRequest: PDFPageNavigationRequest?) {
        self.item = item.wrappedValue
        selectedPageIndices = item.selectedPageIndices
        self.navigationRequest = navigationRequest
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.source.displayName).font(.headline).lineLimit(1)
                    Text(String(localized: "\(item.source.pageCount) pages"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            Divider()
            PDFKitView(
                source: item.source,
                password: item.password,
                selectedPageIndices: selectedPageIndices,
                navigationRequest: navigationRequest
            )
        }
        .frame(minWidth: 220, idealWidth: 360, maxWidth: .infinity)
    }
}
