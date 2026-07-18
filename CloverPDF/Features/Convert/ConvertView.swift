import AppKit
import SwiftUI

struct ConvertView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pageNavigationRequest: PDFPageNavigationRequest?
    @State private var draggedConversionItemID: UUID?
    @State private var conversionSelectionAnchor: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var dragStartFrame: CGRect?
    @State private var dragOffsetY: CGFloat = 0
    @State private var previousDragTranslationY: CGFloat = 0

    var body: some View {
        Group {
            if let selectedItemBinding {
                HSplitView {
                    workspace
                    PDFWorkspacePreview(
                        item: selectedItemBinding,
                        navigationRequest: pageNavigationRequest
                    )
                }
            } else {
                workspace
            }
        }
        .acceptsPDFDrops { model.importPDFs($0, destination: .convert) }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if model.conversionItems.isEmpty {
                EmptyPDFState(title: "No PDFs selected", icon: "doc.badge.plus") {
                    model.importPDFs(FilePanel.openPDFs(), destination: .convert)
                }
            } else {
                ZStack {
                    List {
                        ForEach($model.conversionItems) { $item in
                        VStack(spacing: 0) {
                            PDFFileRow(
                                item: $item,
                                actions: PDFFileRowActions(
                                    canMoveUp: item.id != model.conversionItems.first?.id,
                                    canMoveDown: item.id != model.conversionItems.last?.id,
                                    moveUp: { model.moveConversionItem(item.id, offset: -1) },
                                    moveDown: { model.moveConversionItem(item.id, offset: 1) },
                                    remove: { model.removeConversionItems(contextSelection(for: item.id)) },
                                    revealInFinder: {
                                        model.revealWorkspaceItems(
                                            contextSelection(for: item.id),
                                            in: model.conversionItems
                                        )
                                    }
                                )
                            )
                            .highPriorityGesture(reorderGesture(for: item))
                            .itemSelectionTap {
                                updateConversionSelection(item.id)
                            }
                            PDFPageSelectionStrip(item: $item) { pageIndex in
                                pageNavigationRequest = PDFPageNavigationRequest(pageIndex: pageIndex)
                            }
                            .itemSelectionTap {
                                updateConversionSelection(item.id)
                            }
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
                        .itemSelectionOutline(isSelected: model.selectedConversionItemIDs.contains(item.id))
                        .opacity(draggedConversionItemID == item.id ? 0 : 1)
                        }
                    }
                    .listStyle(.inset)

                    dragPreview
                }
                .onPreferenceChange(WorkspaceItemFramePreferenceKey.self) { itemFrames = $0 }
            }
            Divider()
            options
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var options: some View {
        HStack(spacing: 12) {
            Text(String(localized: "\(model.remainingTrialConversions) free conversions remaining"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !model.purchaseService.isPremiumUnlocked && selectedConversionCount > 1 {
                Label("Premium required for batch conversion", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.enqueueConversions()
            } label: {
                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.conversionItems.allSatisfy { $0.selectedPageIndices.isEmpty })
        }
        .padding(16)
    }

    private var selectedItemBinding: Binding<WorkspacePDF>? {
        guard let index = model.conversionItems.firstIndex(where: {
            model.selectedConversionItemIDs.contains($0.id)
        }) else {
            return nil
        }
        return $model.conversionItems[index]
    }

    private var selectedConversionCount: Int {
        model.conversionItems.count { !$0.selectedPageIndices.isEmpty }
    }

    private func contextSelection(for id: UUID) -> Set<UUID> {
        model.selectedConversionItemIDs.contains(id) ? model.selectedConversionItemIDs : [id]
    }

    private func updateConversionSelection(_ id: UUID) {
        let update = ItemSelectionController.update(
            id: id,
            orderedIDs: model.conversionItems.map(\.id),
            selection: model.selectedConversionItemIDs,
            anchor: conversionSelectionAnchor
        )
        model.selectedConversionItemIDs = update.selection
        conversionSelectionAnchor = update.anchor
    }

    private var dragPreview: some View {
        GeometryReader { proxy in
            if let draggedConversionItemID,
               let item = model.conversionItems.first(where: { $0.id == draggedConversionItemID }),
               let startFrame = dragStartFrame {
                let overlayFrame = proxy.frame(in: .global)
                WorkspaceItemDragPreview(
                    item: item,
                    size: startFrame.size,
                    showsPageSelection: true
                )
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
                if draggedConversionItemID == nil {
                    guard let frame = itemFrames[item.id] else { return }
                    model.selectedConversionItemIDs = [item.id]
                    conversionSelectionAnchor = item.id
                    draggedConversionItemID = item.id
                    dragStartFrame = frame
                }
                guard draggedConversionItemID == item.id, let startFrame = dragStartFrame else { return }
                let movementY = value.translation.height - previousDragTranslationY
                previousDragTranslationY = value.translation.height
                dragOffsetY = value.translation.height
                moveConversionItemIfNeeded(
                    item.id,
                    previewY: startFrame.midY + dragOffsetY,
                    movementY: movementY
                )
            }
            .onEnded { _ in settleConversionDrag(item.id) }
    }

    private func moveConversionItemIfNeeded(_ id: UUID, previewY: CGFloat, movementY: CGFloat) {
        guard abs(movementY) > 0.1,
              let sourceIndex = model.conversionItems.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = movementY > 0 ? sourceIndex + 1 : sourceIndex - 1
        guard model.conversionItems.indices.contains(targetIndex),
              let targetFrame = itemFrames[model.conversionItems[targetIndex].id] else { return }
        let crossedTarget = movementY > 0 ? previewY > targetFrame.midY : previewY < targetFrame.midY
        guard crossedTarget else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            model.conversionItems.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    private func settleConversionDrag(_ id: UUID) {
        guard let startFrame = dragStartFrame else { return }
        DispatchQueue.main.async {
            let finalFrame = itemFrames[id] ?? startFrame
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffsetY = finalFrame.midY - startFrame.midY
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard draggedConversionItemID == id else { return }
                draggedConversionItemID = nil
                dragStartFrame = nil
                dragOffsetY = 0
                previousDragTranslationY = 0
            }
        }
    }
}
