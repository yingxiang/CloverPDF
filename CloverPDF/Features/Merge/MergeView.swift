import SwiftUI

struct MergeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if model.mergeItems.isEmpty {
                    EmptyPDFState(title: "No PDFs selected", icon: "square.stack.3d.up.slash")
                } else {
                    List {
                        ForEach(Array(model.mergeItems.indices), id: \.self) { index in
                            PDFFileRow(
                                item: $model.mergeItems[index],
                                index: index,
                                count: model.mergeItems.count,
                                moveUp: { move(index, offset: -1) },
                                moveDown: { move(index, offset: 1) },
                                remove: { model.mergeItems.remove(at: index) }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .acceptsPDFDrops { model.importPDFs($0, destination: .merge) }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Merge PDFs").font(.title2).fontWeight(.semibold)
                Text("\(model.mergeItems.reduce(0) { $0 + $1.source.pageCount }) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.importPDFs(FilePanel.openPDFs(), destination: .merge)
            } label: {
                Label("Add PDFs", systemImage: "plus")
            }
            Button {
                model.mergeItems.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear")
            .disabled(model.mergeItems.isEmpty)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            TextField("Output Name", text: $model.mergeOutputName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Button {
                model.outputDirectory = FilePanel.chooseDirectory(current: model.outputDirectory) ?? model.outputDirectory
            } label: {
                Label(model.outputDirectory.lastPathComponent, systemImage: "folder")
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.enqueueMerge()
            } label: {
                Label("Merge", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.mergeItems.isEmpty || model.mergeOutputName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
    }

    private func move(_ index: Int, offset: Int) {
        let destination = index + offset
        guard model.mergeItems.indices.contains(destination) else { return }
        model.mergeItems.swapAt(index, destination)
    }
}
