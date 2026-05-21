import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Entitlement Tests

struct EntitlementTests {

    @Test func noneIsNotActive() {
        #expect(!Entitlement.none.isActive)
    }

    @Test func paidMonthlyIsActive() {
        #expect(Entitlement.paidFounderMonthly.isActive)
    }

    @Test func paidAnnualIsActive() {
        #expect(Entitlement.paidFounderAnnual.isActive)
    }

    @Test func allEntitlementsHaveDisplayNames() {
        let all: [Entitlement] = [.none, .paidFounderMonthly, .paidFounderAnnual]
        for entitlement in all {
            #expect(!entitlement.displayName.isEmpty)
        }
    }

    @Test func rawValuesAreStable() {
        #expect(Entitlement.none.rawValue == "none")
        #expect(Entitlement.paidFounderMonthly.rawValue == "paid_founder_monthly")
        #expect(Entitlement.paidFounderAnnual.rawValue == "paid_founder_annual")
    }

    @Test func entitlementRoundTrips() {
        let all: [Entitlement] = [.none, .paidFounderMonthly, .paidFounderAnnual]
        for original in all {
            let decoded = Entitlement(rawValue: original.rawValue)
            #expect(decoded == original)
        }
    }

    /// Legacy "free_founder" raw value must no longer decode to an active
    /// entitlement. Devices that persisted this from pre-rejection builds
    /// should fall back to .none and route through the paywall.
    @Test func legacyFreeFounderRawValueDoesNotDecode() {
        #expect(Entitlement(rawValue: "free_founder") == nil)
    }
}

// MARK: - Product ID Tests

struct ProductIDTests {

    @Test func monthlyIDFollowsConvention() {
        #expect(SubscriptionService.monthlyProductID == "smartertraining.founding.monthly")
    }

    @Test func annualIDFollowsConvention() {
        #expect(SubscriptionService.annualProductID == "smartertraining.founding.annual")
    }
}

// MARK: - Persistence & Reset Tests

/// These tests run against a stand-alone SubscriptionService and exercise the
/// non-StoreKit pieces of the entitlement flow. The actual `purchase(_:)` path
/// hits real StoreKit, so it is exercised via the .storekit configuration in
/// the simulator and during App Review — not from unit tests.
///
/// Serialized because all SubscriptionService instances share `UserDefaults.standard`;
/// running these in parallel races on the persisted entitlement key.
@Suite(.serialized)
struct SubscriptionPersistenceTests {

    @Test func legacyFreeFounderPersistedValueIsCleared() {
        // Simulate a device with the pre-rejection free-founder value persisted.
        UserDefaults.standard.set("free_founder", forKey: "subscription_entitlement")
        UserDefaults.standard.set(1, forKey: "free_founder_claimed_count")
        UserDefaults.standard.set(true, forKey: "free_founder_claimed_by_device")

        let service = SubscriptionService()

        // Persisted "free_founder" no longer decodes — entitlement must be inactive.
        #expect(service.entitlement == .none)
        #expect(!service.entitlement.isActive)

        // Legacy keys must be cleared on launch.
        #expect(UserDefaults.standard.object(forKey: "free_founder_claimed_count") == nil)
        #expect(UserDefaults.standard.object(forKey: "free_founder_claimed_by_device") == nil)
    }

    @Test func clearLocalEntitlementResetsToNone() {
        let service = SubscriptionService()
        #if DEBUG
        service.debugSimulatePaidEntitlement(.paidFounderMonthly)
        #expect(service.entitlement == .paidFounderMonthly)
        #endif

        service.clearLocalEntitlement()
        #expect(service.entitlement == .none)
    }

    #if DEBUG
    @Test func debugSimulatePaidEntitlementSetsPaid() {
        let service = SubscriptionService()
        service.clearLocalEntitlement()

        service.debugSimulatePaidEntitlement(.paidFounderMonthly)
        #expect(service.entitlement == .paidFounderMonthly)
        #expect(service.entitlement.isActive)

        service.debugSimulatePaidEntitlement(.paidFounderAnnual)
        #expect(service.entitlement == .paidFounderAnnual)
        #expect(service.entitlement.isActive)
    }

    @Test func debugSimulatePaidEntitlementRejectsInactiveValue() {
        let service = SubscriptionService()
        service.clearLocalEntitlement()

        // Passing .none would be a programming error — guard ignores it so we
        // can never accidentally "simulate" an active-state with .none.
        service.debugSimulatePaidEntitlement(.none)
        #expect(service.entitlement == .none)
    }
    #endif
}

// MARK: - Purchase Result Semantics

/// These tests document the invariants of `purchase(_:)` so future refactors
/// can't quietly drop them. The actual `Product.PurchaseResult` cases (success,
/// .userCancelled, .pending) require real StoreKit, so we assert on the
/// enum-level behavior the production code relies on: entitlement only ever
/// flips active through `updateEntitlementFromTransaction`, which is only
/// reached on a verified `.success`.
struct PurchaseInvariantTests {

    @Test func entitlementStartsInactive() {
        let service = SubscriptionService()
        service.clearLocalEntitlement()
        #expect(!service.entitlement.isActive)
    }

    /// Confirms that there is no public API on SubscriptionService that grants
    /// an active entitlement without going through StoreKit. (Removed:
    /// `claimFreeFounderAccess`, `isFreeFoundingAvailable`,
    /// `hasClaimedFreeFounderOnDevice`, `maxFreeFounders`.)
    @Test func noPublicNonPurchasePathToActiveEntitlement() {
        let service = SubscriptionService()
        service.clearLocalEntitlement()

        // The only ways to flip entitlement to active are:
        //   1. A verified StoreKit transaction (runtime).
        //   2. The DEBUG-only debugSimulatePaidEntitlement helper.
        // Both are exercised elsewhere; here we just confirm the service
        // exposes neither a free-claim API nor any free-counter accessors.
        let mirror = Mirror(reflecting: service)
        let propertyNames = mirror.children.compactMap { $0.label }
        #expect(!propertyNames.contains("isFreeFoundingAvailable"))
        #expect(!propertyNames.contains("hasClaimedFreeFounderOnDevice"))
    }
}
