import SwiftUI

struct WorkoutDetailView: View {
    let entry: WorkoutHistoryEntry
    let ride: CompletedWorkout?
    var likelyTomorrow: LikelyWorkoutPreview? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if let ride, ride.duration > 0 {
                    sessionStatsSection(ride)
                }

                if let ride, !ride.samples.isEmpty {
                    WorkoutChartsSection(workout: ride)
                }

                if let reflection = ride?.reflection {
                    reflectionSection(reflection)
                } else if let likelyTomorrow {
                    LikelyTomorrowCard(preview: likelyTomorrow)
                }

                if let coachReflection = ride?.coachReflection {
                    SavedCoachReflectionCard(reflection: coachReflection)
                }

                if entry.feedback != nil || ride?.perceivedEffort != nil || ride?.postWorkoutNote != nil {
                    feedbackSection
                }

                if let checkIn = entry.checkIn {
                    checkInSection(checkIn)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 10) {
                Text(entry.type.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(typeColor.opacity(0.12))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())

                if let subtype = entry.qualitySubtype {
                    Text(subtype.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(typeColor.opacity(0.08))
                        .foregroundStyle(typeColor.opacity(0.85))
                        .clipShape(Capsule())
                }

                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session Stats

    private func sessionStatsSection(_ ride: CompletedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statItem("Duration", value: formatDuration(ride.duration))

                if let avg = ride.averagePower {
                    statItem("Avg Power", value: "\(avg)W")
                }
                if let max = ride.maxPower {
                    statItem("Max Power", value: "\(max)W")
                }
                if let avgHR = ride.averageHeartRate {
                    statItem("Avg HR", value: "\(avgHR)")
                }
                if let maxHR = ride.maxHeartRate {
                    statItem("Max HR", value: "\(maxHR)")
                }
                if let avgCad = ride.averageCadence {
                    statItem("Cadence", value: "\(avgCad)")
                }
            }

            HStack(spacing: 14) {
                if let erg = ride.ergWasEnabled {
                    Label(erg ? "ERG" : "Guided", systemImage: erg ? "bolt.fill" : "bolt.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if ride.isPostedToStrava {
                    Label("Strava", systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if ride.healthKitSaveStatus == .saved {
                    Label("Health", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Coach Reflection

    private func reflectionSection(_ reflection: PostWorkoutReflection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                Text("Coach reflection")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
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

            if let likelyTomorrow {
                Divider()
                LikelyTomorrowCard(preview: likelyTomorrow)
            } else if !reflection.nextTwoDays.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Next two days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)

                    ForEach(reflection.nextTwoDays, id: \.dayLabel) { day in
                        HStack(alignment: .top, spacing: 8) {
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

    // MARK: - User Feedback

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your feedback")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            HStack(spacing: 16) {
                if let feedback = entry.feedback ?? ride?.workoutFeedback {
                    HStack(spacing: 6) {
                        Text(feedback.emoji)
                            .font(.title3)
                        Text(feedback.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                if let effort = ride?.perceivedEffort {
                    HStack(spacing: 4) {
                        Text("\(effort)/10")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Text("effort")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let note = ride?.postWorkoutNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Check-In Context

    private func checkInSection(_ checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How you felt")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            Text("\(checkIn.overallFeel) \u{00B7} \(checkIn.legs) \u{00B7} \(checkIn.motivation) \u{00B7} \(checkIn.timeAvailable) min")
                .font(.subheadline)

            if !checkIn.contextFlags.isEmpty {
                Text(checkIn.contextFlags.joined(separator: " \u{00B7} "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !checkIn.recentActivities.isEmpty {
                let summary = checkIn.recentActivities.map { a in
                    var parts = [a.type]
                    if let t = a.timing { parts.append(t.lowercased()) }
                    if let i = a.intensity { parts.append(i.lowercased()) }
                    return parts.joined(separator: " \u{00B7} ")
                }.joined(separator: ", ")
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private var typeColor: Color {
        switch entry.type {
        case .recovery: Theme.Semantic.recovery
        case .endurance: Theme.Semantic.endurance
        case .quality: Theme.Semantic.quality
        }
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(entry.date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(entry.date) {
            return "Yesterday"
        } else {
            return entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
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

    private func reflectionRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
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
        case "endurance": Theme.Semantic.endurance
        case "quality": .orange
        default: .secondary
        }
    }
}
