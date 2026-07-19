import AppKit
import Combine
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {
    static let product3Months = "pdf_buy_three_month"
    static let product6Months = "pdf_buy_six_month"
    static let product12Months = "pdf_buy_one_year"
    static let lifetimeProduct = "com.lingchen.pdf.unlockall"

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
            lifetimeProductID: Self.lifetimeProduct,
            plans: [
                MacPurchasePlan(
                    productID: Self.product12Months,
                    durationMonths: 12,
                    originalPriceMultiplier: 2
                ),
                MacPurchasePlan(
                    productID: Self.product6Months,
                    durationMonths: 6,
                    originalPriceMultiplier: 2
                ),
                MacPurchasePlan(
                    productID: Self.product3Months,
                    durationMonths: 3,
                    originalPriceMultiplier: 3
                ),
            ]
        ))
        cancellable = manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isPremiumUnlocked: Bool { manager.isUnlocked }
    var isLifetimeUnlocked: Bool { manager.activeProductIDs.contains(Self.lifetimeProduct) }

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
                return Self.purchaseProducts(from: manager)
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
        // Keep CloverPDF visible behind the purchase sheet. The shared presenter
        // hides this window when it is supplied, which makes sandbox checkout
        // appear to close the app when the payment sheet changes focus.
        presenter.show(sourceWindowToHide: nil)
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

    private static func purchaseProducts(from manager: MacPurchaseManager) -> [MacPaywallProduct] {
        var products: [MacPaywallProduct] = []
        if let lifetime = manager.products.first(where: { $0.id == PurchaseService.lifetimeProduct }) {
            products.append(MacPaywallProduct(
                productID: lifetime.id,
                title: title(for: lifetime.id),
                subtitle: subtitle(for: lifetime.id),
                originalPrice: manager.originalDisplayPrice(for: lifetime.id, multiplier: 2),
                currentPrice: lifetime.displayPrice,
                badge: String(localized: "Best value"),
                isEnabled: !manager.activeProductIDs.contains(lifetime.id)
            ))
        }
        for productID in [
            PurchaseService.product12Months,
            PurchaseService.product6Months,
            PurchaseService.product3Months,
        ] {
            guard let product = manager.products.first(where: { $0.id == productID }) else { continue }
            let plan = manager.configuration.plans.first { $0.productID == productID }
            let multiplier = originalPriceMultiplier(
                for: product,
                manager: manager,
                plan: plan
            )
            products.append(MacPaywallProduct(
                productID: product.id,
                title: title(for: product.id),
                subtitle: subtitle(for: product.id),
                originalPrice: plan.flatMap { _ in
                    manager.originalDisplayPrice(for: product.id, multiplier: multiplier)
                },
                currentPrice: product.displayPrice,
                badge: badge(for: product.id),
                isEnabled: !manager.activeProductIDs.contains(product.id)
            ))
        }
        return products
    }

    private static func badge(for productID: String) -> String {
        switch productID {
        case PurchaseService.product12Months:
            String(localized: "Economical")
        case PurchaseService.product6Months, PurchaseService.product3Months:
            String(localized: "Limited-time discount")
        default:
            ""
        }
    }

    private static func originalPriceMultiplier(
        for product: Product,
        manager: MacPurchaseManager,
        plan: MacPurchasePlan?
    ) -> Decimal {
        guard product.id == PurchaseService.product3Months,
              let sixMonthProduct = manager.products.first(where: {
                  $0.id == PurchaseService.product6Months
              }) else {
            return plan?.originalPriceMultiplier ?? 1
        }
        let threeMonthAtThree = (product.price as NSDecimalNumber)
            .multiplying(by: 3)
        let sixMonthAtTwo = (sixMonthProduct.price as NSDecimalNumber)
            .multiplying(by: 2)
        return threeMonthAtThree.compare(sixMonthAtTwo) == .orderedDescending ? 2 : 3
    }
}
