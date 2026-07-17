import SwiftUI

struct MergeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectionAnchor: UUID?

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
                List {
                    ForEach($model.mergeItems) { $item in
                        PDFFileRow(
                            item: $item,
                            actions: PDFFileRowActions(
                                canMoveUp: item.id != model.mergeItems.first?.id,
                                canMoveDown: item.id != model.mergeItems.last?.id,
                                moveUp: { model.moveMergeItem(item.id, offset: -1) },
                                moveDown: { model.moveMergeItem(item.id, offset: 1) },
                                remove: { model.removeMergeItems(contextSelection(for: item.id)) },
                                revealInFinder: {
                                    model.revealWorkspaceItems(
                                        contextSelection(for: item.id),
                                        in: model.mergeItems
                                    )
                                }
                            )
                        )
                        .selectableItem(isSelected: model.selectedMergeItemIDs.contains(item.id)) {
                            updateSelection(item.id)
                        }
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
        model.mergeItems.first { model.selectedMergeItemIDs.contains($0.id) }
    }

    private func contextSelection(for id: UUID) -> Set<UUID> {
        model.selectedMergeItemIDs.contains(id) ? model.selectedMergeItemIDs : [id]
    }

    private func updateSelection(_ id: UUID) {
        let update = ItemSelectionController.update(
            id: id,
            orderedIDs: model.mergeItems.map(\.id),
            selection: model.selectedMergeItemIDs,
            anchor: selectionAnchor
        )
        model.selectedMergeItemIDs = update.selection
        selectionAnchor = update.anchor
    }
}
