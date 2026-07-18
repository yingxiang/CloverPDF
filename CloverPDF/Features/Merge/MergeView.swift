import SwiftUI

struct MergeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectionAnchor: UUID?
    @State private var draggedItemID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var dragStartFrame: CGRect?
    @State private var dragOffsetY: CGFloat = 0
    @State private var previousDragTranslationY: CGFloat = 0

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
                ZStack {
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
                        .highPriorityGesture(reorderGesture(for: item))
                        .selectableItem(isSelected: model.selectedMergeItemIDs.contains(item.id)) {
                            updateSelection(item.id)
                        }
                        .contentShape(Rectangle())
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: WorkspaceItemFramePreferenceKey.self,
                                        value: [item.id: proxy.frame(in: .global)]
                                    )
                            }
                        }
                        .opacity(draggedItemID == item.id ? 0 : 1)
                        }
                    }
                    .listStyle(.inset)

                    dragPreview
                }
                .onPreferenceChange(WorkspaceItemFramePreferenceKey.self) { itemFrames = $0 }
            }
            Divider()
            HStack {
                Spacer()
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

    private var dragPreview: some View {
        GeometryReader { proxy in
            if let draggedItemID,
               let item = model.mergeItems.first(where: { $0.id == draggedItemID }),
               let startFrame = dragStartFrame {
                let overlayFrame = proxy.frame(in: .global)
                WorkspaceItemDragPreview(item: item, size: startFrame.size, showsPageSelection: false)
                    .position(
                        x: startFrame.midX - overlayFrame.minX,
                        y: startFrame.midY + dragOffsetY - overlayFrame.minY
                    )
            }
        }
        .allowsHitTesting(false)
        .zIndex(10)
    }

    private func reorderGesture(for item: WorkspacePDF) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if draggedItemID == nil {
                    guard let frame = itemFrames[item.id] else { return }
                    model.selectedMergeItemIDs = [item.id]
                    selectionAnchor = item.id
                    draggedItemID = item.id
                    dragStartFrame = frame
                }
                guard draggedItemID == item.id, let startFrame = dragStartFrame else { return }
                let movementY = value.translation.height - previousDragTranslationY
                previousDragTranslationY = value.translation.height
                dragOffsetY = value.translation.height
                moveMergeItemIfNeeded(
                    item.id,
                    previewY: startFrame.midY + dragOffsetY,
                    movementY: movementY
                )
            }
            .onEnded { _ in settleMergeDrag(item.id) }
    }

    private func moveMergeItemIfNeeded(_ id: UUID, previewY: CGFloat, movementY: CGFloat) {
        guard abs(movementY) > 0.1,
              let sourceIndex = model.mergeItems.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = movementY > 0 ? sourceIndex + 1 : sourceIndex - 1
        guard model.mergeItems.indices.contains(targetIndex),
              let targetFrame = itemFrames[model.mergeItems[targetIndex].id] else { return }
        let crossedTarget = movementY > 0 ? previewY > targetFrame.midY : previewY < targetFrame.midY
        guard crossedTarget else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            model.mergeItems.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    private func settleMergeDrag(_ id: UUID) {
        guard let startFrame = dragStartFrame else { return }
        DispatchQueue.main.async {
            let finalFrame = itemFrames[id] ?? startFrame
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffsetY = finalFrame.midY - startFrame.midY
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard draggedItemID == id else { return }
                draggedItemID = nil
                dragStartFrame = nil
                dragOffsetY = 0
                previousDragTranslationY = 0
            }
        }
    }
}
