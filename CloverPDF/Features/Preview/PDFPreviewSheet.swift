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
                    Text("\(item.source.pageCount) pages").font(.caption).foregroundStyle(.secondary)
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
            PDFKitView(source: item.source)
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

private struct PDFKitView: NSViewRepresentable {
    let source: PDFSource

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard let url = try? BookmarkService.resolve(source) else { return }
        BookmarkService.withAccess(to: url) {
            view.document = PDFDocument(url: url)
        }
    }
}
