import SwiftUI

struct ConvertView: View {
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
        .acceptsPDFDrops { model.importPDFs($0, destination: .convert) }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if model.conversionItems.isEmpty {
                EmptyPDFState(title: "No PDFs selected", icon: "doc.badge.plus") {
                    model.importPDFs(FilePanel.openPDFs(), destination: .convert)
                }
            } else {
                List(selection: $model.selectedConversionItemIDs) {
                    ForEach($model.conversionItems) { $item in
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
                        .tag(item.id)
                    }
                    .onMove { offsets, destination in
                        model.conversionItems.move(fromOffsets: offsets, toOffset: destination)
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
            Toggle("Page Range", isOn: $model.pageRangeEnabled)
            if model.pageRangeEnabled {
                Stepper("Start: \(model.startPage)", value: $model.startPage, in: 1...99999)
                    .fixedSize()
                Stepper("End: \(model.endPage)", value: $model.endPage, in: model.startPage...99999)
                    .fixedSize()
            }
            Spacer()
            if !model.purchaseService.isPremiumUnlocked && model.conversionItems.count > 1 {
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
            .disabled(model.conversionItems.isEmpty || (model.pageRangeEnabled && model.endPage < model.startPage))
        }
        .padding(16)
    }

    private var selectedItem: WorkspacePDF? {
        model.conversionItems.first { model.selectedConversionItemIDs.contains($0.id) }
    }

    private func contextSelection(for id: UUID) -> Set<UUID> {
        model.selectedConversionItemIDs.contains(id) ? model.selectedConversionItemIDs : [id]
    }
}
