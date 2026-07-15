import AppKit
import Combine
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {
    static let product3Months = "com.lingchen.cloverpdf.subscription.3months"
    static let product6Months = "com.lingchen.cloverpdf.subscription.6months"
    static let product12Months = "com.lingchen.cloverpdf.subscription.12months"
    static let lifetimeProduct = "com.lingchen.cloverpdf.lifetime"

    let manager: MacPurchaseManager
    private var cancellable: AnyCancellable?

    init() {
        manager = MacPurchaseManager(configuration: MacPurchaseConfiguration(
            productOrder: [
                Self.lifetimeProduct,
                Self.product12Months,
                Self.product6Months,
                Self.product3Months,
            ],
            lifetimeProductID: Self.lifetimeProduct
        ))
        cancellable = manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isPremiumUnlocked: Bool { manager.isUnlocked }

    func start() {
        manager.start()
    }
}

@MainActor
final class CloverPaywallCoordinator {
    private let purchaseService: PurchaseService
    private var presenter: MacPaywallPresenter?

    init(purchaseService: PurchaseService) {
        self.purchaseService = purchaseService
    }

    func show(sourceView: NSView? = nil) {
        let manager = purchaseService.manager
        let presenter = MacPaywallPresenter(
            configuration: MacPaywallConfiguration(
                title: String(localized: "Unlock CloverPDF Premium"),
                unlockedTitle: String(localized: "CloverPDF Premium is active"),
                failureTitle: String(localized: "Purchase Failed"),
                emptyProductsMessage: String(localized: "Products are temporarily unavailable. Please try again later."),
                benefits: [
                    String(localized: "Unlimited PDF to Word conversion"),
                    String(localized: "Batch conversion"),
                    String(localized: "Full task history and retry"),
                    String(localized: "Future premium PDF tools"),
                ],
                privacyPolicyURL: URL(string: "https://yingxiang.github.io/cloverpdf/privacy.html")!,
                termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
            ),
            productsProvider: {
                await manager.loadProducts()
                return manager.products.map { product in
                    MacPaywallProduct(
                        productID: product.id,
                        title: Self.title(for: product.id),
                        subtitle: Self.subtitle(for: product.id),
                        currentPrice: product.displayPrice,
                        badge: product.id == PurchaseService.lifetimeProduct ? String(localized: "Best value") : nil,
                        isEnabled: !manager.activeProductIDs.contains(product.id)
                    )
                }
            },
            isUnlocked: { manager.isUnlocked },
            purchaseHandler: { productID, window in
                try await manager.purchase(productID: productID, confirmIn: window)
            },
            restoreHandler: {
                try await AppStore.sync()
                await manager.refreshEntitlements(force: true)
                return manager.isUnlocked
            }
        )
        self.presenter = presenter
        presenter.show(sourceWindowToHide: sourceView?.window)
    }

    private static func title(for productID: String) -> String {
        switch productID {
        case PurchaseService.product3Months: String(localized: "3-Month Subscription")
        case PurchaseService.product6Months: String(localized: "6-Month Subscription")
        case PurchaseService.product12Months: String(localized: "1-Year Subscription")
        case PurchaseService.lifetimeProduct: String(localized: "Lifetime Unlock")
        default: productID
        }
    }

    private static func subtitle(for productID: String) -> String? {
        productID == PurchaseService.lifetimeProduct
            ? String(localized: "One purchase, permanent access")
            : String(localized: "Auto-renewable subscription")
    }
}
