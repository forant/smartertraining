import Foundation
import Observation
import StoreKit

enum Entitlement: String, Codable, Equatable {
    case none
    case freeFounder = "free_founder"
    case paidFounderMonthly = "paid_founder_monthly"
    case paidFounderAnnual = "paid_founder_annual"

    var isActive: Bool { self != .none }

    var displayName: String {
        switch self {
        case .none: "None"
        case .freeFounder: "Founding Athlete"
        case .paidFounderMonthly: "Founding Supporter (Monthly)"
        case .paidFounderAnnual: "Founding Supporter (Annual)"
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

    private var transactionListener: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let entitlement = "subscription_entitlement"
        static let freeFounderClaimedCount = "free_founder_claimed_count"
        static let freeFounderClaimedByThisDevice = "free_founder_claimed_by_device"
    }

    static let maxFreeFounders = 100

    init() {
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

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(for: [
                Self.monthlyProductID,
                Self.annualProductID
            ])
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            ErrorLogger.log(.subscription, message: error.localizedDescription, subsystem: "storekit")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlementFromTransaction(transaction)
                await transaction.finish()
                return true

            case .userCancelled:
                AnalyticsService.shared.track(.purchaseCancelled, properties: [
                    "product": product.id
                ])
                return false

            case .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
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
        do {
            try await AppStore.sync()
            await resolveEntitlementFromStore()
        } catch {
            purchaseError = error.localizedDescription
            AnalyticsService.shared.track(.restoreFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.subscription, message: error.localizedDescription, subsystem: "storekit")
        }
    }

    // MARK: - Free Founding Access

    var isFreeFoundingAvailable: Bool {
        // TODO: Replace with backend-enforced global count before broader launch.
        // Local count is per-device only and does not prevent >100 claims across devices.
        let claimed = defaults.integer(forKey: Keys.freeFounderClaimedCount)
        return claimed < Self.maxFreeFounders
    }

    var hasClaimedFreeFounderOnDevice: Bool {
        defaults.bool(forKey: Keys.freeFounderClaimedByThisDevice)
    }

    func claimFreeFounderAccess() {
        let currentCount = defaults.integer(forKey: Keys.freeFounderClaimedCount)
        defaults.set(currentCount + 1, forKey: Keys.freeFounderClaimedCount)
        defaults.set(true, forKey: Keys.freeFounderClaimedByThisDevice)
        entitlement = .freeFounder
        persistEntitlement()
    }

    // MARK: - Entitlement Resolution

    func resolveEntitlement() async {
        await resolveEntitlementFromStore()

        if entitlement == .none && hasClaimedFreeFounderOnDevice {
            entitlement = .freeFounder
            persistEntitlement()
        }

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

        if foundEntitlement != .none {
            entitlement = foundEntitlement
            persistEntitlement()
        } else if entitlement == .freeFounder {
            // Keep free founder if no paid subscription found
        } else {
            entitlement = .none
            persistEntitlement()
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self, let transaction = try? self.checkVerified(result) else { continue }
                await self.updateEntitlementFromTransaction(transaction)
                await transaction.finish()
            }
        }
    }

    @MainActor
    private func updateEntitlementFromTransaction(_ transaction: StoreKit.Transaction) {
        if transaction.revocationDate != nil {
            if entitlement != .freeFounder {
                entitlement = .none
                persistEntitlement()
            }
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Persistence

    private func loadPersistedEntitlement() {
        if let raw = defaults.string(forKey: Keys.entitlement),
           let saved = Entitlement(rawValue: raw) {
            entitlement = saved
        }
    }

    private func persistEntitlement() {
        defaults.set(entitlement.rawValue, forKey: Keys.entitlement)
    }

    func clearLocalEntitlement() {
        entitlement = .none
        defaults.removeObject(forKey: Keys.entitlement)
        defaults.removeObject(forKey: Keys.freeFounderClaimedByThisDevice)
    }

    // MARK: - Debug

    #if DEBUG
    func debugResetEntitlement() {
        entitlement = .none
        defaults.removeObject(forKey: Keys.entitlement)
        defaults.removeObject(forKey: Keys.freeFounderClaimedByThisDevice)
        defaults.set(0, forKey: Keys.freeFounderClaimedCount)
    }

    func debugSimulateFounderClaimed() {
        claimFreeFounderAccess()
    }

    func debugSetFounderCountFull() {
        defaults.set(Self.maxFreeFounders, forKey: Keys.freeFounderClaimedCount)
    }

    func debugSetFounderCountAvailable() {
        defaults.set(0, forKey: Keys.freeFounderClaimedCount)
    }
    #endif
}
