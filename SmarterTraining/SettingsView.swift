import SwiftUI
import AuthenticationServices
import Sentry

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var subscriptionService: SubscriptionService?
    @State private var stravaAuth = StravaAuth()
    @State private var healthKit = HealthKitManager()
    @State private var signInError: String?
    @State private var isAuthorizingStrava = false
    @State private var stravaError: String?
    @State private var showCrashConfirmation = false
    @State private var isRestoring = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                if let subscriptionService {
                    membershipSection(subscriptionService)
                }
                accountSection
                devicesSection
                integrationsSection
                trainingDataSection
                dangerZoneSection
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

    // MARK: - Membership

    private func membershipSection(_ service: SubscriptionService) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.entitlement.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                Task {
                    isRestoring = true
                    await service.restorePurchases()
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Restore purchases")
                }
            }
            .font(.subheadline)
        } header: {
            Text("Membership")
        } footer: {
            Text("Manage your subscription in Settings \u{203A} Apple ID \u{203A} Subscriptions.")
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

    // MARK: - Devices

    private var devicesSection: some View {
        Section {
            rememberedDeviceRow(
                label: "Trainer",
                icon: "bicycle",
                device: RememberedDeviceStore.shared.trainer,
                onForget: { RememberedDeviceStore.shared.forgetTrainer() }
            )
            rememberedDeviceRow(
                label: "Heart rate monitor",
                icon: "heart.fill",
                device: RememberedDeviceStore.shared.hrm,
                onForget: { RememberedDeviceStore.shared.forgetHRM() }
            )
        } header: {
            Text("Remembered devices")
        } footer: {
            Text("Remembered devices reconnect automatically at ride start.")
        }
    }

    private func rememberedDeviceRow(
        label: String,
        icon: String,
        device: RememberedDevice?,
        onForget: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(device != nil ? Color.accentColor : Color(.tertiaryLabel))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let device {
                    Text(device.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("None saved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if device != nil {
                Button("Forget", role: .destructive) {
                    onForget()
                }
                .font(.subheadline)
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

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                AnalyticsService.shared.track(.deleteAccountTapped)
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete my account")
                        .font(.subheadline)
                    if isDeletingAccount {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isDeletingAccount)
            .confirmationDialog(
                "Delete account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    performAccountDeletion()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your SmarterTraining account, training data, check-ins, and local app data. This can\u{2019}t be undone.")
            }

            if let deleteError {
                Label(deleteError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Deletes all data and returns the app to its initial state.")
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        deleteError = nil
        AnalyticsService.shared.track(.deleteAccountConfirmed)

        Task {
            do {
                if appState.auth.isSignedIn {
                    try await appState.auth.deleteAccount()
                }

                appState.deleteAllLocalData()
                subscriptionService?.clearLocalEntitlement()
                AnalyticsService.shared.track(.deleteAccountSucceeded)
                AnalyticsService.shared.reset()
                SentryService.clearUser()

                isDeletingAccount = false
                dismiss()
            } catch {
                isDeletingAccount = false
                deleteError = "We couldn\u{2019}t delete your account. Please try again."
                AnalyticsService.shared.track(.deleteAccountFailed, properties: [
                    "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
                ])
            }
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

            Link(destination: URL(string: "https://smartertraining.ai/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Link(destination: URL(string: "https://smartertraining.ai/terms")!) {
                HStack {
                    Text("Terms of Service")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

            if let subscriptionService {
                Section("Subscription") {
                    HStack {
                        Text("Entitlement")
                            .font(.subheadline)
                        Spacer()
                        Text(subscriptionService.entitlement.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Free spots left")
                            .font(.subheadline)
                        Spacer()
                        Text(subscriptionService.isFreeFoundingAvailable ? "Available" : "Full")
                            .font(.caption)
                            .foregroundStyle(subscriptionService.isFreeFoundingAvailable ? .green : .red)
                    }

                    Button("Reset Entitlement", role: .destructive) {
                        subscriptionService.debugResetEntitlement()
                    }

                    Button("Simulate Founder Claimed") {
                        subscriptionService.debugSimulateFounderClaimed()
                    }

                    Button("Set Founder Count Full") {
                        subscriptionService.debugSetFounderCountFull()
                    }

                    Button("Set Founder Count Available") {
                        subscriptionService.debugSetFounderCountAvailable()
                    }
                }
            }

            Section("Analytics") {
                HStack {
                    Text("Mixpanel")
                        .font(.subheadline)
                    Spacer()
                    Text(AnalyticsConfig.isConfigured ? "Configured" : "Log-only")
                        .font(.caption)
                        .foregroundStyle(AnalyticsConfig.isConfigured ? .green : .secondary)
                }

                HStack {
                    Text("Environment")
                        .font(.subheadline)
                    Spacer()
                    Text(AnalyticsConfig.environment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Flush Events") {
                    AnalyticsService.shared.flush()
                }

                Button("Send Test Event") {
                    AnalyticsService.shared.track(.appOpened, properties: [
                        "test": true
                    ])
                }
            }

            Section("Sentry") {
                HStack {
                    Text("Crash reporting")
                        .font(.subheadline)
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Send Test Error") {
                    ErrorLogger.log(.persistence, message: "Debug test error from settings")
                }

                Button("Test Crash", role: .destructive) {
                    showCrashConfirmation = true
                }
                .alert("This will crash the app", isPresented: $showCrashConfirmation) {
                    Button("Crash", role: .destructive) { SentrySDK.crash() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("The crash report will be sent to Sentry on next launch. If running in Xcode, the app will appear frozen — just stop and re-run.")
                }
            }
        }
    }
    #endif
}
