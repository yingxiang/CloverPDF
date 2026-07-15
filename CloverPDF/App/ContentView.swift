import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            List(AppSection.allCases, selection: $model.selection) { section in
                Label(section.localizedTitle, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 210)
            .fixedSize(horizontal: true, vertical: false)

            Divider()

            Group {
                switch model.selection {
                case .merge:
                    MergeView()
                case .convert:
                    ConvertView()
                case .tasks:
                    TasksView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .navigationTitle(model.selection.localizedTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.selection == .merge || model.selection == .convert {
                    Button {
                        let destination: AppSection = model.selection == .convert ? .convert : .merge
                        model.importPDFs(FilePanel.openPDFs(), destination: destination)
                    } label: {
                        Label("Add PDF", systemImage: "doc.badge.plus")
                    }
                    .help("Add PDF")

                    Button {
                        if model.selection == .merge {
                            model.clearMergeItems()
                        } else {
                            model.clearConversionItems()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear")
                    .disabled(currentPDFItemsAreEmpty)
                } else if model.selection == .tasks {
                    Button {
                        model.clearFinishedTasks()
                    } label: {
                        Label("Clear Finished", systemImage: "trash")
                    }
                    .disabled(!model.tasks.contains { terminalTaskStates.contains($0.state) })
                }
            }
        }
        .onAppear { updateWindowTitle() }
        .onChange(of: model.selection) { _ in updateWindowTitle() }
        .sheet(item: $model.previewItem) { item in
            PDFPreviewSheet(item: item)
                .environmentObject(model)
        }
        .alert(
            String(localized: "CloverPDF"),
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var currentPDFItemsAreEmpty: Bool {
        model.selection == .merge ? model.mergeItems.isEmpty : model.conversionItems.isEmpty
    }

    private var terminalTaskStates: Set<ProcessingTaskState> {
        [.succeeded, .failed, .cancelled, .interrupted]
    }

    private func updateWindowTitle() {
        let title = model.selection.localizedTitle
        DispatchQueue.main.async { NSApp.keyWindow?.title = title }
    }
}

private extension AppSection {
    var localizedTitle: String {
        switch self {
        case .merge: String(localized: "Merge PDFs")
        case .convert: String(localized: "PDF to Word")
        case .tasks: String(localized: "Tasks")
        case .settings: String(localized: "Settings")
        }
    }

    var icon: String {
        switch self {
        case .merge: "square.stack.3d.up"
        case .convert: "doc.text"
        case .tasks: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}
