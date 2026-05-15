import SwiftUI

struct RideSessionView: View {
    let recommendation: WorkoutRecommendation
    let ftp: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var manager = FTMSManager()
    @State private var runtime: TrainerWorkoutRuntime?
    @State private var phase: SessionPhase = .connecting
    @State private var completedWorkout: CompletedWorkout?
    @State private var ergToggle = false
    @State private var editor: WorkoutEditor?
    @State private var showingEditor = false

    private enum SessionPhase {
        case connecting
        case ready
        case riding
        case finished
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .connecting:
                    TrainerConnectionView(manager: manager) {
                        phase = .ready
                        let steps = WorkoutConverter.convert(recommendation: recommendation, ftp: ftp)
                        editor = WorkoutEditor(steps: steps, workoutType: recommendation.type, ftp: ftp)
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

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if let editor {
                        runtime = TrainerWorkoutRuntime(
                            steps: editor.toSteps(),
                            trainerManager: manager
                        )
                        runtime?.ergEnabled = ergToggle
                    }
                    phase = .riding
                    runtime?.start()
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
            Divider()
            stepInfo(runtime)
            Spacer()
            rideControls(runtime)
        }
        .padding()
        .onChange(of: runtime.state) { _, newState in
            if newState == .finished {
                completedWorkout = CompletedWorkout(
                    startDate: runtime.startDate ?? Date(),
                    duration: runtime.totalElapsed,
                    title: recommendation.title,
                    samples: runtime.samples
                )
                phase = .finished
            }
        }
        .onChange(of: manager.connectionState) { _, newState in
            if case .error = newState, runtime.state == .running {
                runtime.pause()
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
                Text("\(runtime.targetPower ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                Text("watts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                metricBox("POWER", value: manager.metrics.power.map { "\($0)" } ?? "--", unit: "W")
                metricBox("CADENCE", value: manager.metrics.cadence.map { "\(Int($0))" } ?? "--", unit: "rpm")
                metricBox("SPEED", value: manager.metrics.speed.map { String(format: "%.1f", $0) } ?? "--", unit: "km/h")
            }
        }
        .padding(.vertical, 20)
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
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Workout Complete")
                    .font(.title2)
                    .fontWeight(.bold)

                if let runtime {
                    Text(formatDuration(runtime.totalElapsed) + " total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let workout = completedWorkout {
                    StravaPostView(workout: workout) {
                        completedWorkout?.isPostedToStrava = true
                    }
                }

                Button {
                    manager.disconnect()
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

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
