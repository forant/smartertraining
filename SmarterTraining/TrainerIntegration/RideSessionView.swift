import SwiftUI

struct RideSessionView: View {
    let recommendation: WorkoutRecommendation
    let ftp: Int?
    var checkIn: CheckIn?
    var recentHistory: [WorkoutHistoryEntry] = []
    var profile: UserProfile = .empty
    var existingEditor: WorkoutEditor?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var manager = FTMSManager()
    @State private var hrmManager = HRMManager()
    @State private var runtime: TrainerWorkoutRuntime?
    @State private var phase: SessionPhase = .connecting
    @State private var completedWorkout: CompletedWorkout?
    @State private var ergToggle = false
    @State private var editor: WorkoutEditor?
    @State private var showingEditor = false
    @State private var healthKit = HealthKitManager()
    @State private var savingToHealthKit = false
    @State private var showingHRMPicker = false

    // Post-workout state
    @State private var finishedPhase: FinishedPhase = .feedback
    @State private var postFeedback: WorkoutFeedback?
    @State private var postEffort: Int?
    @State private var postNote: String = ""
    @State private var reflectionService = PostWorkoutReflectionService()

    private static let saveIntervalSeconds = 10

    private enum SessionPhase {
        case connecting
        case ready
        case riding
        case finished
    }

    private enum FinishedPhase {
        case feedback
        case summary
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .connecting:
                    TrainerConnectionView(manager: manager) {
                        phase = .ready
                        if let existingEditor {
                            editor = existingEditor
                        } else {
                            let steps = WorkoutConverter.convert(recommendation: recommendation, ftp: ftp)
                            editor = WorkoutEditor(
                                steps: steps,
                                workoutType: recommendation.type,
                                ftp: ftp,
                                checkIn: checkIn,
                                recentHistory: recentHistory,
                                profile: profile
                            )
                        }
                    }
                case .ready:
                    readyView
                case .riding:
                    if let runtime {
                        rideExecutionView(runtime)
                    }
                case .finished:
                    finishedView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .finished ? "Done" : "Close") {
                        runtime?.finish()
                        manager.disconnect()
                        hrmManager.disconnect()
                        dismiss()
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .connecting: "Connect Trainer"
        case .ready: "Ready"
        case .riding: recommendation.title
        case .finished: "Workout Complete"
        }
    }

    // MARK: - Ready View

    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text(manager.connectionState.displayText)
                .font(.headline)

            if let editor {
                VStack(spacing: 8) {
                    Text(recommendation.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(editor.totalStepCount) steps \u{00B7} \(formatDuration(editor.totalDuration))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if editor.isModified {
                        Label("Modified from today's recommendation", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            ergToggleSection
            hrmSection

            Spacer()

            VStack(spacing: 12) {
                Button {
                    startRide()
                } label: {
                    Text("Start Workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingEditor = true
                } label: {
                    Label("Edit Workout", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)

            Button {
                phase = .connecting
                manager.disconnect()
                editor = nil
            } label: {
                Text("Change Trainer")
                    .font(.subheadline)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .sheet(isPresented: $showingEditor) {
            if let editor {
                WorkoutEditorView(editor: editor)
            }
        }
        .sheet(isPresented: $showingHRMPicker) {
            HRMPickerView(manager: hrmManager)
        }
        .task {
            await healthKit.requestAuthorization()
        }
        .onAppear {
            attemptHRMReconnect()
        }
    }

    private func attemptHRMReconnect() {
        guard !hrmManager.connectionState.isConnected else { return }
        if let remembered = RememberedDeviceStore.shared.hrm {
            hrmManager.attemptReconnect(identifier: remembered.peripheralIdentifier)
        }
    }

    private var hrmSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(hrmStatusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hrmStatusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(hrmDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(hrmManager.connectionState.isConnected ? "Change" : "Add") {
                    showingHRMPicker = true
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    private var hrmStatusText: String {
        switch hrmManager.connectionState {
        case .connected(let name): name
        case .connecting: "Connecting..."
        case .scanning: "Scanning..."
        default: "Heart rate monitor"
        }
    }

    private var hrmDetailText: String {
        switch hrmManager.connectionState {
        case .connected: "Connected"
        case .connecting(let name): "Connecting to \(name)"
        case .disconnected: "Optional \u{2014} tap Add to pair"
        case .error(let msg): msg
        default: "Not connected"
        }
    }

    private var hrmStatusColor: Color {
        switch hrmManager.connectionState {
        case .connected: .red
        case .connecting, .scanning: .orange
        default: .secondary
        }
    }

    private func startRide() {
        guard let editor else { return }
        runtime = TrainerWorkoutRuntime(
            steps: editor.toSteps(),
            trainerManager: manager,
            hrmManager: hrmManager
        )
        runtime?.ergEnabled = ergToggle

        let ride = CompletedWorkout(
            startDate: Date(),
            title: recommendation.title,
            status: .inProgress
        )
        completedWorkout = ride
        appState.store.saveRide(ride)

        phase = .riding
        runtime?.start()
        healthKit.startHeartRateObservation()
    }

    private var ergToggleSection: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $ergToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ERG Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Let SmarterTraining control trainer resistance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)

            if ergToggle && !manager.supportsERG && manager.connectionState.isConnected {
                Label("Trainer may not support ERG", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    // MARK: - Ride Execution

    private func rideExecutionView(_ runtime: TrainerWorkoutRuntime) -> some View {
        VStack(spacing: 0) {
            ergStatusBanner(runtime)
            metricsDisplay(runtime)
            cadenceWarning(runtime)
            Divider()
            stepInfo(runtime)
            Spacer()
            midRideERGToggle(runtime)
            rideControls(runtime)
        }
        .padding()
        .onChange(of: runtime.state) { _, newState in
            if newState == .finished {
                finishRide(runtime)
            }
        }
        .onChange(of: runtime.totalElapsed) { _, elapsed in
            let tick = Int(elapsed)
            if tick > 0 && tick % Self.saveIntervalSeconds == 0 {
                saveRideSnapshot(runtime)
            }
        }
        .onChange(of: manager.connectionState) { _, newState in
            if case .error = newState, runtime.state == .running {
                runtime.pause()
            }
        }
        .onChange(of: ergToggle) { _, newValue in
            runtime.ergEnabled = newValue
        }
    }

    private func saveRideSnapshot(_ runtime: TrainerWorkoutRuntime) {
        guard var ride = completedWorkout else { return }
        ride.duration = runtime.totalElapsed
        ride.samples = runtime.samples
        appState.store.saveRide(ride)
    }

    private func finishRide(_ runtime: TrainerWorkoutRuntime) {
        healthKit.stopHeartRateObservation()

        let trainerHRs = runtime.samples.compactMap(\.heartRate).filter { $0 > 0 }
        let hrValues = trainerHRs.isEmpty ? healthKit.collectedBPMs : trainerHRs
        let avgHR = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / hrValues.count
        let maxHR = hrValues.max()

        if var ride = completedWorkout {
            ride.duration = runtime.totalElapsed
            ride.samples = runtime.samples
            ride.status = .finished
            ride.averageHeartRate = avgHR
            ride.maxHeartRate = maxHR
            ride.computeStats(from: runtime.samples, ergEnabled: ergToggle, workoutType: recommendation.type)
            completedWorkout = ride
            appState.store.saveRide(ride)
        } else {
            var ride = CompletedWorkout(
                startDate: runtime.startDate ?? Date(),
                duration: runtime.totalElapsed,
                title: recommendation.title,
                samples: runtime.samples,
                status: .finished,
                averageHeartRate: avgHR,
                maxHeartRate: maxHR
            )
            ride.computeStats(from: runtime.samples, ergEnabled: ergToggle, workoutType: recommendation.type)
            completedWorkout = ride
            appState.store.saveRide(ride)
        }
        finishedPhase = .feedback
        phase = .finished
        appState.triggerSync()

        if healthKit.isAvailable {
            savingToHealthKit = true
            Task {
                let endDate = Date()
                let startDate = completedWorkout?.startDate ?? runtime.startDate ?? endDate
                let (uuid, failure) = await healthKit.saveWorkout(
                    startDate: startDate,
                    endDate: endDate,
                    trainerSamples: runtime.samples
                )
                savingToHealthKit = false
                completedWorkout?.healthKitWorkoutUUID = uuid
                completedWorkout?.healthKitSaveStatus = uuid != nil ? .saved : .failed
                completedWorkout?.healthKitFailureReason = failure
                if let ride = completedWorkout {
                    appState.store.saveRide(ride)
                }
            }
        }
    }

    private func submitFeedbackAndRequestReflection() {
        CoachingNotificationManager.shared.requestPermissionIfNeeded()

        completedWorkout?.workoutFeedback = postFeedback
        completedWorkout?.perceivedEffort = postEffort
        completedWorkout?.postWorkoutNote = postNote.isEmpty ? nil : postNote
        completedWorkout?.reflectionStatus = .loading
        completedWorkout?.updatedAt = Date()

        if let ride = completedWorkout {
            appState.store.saveRide(ride)
        }

        if let feedback = postFeedback {
            appState.submitFeedback(feedback)
        }

        finishedPhase = .summary

        let feedbackIntent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: completedWorkout?.id ?? UUID(),
            workoutCompletedAt: Date(),
            workoutType: recommendation.type,
            feedback: postFeedback,
            perceivedEffort: postEffort
        )
        appState.store.saveIntent(feedbackIntent)
        CoachingNotificationManager.shared.scheduleNotifications(for: feedbackIntent)

        Task {
            guard var ride = completedWorkout else { return }
            let memorySummary = TrainingMemoryBuilder.build(
                history: appState.recentHistory,
                rides: appState.store.finishedRides()
            )
            await reflectionService.fetchReflection(
                workout: ride,
                recommendation: recommendation,
                steps: editor?.toSteps() ?? [],
                checkIn: checkIn,
                memorySummary: memorySummary,
                auth: appState.auth
            )

            if let reflection = reflectionService.reflection {
                ride = completedWorkout ?? ride
                ride.reflection = reflection
                ride.reflectionStatus = reflection.isFallback ? .failed : .generated
                ride.updatedAt = Date()
                completedWorkout = ride
                appState.store.saveRide(ride)

                let intent = TrainingIntentBuilder.build(
                    from: reflection,
                    sourceWorkoutId: ride.id,
                    workoutCompletedAt: ride.startDate,
                    workoutType: recommendation.type
                )
                appState.store.saveIntent(intent)
                CoachingNotificationManager.shared.scheduleNotifications(for: intent)
            }
        }
    }

    @ViewBuilder
    private func ergStatusBanner(_ runtime: TrainerWorkoutRuntime) -> some View {
        switch runtime.ergState {
        case .off:
            EmptyView()
        case .enabling:
            statusPill("ERG enabling...", icon: "gearshape", color: .orange)
        case .active:
            statusPill("ERG active", icon: "bolt.fill", color: .green)
        case .unsupported:
            statusPill("ERG unavailable \u{2014} follow the targets manually.", icon: "exclamationmark.triangle", color: .orange)
        case .failed(let msg):
            statusPill("ERG unavailable \u{2014} follow the targets manually.", icon: "exclamationmark.triangle", color: .orange)
                .onAppear {
                    #if DEBUG
                    print("[ERG] Fallback reason: \(msg)")
                    #endif
                }
        }
    }

    private func statusPill(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 4)
    }

    private func metricsDisplay(_ runtime: TrainerWorkoutRuntime) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("TARGET")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(runtime.displayTargetPower ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: runtime.displayTargetPower)
                Text("watts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                metricBox("POWER", value: runtime.smoothedPower.map { "\($0)" } ?? "--", unit: "W")
                hrMetricBox
                metricBox("CADENCE", value: manager.metrics.cadence.map { "\(Int($0))" } ?? "--", unit: "rpm")
                metricBox("SPEED", value: manager.metrics.speed.map { String(format: "%.1f", $0) } ?? "--", unit: "km/h")
            }
        }
        .padding(.vertical, 20)
    }

    private var hrMetricBox: some View {
        let resolved = resolvedHeartRate
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("HR")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                #if DEBUG
                if resolved.source != .none {
                    Text("(\(resolved.source.rawValue))")
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                }
                #endif
            }
            Text(resolved.bpm.map { "\($0)" } ?? "--")
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text("bpm")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricBox(_ label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepInfo(_ runtime: TrainerWorkoutRuntime) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: runtime.progress)
                .tint(.accentColor)

            if let step = runtime.currentStep {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(.headline)
                        Text("\(step.targetPower)W target")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatDuration(runtime.stepRemaining))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }

            if let next = runtime.nextStep {
                HStack {
                    Text("Up next: \(next.name)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(next.targetPower)W \u{00B7} \(formatDuration(next.duration))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text("Elapsed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatDuration(runtime.totalElapsed))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 16)
    }

    private func rideControls(_ runtime: TrainerWorkoutRuntime) -> some View {
        HStack(spacing: 16) {
            Button {
                runtime.finish()
            } label: {
                Text("End")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)

            Button {
                if runtime.state == .running {
                    runtime.pause()
                } else {
                    runtime.resume()
                }
            } label: {
                Text(runtime.state == .running ? "Pause" : "Resume")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Finished

    private var finishedView: some View {
        Group {
            switch finishedPhase {
            case .feedback:
                feedbackPhaseView
            case .summary:
                summaryPhaseView
            }
        }
    }

    private var feedbackPhaseView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Workout Complete")
                    .font(.title2)
                    .fontWeight(.bold)

                if let runtime {
                    Text(formatDuration(runtime.totalElapsed) + " total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PostWorkoutFeedbackView(
                    feedback: $postFeedback,
                    perceivedEffort: $postEffort,
                    note: $postNote,
                    onDone: submitFeedbackAndRequestReflection
                )
            }
            .padding(.horizontal, 24)
        }
    }

    private var summaryPhaseView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Workout Complete")
                    .font(.title2)
                    .fontWeight(.bold)

                if let workout = completedWorkout {
                    PostWorkoutSummaryCard(workout: workout)
                }

                if let reflection = reflectionService.reflection {
                    PostWorkoutReflectionCard(
                        reflection: reflection,
                        isLoading: false
                    )
                } else if reflectionService.isLoading {
                    ReflectionLoadingView()
                }

                if healthKit.isAvailable {
                    healthKitStatusView
                }

                if let workout = completedWorkout {
                    StravaPostView(workout: workout) {
                        completedWorkout?.isPostedToStrava = true
                        if var ride = completedWorkout {
                            ride.isPostedToStrava = true
                            appState.store.saveRide(ride)
                        }
                    }
                }

                Button {
                    manager.disconnect()
                    hrmManager.disconnect()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    // MARK: - Heart Rate

    private var resolvedHeartRate: ResolvedHeartRate {
        HeartRateResolver.resolve(
            trainerHR: manager.metrics.heartRate,
            hrmHR: hrmManager.heartRate,
            healthKitHR: healthKit.currentHeartRate
        )
    }

    private var effectiveHeartRate: Int? {
        resolvedHeartRate.bpm
    }

    @ViewBuilder
    private var healthKitStatusView: some View {
        if savingToHealthKit {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving to Health...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if completedWorkout?.healthKitSaveStatus == .saved {
            Label("Saved to Health", systemImage: "heart.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else if completedWorkout?.healthKitSaveStatus == .failed {
            VStack(spacing: 4) {
                Label("Could not save to Health", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                if let reason = completedWorkout?.healthKitFailureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Cadence Warning

    @ViewBuilder
    private func cadenceWarning(_ runtime: TrainerWorkoutRuntime) -> some View {
        if case .low(let rpm) = runtime.cadenceStatus {
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Cadence low (\(rpm) rpm) \u{2014} try to stay above 75 rpm")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.3), value: runtime.cadenceStatus)
        }
    }

    // MARK: - Mid-Ride ERG Toggle

    private func midRideERGToggle(_ runtime: TrainerWorkoutRuntime) -> some View {
        HStack {
            Toggle(isOn: $ergToggle) {
                HStack(spacing: 6) {
                    Image(systemName: ergToggle ? "bolt.fill" : "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(ergToggle ? .green : .secondary)
                    Text(ergToggle ? "ERG on" : "ERG off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
