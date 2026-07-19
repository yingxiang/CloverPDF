import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isSidebarVisible = true
    @State private var confirmsClearFinishedTasks = false

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                List(AppSection.allCases, selection: $model.selection) { section in
                    sidebarLabel(for: section)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .frame(width: 210)
                .fixedSize(horizontal: true, vertical: false)

                Divider()
            }

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
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Label(sidebarButtonTitle, systemImage: "sidebar.left")
                        .labelStyle(.iconOnly)
                }
                .help(Text(sidebarButtonTitle))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.selection == .merge || model.selection == .convert {
                    Button {
                        model.importPDFs(FilePanel.openPDFs(), destination: model.selection)
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
                        confirmsClearFinishedTasks = true
                    } label: {
                        Label("Clear Finished", systemImage: "trash")
                    }
                    .disabled(!model.tasks.contains { terminalTaskStates.contains($0.state) })
                }
            }
        }
        .onAppear { updateWindowTitle() }
        .onChange(of: model.selection) { _ in updateWindowTitle() }
        .alert("Delete Finished Tasks", isPresented: $confirmsClearFinishedTasks) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.clearFinishedTasks()
            }
        } message: {
            Text("Delete all finished tasks?")
        }
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
        switch model.selection {
        case .merge: model.mergeItems.isEmpty
        case .convert: model.conversionItems.isEmpty
        case .tasks, .settings: true
        }
    }

    @ViewBuilder
    private func sidebarLabel(for section: AppSection) -> some View {
        if let tip = section.localizedTip {
            Label(section.localizedTitle, systemImage: section.icon)
                .help(tip)
        } else {
            Label(section.localizedTitle, systemImage: section.icon)
        }
    }

    private var terminalTaskStates: Set<ProcessingTaskState> {
        [.succeeded, .failed, .cancelled, .interrupted]
    }

    private var sidebarButtonTitle: LocalizedStringKey {
        isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    private func updateWindowTitle() {
        let title = model.selection.localizedTitle
        DispatchQueue.main.async { NSApp.keyWindow?.title = title }
    }
}

private extension AppSection {
    var localizedTitle: String {
        switch self {
        case .merge: String(localized: "Merge")
        case .convert: String(localized: "Convert")
        case .tasks: String(localized: "Tasks")
        case .settings: String(localized: "Settings")
        }
    }

    var localizedTip: String? {
        switch self {
        case .merge:
            String(localized: "Merge as PNG, JPG, PDF, or Word files")
        case .convert:
            String(localized: "Export PNG, JPG, PDF, or Word files")
        case .tasks, .settings:
            nil
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
