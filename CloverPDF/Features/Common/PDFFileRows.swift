import SwiftUI

struct PDFFileRow: View {
    @Binding var item: WorkspacePDF
    let index: Int
    let count: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.source.displayName)
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                iconButton("arrow.up", help: String(localized: "Move Up"), disabled: index == 0, action: moveUp)
                iconButton("arrow.down", help: String(localized: "Move Down"), disabled: index == count - 1, action: moveDown)
                iconButton("trash", help: String(localized: "Remove"), disabled: false, action: remove)
            }
        }
        .padding(.vertical, 7)
    }

    private var metadata: String {
        let pages = String(localized: "\(item.source.pageCount) pages")
        let size = ByteCountFormatStyle(style: .file).format(item.source.fileSize)
        return "\(pages) · \(size)"
    }

    private func iconButton(_ icon: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
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
