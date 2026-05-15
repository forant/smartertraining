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
                Text("Keep your training history backed up and synced across devices.")
            }
        }
    }

    private var signedInContent: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Signed in")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    syncSummaryText
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if case .syncing = appState.sync.status {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button("Sync now") {
                appState.triggerSync()
            }

            Button("Sign out", role: .destructive) {
                appState.auth.signOut()
                appState.sync.updateAuthStatus()
            }
        }
    }

    @ViewBuilder
    private var syncSummaryText: some View {
        switch appState.sync.status {
        case .synced:
            if let lastSynced = appState.sync.lastSyncedAt {
                Text("Synced \(lastSynced.formatted(.relative(presentation: .named)))")
            } else {
                Text("Synced")
            }
        case .syncing:
            Text("Syncing\u{2026}")
        case .error(let msg):
            Text(msg)
                .foregroundStyle(.red)
        default:
            Text("Ready to sync")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strava")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(stravaAuth.athleteName.map { "Connected as \($0)" } ?? "Connected")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Disconnect", role: .destructive) {
                    stravaAuth.disconnect()
                }
                .font(.subheadline)
            } else if StravaConfig.isConfigured {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strava")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Auto-upload finished rides")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isAuthorizingStrava {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Button("Connect to Strava") {
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
                }
                .disabled(isAuthorizingStrava)
                .font(.subheadline)

                if let stravaError {
                    Text(stravaError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Text("Strava")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var healthKitRow: some View {
        Group {
            if healthKit.isAvailable {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Heart rate and workout saving")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                Button("Grant permissions") {
                    Task { await healthKit.requestAuthorization() }
                }
                .font(.subheadline)
            } else {
                HStack {
                    Text("Apple Health")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Not available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Training Data

    private var trainingDataSection: some View {
        Section {
            dataRow("Workouts", value: "\(appState.recentHistory.count)")
            dataRow("Finished rides", value: "\(appState.store.finishedRides().count)")

            if appState.auth.isSignedIn {
                let summary = appState.store.syncMetadataSummary()
                dataRow("Synced", value: "\(summary.syncedCount)")
                if summary.failedCount > 0 {
                    dataRow("Failed", value: "\(summary.failedCount)", valueColor: .red)
                }
            }
        } header: {
            Text("Training data")
        }
    }

    private func dataRow(_ label: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .font(.subheadline)
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text("Training for people with real lives.")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
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
