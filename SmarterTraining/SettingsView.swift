import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var stravaAuth = StravaAuth()
    @State private var healthKit = HealthKitManager()
    @State private var signInError: String?
    @State private var isAuthorizingStrava = false
    @State private var stravaError: String?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                integrationsSection
                trainingDataSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if appState.auth.isSignedIn {
                signedInContent
            } else {
                signedOutContent
            }
        } header: {
            Text("Account")
        } footer: {
            if !appState.auth.isSignedIn {
                Text("Sync your training history across devices.")
            }
        }
    }

    private var signedInContent: some View {
        Group {
            HStack {
                Label("Signed In", systemImage: "person.crop.circle.fill")
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Label(appState.sync.status.displayText, systemImage: syncIcon)
                Spacer()
                if case .syncing = appState.sync.status {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let lastSynced = appState.sync.lastSyncedAt {
                HStack {
                    Text("Last synced")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastSynced.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }

            Button("Sync Now") {
                appState.triggerSync()
            }

            Button("Sign Out", role: .destructive) {
                appState.auth.signOut()
                appState.sync.updateAuthStatus()
            }
        }
    }

    private var signedOutContent: some View {
        Group {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task {
                        do {
                            try await appState.auth.handleSignIn(authorization: authorization)
                            appState.sync.updateAuthStatus()
                            appState.triggerSync()
                            signInError = nil
                        } catch {
                            signInError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    signInError = error.localizedDescription
                }
            }
            .frame(height: 44)

            if let signInError {
                Label(signInError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var syncIcon: String {
        switch appState.sync.status {
        case .notSignedIn: "arrow.triangle.2.circlepath"
        case .idle: "arrow.triangle.2.circlepath"
        case .syncing: "arrow.triangle.2.circlepath.circle"
        case .synced: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle"
        }
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        Section("Integrations") {
            stravaRow
            healthKitRow
        }
    }

    private var stravaRow: some View {
        Group {
            if stravaAuth.isConnected {
                HStack {
                    Label(stravaAuth.athleteName ?? "Strava", systemImage: "figure.run")
                    Spacer()
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                Button("Disconnect Strava", role: .destructive) {
                    stravaAuth.disconnect()
                }
            } else if StravaConfig.isConfigured {
                HStack {
                    Label("Strava", systemImage: "figure.run")
                    Spacer()
                    Text("Not connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        isAuthorizingStrava = true
                        stravaError = nil
                        do {
                            try await stravaAuth.authorize()
                        } catch {
                            stravaError = error.localizedDescription
                        }
                        isAuthorizingStrava = false
                    }
                } label: {
                    HStack {
                        Text("Connect to Strava")
                        if isAuthorizingStrava {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isAuthorizingStrava)

                if let stravaError {
                    Text(stravaError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Label("Strava", systemImage: "figure.run")
                    Spacer()
                    Text("Not configured")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var healthKitRow: some View {
        Group {
            if healthKit.isAvailable {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                    Spacer()
                    Text("Available")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                Button("Request Permissions") {
                    Task { await healthKit.requestAuthorization() }
                }
            } else {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                    Spacer()
                    Text("Not available")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Training Data

    private var trainingDataSection: some View {
        Section("Training Data") {
            HStack {
                Text("Workouts")
                Spacer()
                Text("\(appState.recentHistory.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Finished rides")
                Spacer()
                Text("\(appState.store.finishedRides().count)")
                    .foregroundStyle(.secondary)
            }

            if appState.auth.isSignedIn {
                let summary = appState.store.syncMetadataSummary()
                HStack {
                    Text("Synced")
                    Spacer()
                    Text("\(summary.syncedCount)")
                        .foregroundStyle(.secondary)
                }
                if summary.failedCount > 0 {
                    HStack {
                        Text("Failed")
                        Spacer()
                        Text("\(summary.failedCount)")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .foregroundStyle(.secondary)
            }

            Text("Training for people with real lives.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "\u{2014}"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "\u{2014}"
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Button("Force Sync") { appState.triggerSync() }

            Button("Clear Sync State", role: .destructive) {
                appState.sync.debugClearSyncState()
            }

            Button("Clear History", role: .destructive) {
                appState.debugClearHistory()
            }

            Button("Reset Today", role: .destructive) {
                appState.resetToday()
            }

            Button("Reset Onboarding", role: .destructive) {
                appState.resetOnboarding()
            }

            let summary = appState.store.syncMetadataSummary()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Pending: \(summary.pendingCount)")
                    Text("Synced: \(summary.syncedCount)")
                    Text("Failed: \(summary.failedCount)")
                        .foregroundStyle(summary.failedCount > 0 ? .red : .secondary)
                }

                if let lastAttempt = summary.lastAttempt {
                    Text("Last attempt: \(lastAttempt.formatted(.dateTime.hour().minute().second()))")
                }
                if let lastSuccess = summary.lastSuccess {
                    Text("Last success: \(lastSuccess.formatted(.dateTime.hour().minute().second()))")
                }
                if !summary.recentFailures.isEmpty {
                    Text("Failures: \(summary.recentFailures.joined(separator: ", "))")
                        .foregroundStyle(.red)
                }

                Text("Service: \(appState.sync.status.displayText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("+ Recovery") { appState.debugSeedWorkout(type: .recovery) }
                Button("+ Endurance") { appState.debugSeedWorkout(type: .endurance) }
                Button("+ Quality") { appState.debugSeedWorkout(type: .quality) }
            }
            .font(.caption)
        }
    }
    #endif
}
