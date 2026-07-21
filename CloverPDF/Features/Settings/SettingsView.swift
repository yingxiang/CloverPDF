import SwiftUI

struct SettingsView: View {
    @AppStorage(OCRSettings.enabledKey) private var isOCREnabled = true

    var body: some View {
        Form {
            Section("Conversion") {
                Toggle("OCR scanned documents", isOn: $isOCREnabled)
            }
            Section("About") {
                LabeledContent("Application") { Text("WPDF") }
                LabeledContent("Version") { Text(appVersion) }
                LabeledContent("Privacy") {
                    Link("Privacy", destination: WPDFLinks.privacyPolicy)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
}
