import Foundation
import Observation
import StoreKit

enum Entitlement: String, Codable, Equatable {
    case none
    case paidFounderMonthly = "paid_founder_monthly"
    case paidFounderAnnual = "paid_founder_annual"

    var isActive: Bool { self != .none }

    var displayName: String {
        switch self {
        case .none: "None"
        case .paidFounderMonthly: "SmarterTraining Monthly"
        case .paidFounderAnnual: "SmarterTraining Annual"
        }
    }
}

@Observable
final class SubscriptionService {

    static let monthlyProductID = "smartertraining.founding.monthly"
    static let annualProductID = "smartertraining.founding.annual"

    private(set) var entitlement: Entitlement = .none
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchaseError: String?
    /// True once the app has finished at least one `loadProducts()` attempt.
    /// Used by the paywall to distinguish "still loading" from "tried and got
    /// zero products" so reviewers can never get stuck on a blank spinner.
    private(set) var didAttemptProductLoad = false
    /// The user-facing reason `loadProducts()` failed, if any. Cleared on the
    /// next successful load.
    private(set) var productLoadError: String?
    /// True if a `restorePurchases()` completed without flipping entitlement
    /// to active. The paywall reads this to surface "No purchases found" so
    /// reviewers don't think the button is broken.
    private(set) var restoreFoundNothing = false

    private var transactionListener: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let entitlement = "subscription_entitlement"
        // Legacy keys cleared on launch to remove any pre-rejection free-founder
        // state that may exist on devices running prior TestFlight builds.
        static let legacyFreeFounderClaimedCount = "free_founder_claimed_count"
        static let legacyFreeFounderClaimedByThisDevice = "free_founder_claimed_by_device"
    }

    init() {
        clearLegacyFreeFounderState()
        loadPersistedEntitlement()
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    /// True if either product advertises an introductory free trial offer.
    var hasIntroductoryTrial: Bool {
        products.contains { product in
            product.subscription?.introductoryOffer?.paymentMode == .freeTrial
        }
    }

    /// Days of free trial available on the given product, if any.
    func introductoryTrialDays(for product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    func loadProducts() async {
        isLoading = true
        defer {
            isLoading = false
            didAttemptProductLoad = true
        }

        do {
            let loaded = try await Product.products(for: [
                Self.monthlyProductID,
                Self.annualProductID
            ])
            products = loaded.sorted { $0.price < $1.price }
            productLoadError = nil
            debugLog("[Products] loaded count=\(products.count)")
        } catch {
            productLoadError = error.localizedDescription
            debugLog("[Products] load failed error=\(error.localizedDescription)")
            ErrorLogger.log(.subscription, message: error.localizedDescription, subsystem: "storekit")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        debugLog("[Purchase] start product=\(product.id)")

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                debugLog("[Purchase] result=success product=\(product.id)")
                let transaction = try checkVerified(verification)
                debugLog("[Purchase] verified product=\(transaction.productID) txId=\(transaction.id)")
                await updateEntitlementFromTransaction(transaction)
                debugLog("[Purchase] entitlement updated to=\(entitlement.rawValue)")
                await transaction.finish()
                return entitlement.isActive

            case .userCancelled:
                debugLog("[Purchase] result=userCancelled product=\(product.id)")
                AnalyticsService.shared.track(.purchaseCancelled, properties: [
                    "product": product.id
                ])
                return false

            case .pending:
                debugLog("[Purchase] result=pending product=\(product.id)")
                return false

            @unknown default:
                debugLog("[Purchase] result=unknown product=\(product.id)")
                return false
            }
        } catch {
            debugLog("[Purchase] error=\(error.localizedDescription) product=\(product.id)")
            purchaseError = error.localizedDescription
            AnalyticsService.shared.track(.purchaseFailed, properties: [
                "product": product.id,
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.subscription, message: error.localizedDescription, subsystem: "storekit")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        debugLog("[Restore] start")
        restoreFoundNothing = false
        do {
            try await AppStore.sync()
            await resolveEntitlementFromStore()
            debugLog("[Restore] resolved entitlement=\(entitlement.rawValue)")
            if !entitlement.isActive {
                restoreFoundNothing = true
            }
        } catch {
            purchaseError = error.localizedDescription
            debugLog("[Restore] error=\(error.localizedDescription)")
            AnalyticsService.shared.track(.restoreFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.subscription, message: error.localizedDescription, subsystem: "storekit")
        }
    }

    // MARK: - Entitlement Resolution

    func resolveEntitlement() async {
        await resolveEntitlementFromStore()
        debugLog("[Resolve] entitlement=\(entitlement.rawValue)")
        AnalyticsService.shared.track(.entitlementResolved, properties: [
            "entitlement": entitlement.rawValue
        ])
    }

    private func resolveEntitlementFromStore() async {
        var foundEntitlement: Entitlement = .none

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.productID == Self.monthlyProductID {
                foundEntitlement = .paidFounderMonthly
            } else if transaction.productID == Self.annualProductID {
                foundEntitlement = .paidFounderAnnual
            }
        }

        entitlement = foundEntitlement
        persistEntitlement()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateEntitlementFromTransaction(transaction)
                    await transaction.finish()
                } catch {
                    // Unverified transactions never grant entitlement. Logging
                    // makes silent failures (e.g., reviewer hitting a flaky
                    // sandbox path) diagnosable instead of invisible.
                    ErrorLogger.log(
                        .subscription,
                        message: "Verification failed in transaction listener: \(error.localizedDescription)",
                        subsystem: "storekit"
                    )
                }
            }
        }
    }

    @MainActor
    private func updateEntitlementFromTransaction(_ transaction: StoreKit.Transaction) {
        if transaction.revocationDate != nil {
            entitlement = .none
            persistEntitlement()
            return
        }

        switch transaction.productID {
        case Self.monthlyProductID:
            entitlement = .paidFounderMonthly
        case Self.annualProductID:
            entitlement = .paidFounderAnnual
        default:
            return
        }
        persistEntitlement()
    }

    // MARK: - Verification

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Persistence

    private func loadPersistedEntitlement() {
        guard let raw = defaults.string(forKey: Keys.entitlement),
              let saved = Entitlement(rawValue: raw) else {
            entitlement = .none
            return
        }
        entitlement = saved
    }

    private func persistEntitlement() {
        defaults.set(entitlement.rawValue, forKey: Keys.entitlement)
    }

    /// Drops any UserDefaults entries written by the pre-rejection free-founder
    /// flow. Safe to call on every launch.
    private func clearLegacyFreeFounderState() {
        defaults.removeObject(forKey: Keys.legacyFreeFounderClaimedCount)
        defaults.removeObject(forKey: Keys.legacyFreeFounderClaimedByThisDevice)
    }

    func clearLocalEntitlement() {
        entitlement = .none
        defaults.removeObject(forKey: Keys.entitlement)
    }

    // MARK: - Logging

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    // MARK: - Debug

    #if DEBUG
    func debugResetEntitlement() {
        entitlement = .none
        defaults.removeObject(forKey: Keys.entitlement)
    }

    /// DEBUG-only helper that simulates an active paid subscription so we can
    /// preview gated UI without going through StoreKit. Compiled out of
    /// release builds.
    func debugSimulatePaidEntitlement(_ entitlement: Entitlement = .paidFounderMonthly) {
        guard entitlement.isActive else { return }
        self.entitlement = entitlement
        persistEntitlement()
    }
    #endif
}
