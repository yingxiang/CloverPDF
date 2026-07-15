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

    func makeNSView(context: Context) -> PDFView {
        let view = AutoScalingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let key = "\(source.id.uuidString):\(password)"
        guard context.coordinator.key != key else { return }
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var key: String?
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
            PDFKitView(source: item.source, password: item.password)
        }
        .frame(minWidth: 220, idealWidth: 360, maxWidth: .infinity)
    }
}
