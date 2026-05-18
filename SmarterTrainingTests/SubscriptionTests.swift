import Testing
@testable import SmarterTraining

// MARK: - Entitlement Tests

struct EntitlementTests {

    @Test func noneIsNotActive() {
        #expect(!Entitlement.none.isActive)
    }

    @Test func freeFounderIsActive() {
        #expect(Entitlement.freeFounder.isActive)
    }

    @Test func paidMonthlyIsActive() {
        #expect(Entitlement.paidFounderMonthly.isActive)
    }

    @Test func paidAnnualIsActive() {
        #expect(Entitlement.paidFounderAnnual.isActive)
    }

    @Test func allEntitlementsHaveDisplayNames() {
        let all: [Entitlement] = [.none, .freeFounder, .paidFounderMonthly, .paidFounderAnnual]
        for entitlement in all {
            #expect(!entitlement.displayName.isEmpty)
        }
    }

    @Test func rawValuesAreStable() {
        #expect(Entitlement.none.rawValue == "none")
        #expect(Entitlement.freeFounder.rawValue == "free_founder")
        #expect(Entitlement.paidFounderMonthly.rawValue == "paid_founder_monthly")
        #expect(Entitlement.paidFounderAnnual.rawValue == "paid_founder_annual")
    }

    @Test func entitlementRoundTrips() {
        let all: [Entitlement] = [.none, .freeFounder, .paidFounderMonthly, .paidFounderAnnual]
        for original in all {
            let decoded = Entitlement(rawValue: original.rawValue)
            #expect(decoded == original)
        }
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

    @Test func maxFreeFoundersIsReasonable() {
        #expect(SubscriptionService.maxFreeFounders == 100)
    }
}
