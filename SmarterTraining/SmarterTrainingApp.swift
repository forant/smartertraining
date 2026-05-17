import SwiftUI

@main
struct SmarterTrainingApp: App {
    @State private var appState = AppState()

    init() {
        SentryService.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
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
