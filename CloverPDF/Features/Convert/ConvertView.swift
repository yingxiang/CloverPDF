import SwiftUI

struct ConvertView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if model.conversionItems.isEmpty {
                    EmptyPDFState(title: "No PDFs selected", icon: "doc.badge.plus")
                } else {
                    List {
                        ForEach(Array(model.conversionItems.indices), id: \.self) { index in
                            PDFFileRow(
                                item: $model.conversionItems[index],
                                index: index,
                                count: model.conversionItems.count,
                                moveUp: { move(index, offset: -1) },
                                moveDown: { move(index, offset: 1) },
                                remove: { model.conversionItems.remove(at: index) }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            options
        }
        .acceptsPDFDrops { model.importPDFs($0, destination: .convert) }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PDF to Word").font(.title2).fontWeight(.semibold)
                Text("\(model.remainingTrialConversions) free conversions remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.importPDFs(FilePanel.openPDFs(), destination: .convert)
            } label: {
                Label("Add PDFs", systemImage: "plus")
            }
            Button {
                model.conversionItems.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear")
            .disabled(model.conversionItems.isEmpty)
        }
        .padding(16)
    }

    private var options: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Page Range", isOn: $model.pageRangeEnabled)
                if model.pageRangeEnabled {
                    Stepper("Start: \(model.startPage)", value: $model.startPage, in: 1...99999)
                        .fixedSize()
                    Stepper("End: \(model.endPage)", value: $model.endPage, in: model.startPage...99999)
                        .fixedSize()
                }
                Spacer()
            }
            HStack {
                Button {
                    model.outputDirectory = FilePanel.chooseDirectory(current: model.outputDirectory) ?? model.outputDirectory
                } label: {
                    Label(model.outputDirectory.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
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
        }
        .padding(16)
    }

    private func move(_ index: Int, offset: Int) {
        let destination = index + offset
        guard model.conversionItems.indices.contains(destination) else { return }
        model.conversionItems.swapAt(index, destination)
    }
}
