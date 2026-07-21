import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        guard let window = sender.windows.first(where: { !$0.isVisible && $0.canBecomeMain }) else {
            return true
        }
        window.makeKeyAndOrderFront(nil)
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }
        Task { @MainActor in
            ExternalOpenCenter.shared.handler?(pdfURLs)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
