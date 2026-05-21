import SwiftUI
import SafariServices
import StoreKit

struct FoundingPaywallView: View {
    @Environment(AppState.self) private var appState
    var subscriptionService: SubscriptionService

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var safariURL: URL?
    @State private var selectedProductID: String?
    @State private var showRestoreNothingFound = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                featureList
                tierSelection
                purchaseCTA
                footer
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Theme.Surface.background)
        .task {
            await subscriptionService.loadProducts()
            AnalyticsService.shared.track(.paywallViewed)
            if selectedProductID == nil {
                selectedProductID = subscriptionService.annualProduct?.id
                    ?? subscriptionService.monthlyProduct?.id
            }
        }
        .onChange(of: subscriptionService.entitlement.isActive) { _, isActive in
            if isActive {
                #if DEBUG
                print("[Paywall] dismissing — entitlement active=\(subscriptionService.entitlement.rawValue)")
                #endif
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
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
            .foregroundStyle(.secondary)

            Text("Adaptive training for people with real lives")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text("SmarterTraining adapts your workouts to your recovery, fatigue, schedule, and consistency — so you make real progress without burning out.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("sparkles", "Adaptive AI-powered coaching")
            featureRow("heart.text.square", "Daily recommendations that respect recovery")
            featureRow("bolt.horizontal", "Built-in smart trainer + ERG support")
            featureRow("chart.line.uptrend.xyaxis", "Long-term progression that fits your life")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.Brand.primary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Tier Selection

    private var tierSelection: some View {
        VStack(spacing: 10) {
            if subscriptionService.isLoading && subscriptionService.products.isEmpty {
                ProgressView()
                    .padding(.vertical, 16)
            } else if subscriptionService.products.isEmpty && subscriptionService.didAttemptProductLoad {
                productLoadFailureCard
            } else {
                if let annual = subscriptionService.annualProduct {
                    productCard(
                        product: annual,
                        period: "year",
                        badge: annualSavingsBadge,
                        comparisonNote: nil
                    )
                }
                if let monthly = subscriptionService.monthlyProduct {
                    productCard(
                        product: monthly,
                        period: "month",
                        badge: nil,
                        comparisonNote: nil
                    )
                }
            }

            if let error = subscriptionService.purchaseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Shown when StoreKit returned no products — typically a network/App Store
    /// reachability issue. Gives the reviewer (or any user) a visible reason
    /// and an explicit retry path instead of an indefinite spinner.
    private var productLoadFailureCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Couldn't load subscription options")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Check your connection and try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await subscriptionService.loadProducts() }
            } label: {
                Text("Try again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Brand.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private func productCard(
        product: Product,
        period: String,
        badge: String?,
        comparisonNote: String?
    ) -> some View {
        let isSelected = (selectedProductID == product.id)

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Brand.primary : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(productTitle(for: product))
                            .font(.headline)
                            .foregroundStyle(.primary)
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
                    Text(priceLine(for: product, period: period))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let trialDays = subscriptionService.introductoryTrialDays(for: product) {
                        Text("Includes \(trialDays)-day free trial")
                            .font(.caption)
                            .foregroundStyle(Theme.Brand.primary)
                    } else if let note = comparisonNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(Theme.Surface.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(isSelected ? Theme.Border.selected : Theme.Border.subtle,
                            lineWidth: isSelected ? Theme.Border.selectedWidth : Theme.Border.width)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private func productTitle(for product: Product) -> String {
        if product.id == SubscriptionService.annualProductID { return "Annual" }
        if product.id == SubscriptionService.monthlyProductID { return "Monthly" }
        return product.displayName
    }

    private func priceLine(for product: Product, period: String) -> String {
        "\(product.displayPrice) / \(period)"
    }

    /// Computes annual savings vs. paying monthly for 12 months, when both
    /// products are loaded. Returns nil if monthly is missing or savings is
    /// non-positive.
    private var annualSavingsBadge: String? {
        guard let monthly = subscriptionService.monthlyProduct,
              let annual = subscriptionService.annualProduct else { return nil }
        let monthlyTotal = monthly.price * 12
        guard monthlyTotal > annual.price else { return nil }
        let savings = monthlyTotal - annual.price
        let percent = NSDecimalNumber(decimal: savings / monthlyTotal).doubleValue * 100
        guard percent >= 5 else { return nil }
        return "Save \(Int(percent.rounded()))%"
    }

    // MARK: - CTA

    private var purchaseCTA: some View {
        VStack(spacing: 8) {
            Button {
                Task { await startPurchase() }
            } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Brand.primary)
            .controlSize(.large)
            .disabled(isPurchasing || selectedProduct == nil)

            Text(ctaSubtext)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var selectedProduct: Product? {
        guard let id = selectedProductID else { return nil }
        return subscriptionService.products.first { $0.id == id }
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return "Continue" }
        if subscriptionService.introductoryTrialDays(for: product) != nil {
            return "Start Free Trial"
        }
        return "Continue"
    }

    private var ctaSubtext: String {
        guard let product = selectedProduct else {
            return "Cancel anytime."
        }
        let period = product.id == SubscriptionService.annualProductID ? "year" : "month"
        if let days = subscriptionService.introductoryTrialDays(for: product) {
            return "Free for \(days) days, then \(product.displayPrice)/\(period). Cancel anytime."
        }
        return "\(product.displayPrice)/\(period). Cancel anytime."
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isRestoring = true
                    showRestoreNothingFound = false
                    AnalyticsService.shared.track(.restoreTapped)
                    await subscriptionService.restorePurchases()
                    if subscriptionService.entitlement.isActive {
                        AnalyticsService.shared.track(.restoreSucceeded, properties: [
                            "entitlement": subscriptionService.entitlement.rawValue
                        ])
                    } else if subscriptionService.restoreFoundNothing {
                        showRestoreNothingFound = true
                    }
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Restore purchases")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .alert("No purchases to restore", isPresented: $showRestoreNothingFound) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("No active SmarterTraining subscription was found on this Apple ID.")
            }

            Text("Subscription renews automatically until cancelled. Manage anytime in Settings \u{203A} Apple ID \u{203A} Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 20) {
                Button("Privacy Policy") {
                    safariURL = URL(string: "https://smartertraining.ai/privacy")!
                }
                Button("Terms of Service") {
                    safariURL = URL(string: "https://smartertraining.ai/terms")!
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func startPurchase() async {
        guard let product = selectedProduct else { return }
        let event: AnalyticsEvent = (product.id == SubscriptionService.annualProductID)
            ? .purchaseAnnualTapped
            : .purchaseMonthlyTapped

        isPurchasing = true
        defer { isPurchasing = false }

        AnalyticsService.shared.track(event, properties: [
            "product": product.id,
            "price": product.displayPrice
        ])
        #if DEBUG
        print("[Paywall] purchase tapped product=\(product.id)")
        #endif

        let success = await subscriptionService.purchase(product)
        if success {
            AnalyticsService.shared.track(.purchaseSucceeded, properties: [
                "product": product.id,
                "entitlement": subscriptionService.entitlement.rawValue
            ])
            #if DEBUG
            print("[Paywall] purchase succeeded entitlement=\(subscriptionService.entitlement.rawValue)")
            #endif
        } else {
            #if DEBUG
            print("[Paywall] purchase did not unlock entitlement (cancelled, pending, failed, or unverified)")
            #endif
        }
    }
}

#Preview {
    FoundingPaywallView(subscriptionService: SubscriptionService())
        .environment(AppState())
}
