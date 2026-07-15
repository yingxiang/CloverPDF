import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
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
}

private extension AppSection {
    var title: LocalizedStringKey {
        switch self {
        case .merge: "Merge PDFs"
        case .convert: "PDF to Word"
        case .tasks: "Tasks"
        case .settings: "Settings"
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
