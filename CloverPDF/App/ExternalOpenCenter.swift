import Foundation

@MainActor
final class ExternalOpenCenter {
    static let shared = ExternalOpenCenter()
    var handler: (([URL]) -> Void)?
    private init() {}
}
