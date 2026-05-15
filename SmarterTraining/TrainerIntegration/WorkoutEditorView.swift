import SwiftUI

// MARK: - Editor Model

@Observable
final class WorkoutEditor {

    struct StepGroup: Identifiable {
        let id = UUID()
        var name: String
        var duration: TimeInterval
        var targetPower: Int
        var role: WorkoutStepRole
        var intervalReps: Int?
        var restDuration: TimeInterval?
        var restPower: Int?

        var isIntervalSet: Bool { intervalReps != nil }
    }

    var groups: [StepGroup]
    let originalSteps: [TrainerWorkoutStep]
    let workoutType: WorkoutType
    let ftp: Int?
    let checkIn: CheckIn?
    let recentHistory: [WorkoutHistoryEntry]
    let profile: UserProfile

    init(
        steps: [TrainerWorkoutStep],
        workoutType: WorkoutType,
        ftp: Int?,
        checkIn: CheckIn? = nil,
        recentHistory: [WorkoutHistoryEntry] = [],
        profile: UserProfile = .empty
    ) {
        self.originalSteps = steps
        self.workoutType = workoutType
        self.ftp = ftp
        self.checkIn = checkIn
        self.recentHistory = recentHistory
        self.profile = profile
        self.groups = Self.groupSteps(steps)
    }

    var isModified: Bool {
        let current = toSteps()
        guard current.count == originalSteps.count else { return true }
        return zip(current, originalSteps).contains { a, b in
            a.duration != b.duration || a.targetPower != b.targetPower || a.name != b.name
        }
    }

    var totalDuration: TimeInterval {
        groups.reduce(0) { total, group in
            if let reps = group.intervalReps {
                let work = group.duration * Double(reps)
                let rest = (group.restDuration ?? 0) * Double(max(0, reps - 1))
                return total + work + rest
            }
            return total + group.duration
        }
    }

    var totalStepCount: Int {
        groups.reduce(0) { count, group in
            if let reps = group.intervalReps {
                return count + reps + max(0, reps - 1)
            }
            return count + 1
        }
    }

    var evaluation: WorkoutEditEvaluation {
        let evaluator = WorkoutEditEvaluator(
            workoutType: workoutType,
            originalSteps: originalSteps,
            editedSteps: toSteps(),
            checkIn: checkIn,
            recentHistory: recentHistory,
            profile: profile
        )
        return evaluator.evaluate()
    }

    var intensityWarning: String? {
        guard workoutType == .recovery else { return nil }
        let maxPower = groups.map(\.targetPower).max() ?? 0
        let threshold = ftp.map { Int(Double($0) * 0.7) } ?? 150
        guard maxPower > threshold else { return nil }
        return "This looks more intense than a typical recovery workout."
    }

    func reset() {
        groups = Self.groupSteps(originalSteps)
    }

    func toSteps() -> [TrainerWorkoutStep] {
        var steps: [TrainerWorkoutStep] = []
        for group in groups {
            if let reps = group.intervalReps {
                for i in 1...reps {
                    steps.append(TrainerWorkoutStep(
                        name: "Interval \(i) of \(reps)",
                        duration: group.duration,
                        targetPower: group.targetPower,
                        role: .primary
                    ))
                    if i < reps, let restDur = group.restDuration, let restW = group.restPower {
                        steps.append(TrainerWorkoutStep(
                            name: "Recovery",
                            duration: restDur,
                            targetPower: restW,
                            role: .cooldown
                        ))
                    }
                }
            } else {
                steps.append(TrainerWorkoutStep(
                    name: group.name,
                    duration: group.duration,
                    targetPower: group.targetPower,
                    role: group.role
                ))
            }
        }
        return steps
    }

    // MARK: - Grouping

    private static func groupSteps(_ steps: [TrainerWorkoutStep]) -> [StepGroup] {
        var groups: [StepGroup] = []
        var i = 0

        while i < steps.count {
            let step = steps[i]

            if let info = parseIntervalName(step.name) {
                let reps = info.total
                var restDuration: TimeInterval = 120
                var restPower = 100

                if i + 1 < steps.count && steps[i + 1].name == "Recovery" {
                    restDuration = steps[i + 1].duration
                    restPower = steps[i + 1].targetPower
                }

                groups.append(StepGroup(
                    name: "Intervals",
                    duration: step.duration,
                    targetPower: step.targetPower,
                    role: step.role,
                    intervalReps: reps,
                    restDuration: restDuration,
                    restPower: restPower
                ))

                // Skip past all interval + recovery steps
                let stepsToSkip = reps + max(0, reps - 1)
                i += stepsToSkip
                continue
            }

            groups.append(StepGroup(
                name: step.name,
                duration: step.duration,
                targetPower: step.targetPower,
                role: step.role
            ))
            i += 1
        }

        return groups
    }

    private static func parseIntervalName(_ name: String) -> (current: Int, total: Int)? {
        let pattern = #"Interval (\d+) of (\d+)"#
        guard let match = name.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(name[match])
        let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
        guard numbers.count >= 2, let current = Int(numbers[0]), let total = Int(numbers[1]) else { return nil }
        return (current, total)
    }
}

// MARK: - Bounds

private enum Bounds {
    static let minDuration: TimeInterval = 60
    static let maxDuration: TimeInterval = 3600
    static let durationStep: TimeInterval = 60
    static let minWatts = 30
    static let maxWatts = 500
    static let wattsStep = 5
    static let minReps = 1
    static let maxReps = 10
}

// MARK: - Editor View

struct WorkoutEditorView: View {
    var editor: WorkoutEditor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if editor.isModified {
                    Section {
                        Label("Modified from today's recommendation", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                ForEach(Array(editor.groups.enumerated()), id: \.element.id) { index, group in
                    if group.isIntervalSet {
                        intervalSection(index: index, group: group)
                    } else {
                        singleStepSection(index: index, group: group)
                    }
                }

                Section {
                    HStack {
                        Text("Total")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(editor.totalStepCount) steps \u{00B7} \(formatMinutes(editor.totalDuration))")
                            .foregroundStyle(.secondary)
                    }
                }

                if editor.evaluation.level != .neutral {
                    evaluationSection(editor.evaluation)
                }

                if editor.isModified {
                    Section {
                        Button("Reset to recommendation") {
                            editor.reset()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Single Step

    private func singleStepSection(index: Int, group: WorkoutEditor.StepGroup) -> some View {
        Section(group.name) {
            adjustableRow("Duration", value: formatMinutes(group.duration)) {
                editor.groups[index].duration = max(Bounds.minDuration, group.duration - Bounds.durationStep)
            } onIncrement: {
                editor.groups[index].duration = min(Bounds.maxDuration, group.duration + Bounds.durationStep)
            }
            adjustableRow("Target", value: "\(group.targetPower)W") {
                editor.groups[index].targetPower = max(Bounds.minWatts, group.targetPower - Bounds.wattsStep)
            } onIncrement: {
                editor.groups[index].targetPower = min(Bounds.maxWatts, group.targetPower + Bounds.wattsStep)
            }
        }
    }

    // MARK: - Interval Set

    private func intervalSection(index: Int, group: WorkoutEditor.StepGroup) -> some View {
        Section("Intervals") {
            adjustableRow("Reps", value: "\(group.intervalReps ?? 1)x") {
                let current = group.intervalReps ?? 1
                editor.groups[index].intervalReps = max(Bounds.minReps, current - 1)
            } onIncrement: {
                let current = group.intervalReps ?? 1
                editor.groups[index].intervalReps = min(Bounds.maxReps, current + 1)
            }

            Text("Work").font(.caption).foregroundStyle(.secondary)

            adjustableRow("Duration", value: formatMinutes(group.duration)) {
                editor.groups[index].duration = max(Bounds.minDuration, group.duration - Bounds.durationStep)
            } onIncrement: {
                editor.groups[index].duration = min(Bounds.maxDuration, group.duration + Bounds.durationStep)
            }
            adjustableRow("Target", value: "\(group.targetPower)W") {
                editor.groups[index].targetPower = max(Bounds.minWatts, group.targetPower - Bounds.wattsStep)
            } onIncrement: {
                editor.groups[index].targetPower = min(Bounds.maxWatts, group.targetPower + Bounds.wattsStep)
            }

            if let restDuration = group.restDuration, let restPower = group.restPower {
                Text("Rest").font(.caption).foregroundStyle(.secondary)

                adjustableRow("Duration", value: formatMinutes(restDuration)) {
                    editor.groups[index].restDuration = max(Bounds.minDuration, restDuration - Bounds.durationStep)
                } onIncrement: {
                    editor.groups[index].restDuration = min(Bounds.maxDuration, restDuration + Bounds.durationStep)
                }
                adjustableRow("Target", value: "\(restPower)W") {
                    editor.groups[index].restPower = max(Bounds.minWatts, restPower - Bounds.wattsStep)
                } onIncrement: {
                    editor.groups[index].restPower = min(Bounds.maxWatts, restPower + Bounds.wattsStep)
                }
            }
        }
    }

    // MARK: - Adjustable Row

    private func adjustableRow(
        _ label: String,
        value: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Button(action: onDecrement) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(minWidth: 56)
                .multilineTextAlignment(.center)

            Button(action: onIncrement) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Evaluation Display

    private func evaluationSection(_ eval: WorkoutEditEvaluation) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(eval.title, systemImage: evaluationIcon(eval.level))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(evaluationColor(eval.level))
                Text(eval.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func evaluationIcon(_ level: WorkoutEditGuidanceLevel) -> String {
        switch level {
        case .neutral: "checkmark.circle"
        case .encouragement: "hand.thumbsup.fill"
        case .notice: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .strongDiscourage: "exclamationmark.octagon.fill"
        }
    }

    private func evaluationColor(_ level: WorkoutEditGuidanceLevel) -> Color {
        switch level {
        case .neutral: .secondary
        case .encouragement: .green
        case .notice: .blue
        case .caution: .orange
        case .strongDiscourage: .red
        }
    }

    // MARK: - Helpers

    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if secs == 0 {
            return "\(mins) min"
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
