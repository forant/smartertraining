import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            if showingSplash {
                SplashView()
                    .transition(.opacity)
            } else if !appState.hasCompletedOnboarding {
                OnboardingFlowView()
                    .transition(.opacity)
            } else {
                if appState.hasCheckedInToday {
                    TodayView()
                        .transition(.opacity)
                } else {
                    CheckInView(context: appState.checkInContext)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: showingSplash)
        .animation(.easeOut(duration: 0.25), value: appState.hasCompletedOnboarding)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            showingSplash = false
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
