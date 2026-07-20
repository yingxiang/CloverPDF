import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(OCRSettings.enabledKey) private var isOCREnabled = true

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
                }
                if !model.purchaseService.isLifetimeUnlocked {
                    Button {
                        model.paywallCoordinator.show(sourceView: NSApp.keyWindow?.contentView)
                    } label: {
                        Text(model.purchaseService.isPremiumUnlocked
                            ? String(localized: "Premium Purchased")
                            : String(localized: "Unlock Premium"))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section("Conversion") {
                Toggle("OCR scanned documents", isOn: $isOCREnabled)
            }
            Section("About") {
                LabeledContent("Application") { Text("WPDF") }
                LabeledContent("Version") { Text(appVersion) }
                LabeledContent("Privacy") { Text("Files stay on this Mac") }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
}
