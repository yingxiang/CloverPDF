import SwiftUI

@main
struct CloverPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add PDFs") {
                    model.importPDFs(FilePanel.openPDFs(), destination: model.selection == .convert ? .convert : .merge)
                }
                .keyboardShortcut("o")
            }
        }
    }
}
