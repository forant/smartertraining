import SwiftUI
import StoreKit

struct FoundingPaywallView: View {
    @Environment(AppState.self) private var appState
    var subscriptionService: SubscriptionService

    @State private var isPurchasing = false
    @State private var isRestoring = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                tierCards
                footer
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.Surface.background)
        .task {
            await subscriptionService.loadProducts()
            AnalyticsService.shared.track(.paywallViewed)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15))

            HStack(spacing: 0) {
                Text("Smarter")
                    .fontWeight(.regular)
                Text("Training")
                    .fontWeight(.bold)
            }
            .font(.title3)

            Text("Choose your founding access")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Text("The first \(SubscriptionService.maxFreeFounders) athletes get early access to help shape the product. All tiers unlock the full experience.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Tiers

    private var tierCards: some View {
        VStack(spacing: 10) {
            if subscriptionService.isFreeFoundingAvailable {
                freeTierCard
            }

            if let monthly = subscriptionService.monthlyProduct {
                paidTierCard(
                    title: "Founding Supporter",
                    product: monthly,
                    period: "/month",
                    badge: "Popular",
                    benefits: [
                        "Full coaching access",
                        "Support independent development",
                        "Lock in founding pricing"
                    ],
                    cta: "Support monthly"
                ) {
                    await purchaseProduct(monthly, event: .purchaseMonthlyTapped)
                }
            }

            if let annual = subscriptionService.annualProduct {
                paidTierCard(
                    title: "Annual Founding Supporter",
                    product: annual,
                    period: "/year",
                    badge: "Best value",
                    benefits: [
                        "Full coaching access",
                        "Two months free vs. monthly",
                        "Lock in founding pricing"
                    ],
                    cta: "Support yearly"
                ) {
                    await purchaseProduct(annual, event: .purchaseAnnualTapped)
                }
            }

            if subscriptionService.isLoading && subscriptionService.products.isEmpty {
                ProgressView()
                    .padding(.vertical, 16)
            }

            if let error = subscriptionService.purchaseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private var freeTierCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Founding Athlete")
                    .font(.headline)

                Text("Free during early access")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                benefitRow("Full coaching access")
                benefitRow("Help shape SmarterTraining")
            }

            Button {
                claimFreeAccess()
            } label: {
                Text("Claim founding access")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Brand.primary)
        }
        .padding(14)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func paidTierCard(
        title: String,
        product: Product,
        period: String,
        badge: String?,
        benefits: [String],
        cta: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Brand.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Brand.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(benefits, id: \.self) { benefit in
                    benefitRow(benefit)
                }
            }

            Button {
                Task { await action() }
            } label: {
                Text(cta)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Brand.primary)
            .disabled(isPurchasing)
        }
        .padding(14)
        .background(Theme.Surface.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.Border.subtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Brand.primary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Text("All tiers include the full SmarterTraining experience. Subscriptions renew automatically. Manage anytime in Settings \u{2192} Subscriptions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    isRestoring = true
                    AnalyticsService.shared.track(.restoreTapped)
                    await subscriptionService.restorePurchases()
                    if subscriptionService.entitlement.isActive {
                        AnalyticsService.shared.track(.restoreSucceeded, properties: [
                            "entitlement": subscriptionService.entitlement.rawValue
                        ])
                    }
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Restore purchases")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://smartertraining.ai/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://smartertraining.ai/terms")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func claimFreeAccess() {
        AnalyticsService.shared.track(.freeFounderSelected)
        subscriptionService.claimFreeFounderAccess()
    }

    private func purchaseProduct(_ product: Product, event: AnalyticsEvent) async {
        isPurchasing = true
        AnalyticsService.shared.track(event, properties: [
            "product": product.id,
            "price": product.displayPrice
        ])
        let success = await subscriptionService.purchase(product)
        if success {
            AnalyticsService.shared.track(.purchaseSucceeded, properties: [
                "product": product.id,
                "entitlement": subscriptionService.entitlement.rawValue
            ])
        }
        isPurchasing = false
    }

}

#Preview {
    FoundingPaywallView(subscriptionService: SubscriptionService())
        .environment(AppState())
}
