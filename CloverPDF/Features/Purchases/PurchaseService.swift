import AppKit
import Combine
import Security
import StoreKit

enum WPDFLinks {
    static let privacyPolicy = URL(string: "https://yingxiang.github.io/web/wpdf/privacy.html")!
}

struct WPDFPromotionTrialState {
    let startDate: Date
    let expirationDate: Date

    var remainingDays: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return max(0, remaining + 1)
    }

    var isActive: Bool { Date() < expirationDate }
}

enum WPDFPromotionTrialPolicy {
    static let duration: TimeInterval = 3 * 24 * 60 * 60

    static func startDate(
        storedStartDate: Date?,
        isCloverInstalled: Bool,
        isMapleInstalled: Bool,
        now: Date
    ) -> Date? {
        if let storedStartDate { return storedStartDate }
        return isCloverInstalled || isMapleInstalled ? now : nil
    }

    static func state(startDate: Date) -> WPDFPromotionTrialState {
        WPDFPromotionTrialState(
            startDate: startDate,
            expirationDate: startDate.addingTimeInterval(duration)
        )
    }

    static func isEntitled(
        storedStartDate: Date?,
        hasClaimedInstalledApp: Bool,
        now: Date
    ) -> Bool {
        guard let storedStartDate, hasClaimedInstalledApp else { return false }
        return now < storedStartDate.addingTimeInterval(duration)
    }
}

final class WPDFPromotionTrialService {
    static let cloverBundleIdentifier = "com.lingchen.clover"
    static let mapleBundleIdentifier = "com.lingchen.omnicapture"
    private let service = "com.lingchen.pdf.cross-promotion"
    private let account = "companion-trial-start"
    private let claimedAppsAccount = "companion-trial-claimed-apps"

    var isCloverInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cloverBundleIdentifier) != nil
    }

    var isMapleInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.mapleBundleIdentifier) != nil
    }

    var trialState: WPDFPromotionTrialState? {
        guard let startDate = storedStartDate else { return nil }
        return WPDFPromotionTrialPolicy.state(startDate: startDate)
    }

    var isTrialActive: Bool {
        let installedApps = installedBundleIdentifiers
        let claimedApps = claimedBundleIdentifiers
        return WPDFPromotionTrialPolicy.isEntitled(
            storedStartDate: storedStartDate,
            hasClaimedInstalledApp: !installedApps.isDisjoint(with: claimedApps),
            now: Date()
        )
    }

    func isInstalled(_ bundleIdentifier: String) -> Bool {
        installedBundleIdentifiers.contains(bundleIdentifier)
    }

    func isClaimed(_ bundleIdentifier: String) -> Bool {
        claimedBundleIdentifiers.contains(bundleIdentifier)
    }

    @discardableResult
    func claimTrialIfEligible() -> WPDFPromotionTrialState? {
        let now = Date()
        let existingStartDate = storedStartDate
        let installedApps = installedBundleIdentifiers
        guard let startDate = WPDFPromotionTrialPolicy.startDate(
            storedStartDate: existingStartDate,
            isCloverInstalled: installedApps.contains(Self.cloverBundleIdentifier),
            isMapleInstalled: installedApps.contains(Self.mapleBundleIdentifier),
            now: now
        ) else { return nil }
        if existingStartDate == nil {
            saveStartDate(startDate)
        }
        let existingClaimedApps = claimedBundleIdentifiers
        let claimedApps = existingClaimedApps.union(installedApps)
        if claimedApps != existingClaimedApps {
            saveClaimedBundleIdentifiers(claimedApps)
        }
        return WPDFPromotionTrialPolicy.state(startDate: startDate)
    }

    private var installedBundleIdentifiers: Set<String> {
        var identifiers = Set<String>()
        if isCloverInstalled { identifiers.insert(Self.cloverBundleIdentifier) }
        if isMapleInstalled { identifiers.insert(Self.mapleBundleIdentifier) }
        return identifiers
    }

    private var storedStartDate: Date? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              let interval = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func saveStartDate(_ date: Date) {
        let data = String(date.timeIntervalSince1970).data(using: .utf8) ?? Data()
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var item = baseQuery(account: account)
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private var claimedBundleIdentifiers: Set<String> {
        var query = baseQuery(account: claimedAppsAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let identifiers = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return identifiers
    }

    private func saveClaimedBundleIdentifiers(_ identifiers: Set<String>) {
        guard let data = try? JSONEncoder().encode(identifiers) else { return }
        SecItemDelete(baseQuery(account: claimedAppsAccount) as CFDictionary)
        var item = baseQuery(account: claimedAppsAccount)
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }
}

@MainActor
final class PurchaseService: ObservableObject {
    static let product3Months = "pdf_buy_three_month"
    static let product6Months = "pdf_buy_six_month"
    static let product12Months = "pdf_buy_one_year"
    static let lifetimeProduct = "com.lingchen.pdf.unlockall"

    let manager: MacPurchaseManager
    private let promotionTrialService = WPDFPromotionTrialService()
    private var cancellables = Set<AnyCancellable>()

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
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                if !Self.isRunningTests {
                    self?.refreshPromotionTrial()
                }
            }
            .store(in: &cancellables)
    }

    var isPremiumUnlocked: Bool { manager.isUnlocked || promotionTrialService.isTrialActive }
    var isPurchasedPremiumUnlocked: Bool { manager.isUnlocked }
    var isLifetimeUnlocked: Bool { manager.activeProductIDs.contains(Self.lifetimeProduct) }
    var promotionTrialState: WPDFPromotionTrialState? { promotionTrialService.trialState }
    var promotionTrialRemainingDays: Int? {
        guard promotionTrialService.isTrialActive,
              let state = promotionTrialState else { return nil }
        return state.remainingDays
    }

    func start() {
        if !Self.isRunningTests {
            refreshPromotionTrial()
        }
        manager.start()
    }

    func refreshPromotionTrial() {
        _ = promotionTrialService.claimTrialIfEligible()
        objectWillChange.send()
    }

    func companionApps() -> [MacPaywallCompanionApp] {
        refreshPromotionTrial()
        return MacPaywallCompanionCatalog.apps().map { definition in
            MacPaywallCompanionApp(
                definition: definition,
                isInstalled: promotionTrialService.isInstalled(definition.bundleIdentifier),
                isClaimed: promotionTrialService.isClaimed(definition.bundleIdentifier),
                trialRemainingDays: promotionTrialRemainingDays,
                action: { NSWorkspace.shared.open(definition.appStoreURL) }
            )
        }
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
            || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            || NSClassFromString("XCTestCase") != nil
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
        purchaseService.refreshPromotionTrial()
        let manager = purchaseService.manager
        let presenter = MacPaywallPresenter(
            configuration: MacPaywallConfiguration(
                title: String(localized: "Unlock WPDF Premium"),
                unlockedTitle: String(localized: "WPDF Premium is active"),
                failureTitle: String(localized: "Purchase Failed"),
                emptyProductsMessage: String(localized: "Products are temporarily unavailable. Please try again later."),
                benefits: [
                    String(localized: "Unlimited PDF to Word conversion"),
                    String(localized: "Batch conversion"),
                    String(localized: "Full task history and retry"),
                    String(localized: "Future premium PDF tools"),
                ],
                privacyPolicyURL: WPDFLinks.privacyPolicy,
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
            },
            companionAppsProvider: { [purchaseService] in
                purchaseService.companionApps()
            }
        )
        self.presenter = presenter
        // Keep WPDF visible behind the purchase sheet. The shared presenter
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
