import SwiftUI

@main
struct SmarterTrainingApp: App {
    @State private var appState = AppState()
    @State private var subscriptionService = SubscriptionService()

    init() {
        SentryService.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(subscriptionService: subscriptionService)
                .environment(appState)
                .tint(Theme.Brand.primary)
                .onAppear {
                    AnalyticsService.shared.track(.appOpened)
                    if let userId = appState.auth.userId {
                        AnalyticsService.shared.identify(userId: userId)
                        SentryService.setUser(id: userId)
                    }
                }
        }
    }
}
