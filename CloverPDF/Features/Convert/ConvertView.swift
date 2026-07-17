import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConvertView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pageNavigationRequest: PDFPageNavigationRequest?
    @State private var draggedConversionItemID: UUID?
    @State private var conversionSelectionAnchor: UUID?

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
                            .itemSelectionTap {
                                updateConversionSelection(item.id)
                            }
                            .onDrag {
                                draggedConversionItemID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            } preview: {
                                ConversionItemDragPreview(item: item)
                            }
                            PDFPageSelectionStrip(item: $item) { pageIndex in
                                pageNavigationRequest = PDFPageNavigationRequest(pageIndex: pageIndex)
                            }
                            .itemSelectionTap {
                                updateConversionSelection(item.id)
                            }
                        }
                        .onDrop(
                            of: [UTType.utf8PlainText],
                            delegate: ConversionItemDropDelegate(
                                targetID: item.id,
                                items: $model.conversionItems,
                                draggedItemID: $draggedConversionItemID
                            )
                        )
                        .itemSelectionOutline(isSelected: model.selectedConversionItemIDs.contains(item.id))
                    }
                }
                .listStyle(.inset)
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
                Label("Convert", systemImage: "doc.text")
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
}

private struct ConversionItemDragPreview: View {
    let item: WorkspacePDF

    var body: some View {
        PDFFileRow(
            item: .constant(item),
            actions: PDFFileRowActions(
                canMoveUp: false,
                canMoveDown: false,
                moveUp: {},
                moveDown: {},
                remove: {},
                revealInFinder: {}
            )
        )
        .frame(width: 360, height: PDFFileRow.baseHeight)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ConversionItemDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var items: [WorkspacePDF]
    @Binding var draggedItemID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == draggedItemID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation {
            items.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
