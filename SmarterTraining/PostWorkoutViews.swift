import SwiftUI

// MARK: - Feedback Capture

struct PostWorkoutFeedbackView: View {
    @Binding var feedback: WorkoutFeedback?
    @Binding var perceivedEffort: Int?
    @Binding var note: String
    let onDone: () -> Void

    private let feedbackOptions: [WorkoutFeedback] = [.easy, .right, .hard, .tooMuch]

    var body: some View {
        VStack(spacing: 28) {
            Text("How did that feel?")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 10) {
                ForEach(feedbackOptions, id: \.self) { option in
                    let isSelected = feedback == option
                    Button {
                        feedback = option
                    } label: {
                        VStack(spacing: 6) {
                            Text(option.emoji)
                                .font(.title2)
                            Text(option.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 12) {
                Text("Effort level")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                effortPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Anything worth noting?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                onDone()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(feedback == nil)
        }
        .padding(24)
    }

    private var effortPicker: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(1...10, id: \.self) { level in
                    let isSelected = perceivedEffort == level
                    Button {
                        perceivedEffort = level
                    } label: {
                        Text("\(level)")
                            .font(.subheadline)
                            .fontWeight(isSelected ? .bold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? effortColor(level).opacity(0.2) : Color(.systemGray6))
                            .foregroundStyle(isSelected ? effortColor(level) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("Very easy")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Steady")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Max effort")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func effortColor(_ level: Int) -> Color {
        switch level {
        case 1...3: .green
        case 4...6: .blue
        case 7...8: .orange
        case 9...10: .red
        default: .primary
        }
    }
}

// MARK: - Session Summary

struct PostWorkoutSummaryCard: View {
    let workout: CompletedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session summary")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statItem("Duration", value: formatDuration(workout.duration))

                if let avg = workout.averagePower {
                    statItem("Avg Power", value: "\(avg)W")
                }
                if let max = workout.maxPower {
                    statItem("Max Power", value: "\(max)W")
                }
                if let avgCad = workout.averageCadence {
                    statItem("Avg Cadence", value: "\(avgCad)")
                }
                if let avgHR = workout.averageHeartRate {
                    statItem("Avg HR", value: "\(avgHR)")
                }
                if let maxHR = workout.maxHeartRate {
                    statItem("Max HR", value: "\(maxHR)")
                }
            }

            HStack(spacing: 16) {
                if let erg = workout.ergWasEnabled {
                    Label(erg ? "ERG on" : "ERG off", systemImage: erg ? "bolt.fill" : "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if workout.isPostedToStrava {
                    Label("Strava", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if workout.healthKitSaveStatus == .saved {
                    Label("Health", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Reflection Display

struct PostWorkoutReflectionCard: View {
    let reflection: PostWorkoutReflection
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                Text("Coach reflection")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(reflection.sessionEvaluation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let well = reflection.whatWentWell {
                reflectionRow(icon: "checkmark.circle", color: .green, text: well)
            }

            if let watch = reflection.watchOut {
                reflectionRow(icon: "exclamationmark.triangle", color: .orange, text: watch)
            }

            if !reflection.nextTwoDays.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Next two days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)

                    ForEach(reflection.nextTwoDays, id: \.dayLabel) { day in
                        HStack(alignment: .top, spacing: 10) {
                            intensityDot(day.recommendedIntensity)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.dayLabel)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(day.guidance)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func reflectionRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func intensityDot(_ intensity: String) -> some View {
        Circle()
            .fill(colorForIntensity(intensity))
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }

    private func colorForIntensity(_ intensity: String) -> Color {
        switch intensity {
        case "rest": .gray
        case "recovery": .green
        case "endurance": .blue
        case "quality": .orange
        default: .secondary
        }
    }
}

// MARK: - Loading Placeholder

struct ReflectionLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Thinking through what this means\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
