import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    var subscriptionService: SubscriptionService

    @State private var showingSplash = true

    var body: some View {
        ZStack {
            if showingSplash {
                SplashView()
                    .transition(.opacity)
            } else if !appState.hasCompletedOnboarding {
                OnboardingFlowView()
                    .transition(.opacity)
            } else if !subscriptionService.entitlement.isActive {
                FoundingPaywallView(subscriptionService: subscriptionService)
                    .transition(.opacity)
            } else {
                if appState.hasCheckedInToday {
                    TodayView(subscriptionService: subscriptionService)
                        .transition(.opacity)
                } else {
                    CheckInView(context: appState.checkInContext)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: showingSplash)
        .animation(.easeOut(duration: 0.25), value: appState.hasCompletedOnboarding)
        .animation(.easeOut(duration: 0.25), value: subscriptionService.entitlement.isActive)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            showingSplash = false
            await subscriptionService.resolveEntitlement()
        }
    }
}

#Preview {
    let service = SubscriptionService()
    #if DEBUG
    service.debugSimulateFounderClaimed()
    #endif
    return ContentView(subscriptionService: service)
        .environment(AppState())
}
