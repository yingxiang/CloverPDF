import SwiftUI

struct MergeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let selectedItem {
                HSplitView {
                    workspace
                    PDFWorkspacePreview(item: selectedItem)
                }
            } else {
                workspace
            }
        }
        .acceptsPDFDrops { model.importPDFs($0, destination: .merge) }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if model.mergeItems.isEmpty {
                EmptyPDFState(title: "No PDFs selected", icon: "square.stack.3d.up.slash") {
                    model.importPDFs(FilePanel.openPDFs(), destination: .merge)
                }
            } else {
                List(selection: $model.selectedMergeItemID) {
                    ForEach($model.mergeItems) { $item in
                        PDFFileRow(
                            item: $item,
                            actions: PDFFileRowActions(
                                canMoveUp: item.id != model.mergeItems.first?.id,
                                canMoveDown: item.id != model.mergeItems.last?.id,
                                moveUp: { model.moveMergeItem(item.id, offset: -1) },
                                moveDown: { model.moveMergeItem(item.id, offset: 1) },
                                remove: { model.removeMergeItem(item.id) },
                                revealInFinder: { model.revealSource(item.source) }
                            )
                        )
                        .tag(item.id)
                    }
                    .onMove { offsets, destination in
                        model.mergeItems.move(fromOffsets: offsets, toOffset: destination)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Spacer()
                Button {
                    model.enqueueBatchImages()
                } label: {
                    Label("Batch Convert", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(model.mergeItems.isEmpty)
                Button {
                    model.enqueueMerge()
                } label: {
                    Label("Merge", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.mergeItems.count < 2)
            }
            .padding(16)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedItem: WorkspacePDF? {
        guard let id = model.selectedMergeItemID else { return nil }
        return model.mergeItems.first { $0.id == id }
    }
}
