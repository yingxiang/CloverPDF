import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Premium") {
                LabeledContent("Status") {
                    Text(model.purchaseService.isPremiumUnlocked ? String(localized: "Premium Active") : String(localized: "Free"))
                }
                if !model.purchaseService.isPremiumUnlocked {
                    LabeledContent("Free Conversions") {
                        Text(model.remainingTrialConversions.formatted())
                    }
                    Button("Unlock Premium") {
                        model.paywallCoordinator.show(sourceView: NSApp.keyWindow?.contentView)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section("Output") {
                LabeledContent("Default Folder") {
                    Button(model.outputDirectory.path(percentEncoded: false)) {
                        model.outputDirectory = FilePanel.chooseDirectory(current: model.outputDirectory) ?? model.outputDirectory
                    }
                }
            }
            Section("About") {
                LabeledContent("Application") { Text("CloverPDF") }
                LabeledContent("Privacy") { Text("Files stay on this Mac") }
                LabeledContent("PDF to Word Engine") { Text("pdf2docx") }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
