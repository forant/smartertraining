import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @State private var showingCheckIn = false
    @State private var showingHistory = false
    @State private var showingRideSession = false
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var editor: WorkoutEditor?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    WorkoutHeroCard(
                        recommendation: appState.currentRecommendation,
                        isModified: editor?.isModified == true,
                        onEdit: hasCyclingSteps ? {
                            ensureEditor()
                            showingEditor = true
                        } : nil
                    )
                    startWorkoutButton
                    coachCallout

                    if !appState.currentRecommendation.optionalExtras.isEmpty {
                        OptionalExtrasCard(extras: appState.currentRecommendation.optionalExtras)
                    }

                    if let checkIn = appState.latestCheckIn {
                        CheckInSummaryCard(checkIn: checkIn)
                    }

                    WorkoutFeedbackCard(
                        selectedFeedback: appState.todayFeedback,
                        onSelect: { appState.submitFeedback($0) }
                    )

                    actionButtons
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingCheckIn) {
                CheckInView()
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingEditor) {
                if let editor {
                    WorkoutEditorView(editor: editor)
                }
            }
            .fullScreenCover(isPresented: $showingRideSession) {
                RideSessionView(
                    recommendation: appState.currentRecommendation,
                    ftp: appState.userProfile.ftp,
                    checkIn: appState.latestCheckIn,
                    recentHistory: appState.recentHistory,
                    profile: appState.userProfile,
                    existingEditor: editor
                )
            }
            .onChange(of: appState.latestCheckIn?.timeAvailable) {
                editor = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(appState.latestCheckIn != nil
                 ? "Here's the right move for today"
                 : "Your plan is ready")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Coach Callout

    private var coachCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            Text(appState.currentRecommendation.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Start Workout

    private var hasCyclingSteps: Bool {
        appState.currentRecommendation.steps.contains { $0.modality == .cycling }
    }

    @ViewBuilder
    private var startWorkoutButton: some View {
        if hasCyclingSteps {
            Button {
                showingRideSession = true
            } label: {
                Label("Start Workout", systemImage: "figure.indoor.cycle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        }
    }

    private func ensureEditor() {
        guard editor == nil else { return }
        let steps = WorkoutConverter.convert(
            recommendation: appState.currentRecommendation,
            ftp: appState.userProfile.ftp
        )
        editor = WorkoutEditor(
            steps: steps,
            workoutType: appState.currentRecommendation.type,
            ftp: appState.userProfile.ftp,
            checkIn: appState.latestCheckIn,
            recentHistory: appState.recentHistory,
            profile: appState.userProfile
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showingCheckIn = true
            } label: {
                Label("Update today's plan", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showingHistory = true
            } label: {
                Label("History", systemImage: "clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.secondary)
        }
        .padding(.top, 4)
    }

}

// MARK: - Workout Hero Card

struct WorkoutHeroCard: View {
    let recommendation: WorkoutRecommendation
    var isModified: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.title)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(recommendation.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isModified {
                Label("Modified from recommendation", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Workout")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                ForEach(Array(recommendation.steps.enumerated()), id: \.offset) { index, step in
                    WorkoutStepRow(step: step)

                    if index < recommendation.steps.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Workout Step Row

struct WorkoutStepRow: View {
    let step: WorkoutStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step.durationText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.tint)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(step.targetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Optional Extras Card

struct OptionalExtrasCard: View {
    let extras: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Also consider")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(extras, id: \.self) { extra in
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(extra)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Check-In Summary Card

struct CheckInSummaryCard: View {
    let checkIn: CheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your check-in", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                summaryItem("Feel", value: checkIn.overallFeel)
                summaryItem("Legs", value: checkIn.legs)
                summaryItem("Motivation", value: checkIn.motivation)
                summaryItem("Time", value: "\(checkIn.timeAvailable) min")
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

            if !checkIn.contextFlags.isEmpty {
                Text(checkIn.contextFlags.joined(separator: " \u{00B7} "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Feedback Card

struct WorkoutFeedbackCard: View {
    let selectedFeedback: WorkoutFeedback?
    let onSelect: (WorkoutFeedback) -> Void

    private let options: [WorkoutFeedback] = [.easy, .right, .hard, .tooMuch]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedFeedback == nil ? "How did this feel?" : "Thanks for the feedback")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selectedFeedback == option
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(spacing: 4) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.label)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - History View

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.recentHistory.isEmpty {
                    ContentUnavailableView(
                        "No recent workouts yet",
                        systemImage: "clock",
                        description: Text("Your recent plans will show up here.")
                    )
                } else {
                    List(appState.recentHistory.reversed().indices, id: \.self) { index in
                        let entry = appState.recentHistory.reversed()[index]
                        HistoryRowView(entry: entry)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: WorkoutHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(entry.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(dateLabel(for: entry.date))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func dateLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    TodayView()
        .environment(AppState())
}

#Preview("After Check-In") {
    let state = AppState()
    state.submit(checkIn: CheckIn(
        overallFeel: "Good",
        legs: "Heavy",
        motivation: "Medium",
        timeAvailable: 45,
        contextFlags: ["Slept poorly"],
        notes: nil
    ))
    return TodayView()
        .environment(state)
}
