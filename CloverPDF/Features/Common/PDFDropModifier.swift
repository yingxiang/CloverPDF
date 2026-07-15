import SwiftUI
import UniformTypeIdentifiers

struct PDFDropModifier: ViewModifier {
    let action: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                          let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "pdf" else {
                        continue
                    }
                    urls.append(url)
                }
                await MainActor.run { action(urls) }
            }
            return true
        }
    }
}

extension View {
    func acceptsPDFDrops(action: @escaping ([URL]) -> Void) -> some View {
        modifier(PDFDropModifier(action: action))
    }
}
