import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    var subscriptionService: SubscriptionService?
    @State private var showingCheckIn = false
    @State private var showingHistory = false
    @State private var showingRideSession = false
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var showingUpcomingContextAdd = false
    @State private var editingUpcomingContextEvent: UpcomingContextEvent?
    @State private var editor: WorkoutEditor?
    @State private var aiCoach = AICoachService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header

                    WorkoutHeroCard(
                        recommendation: appState.currentRecommendation,
                        isModified: editor?.isModified == true,
                        hasCyclingSteps: hasCyclingSteps,
                        onStart: {
                            AnalyticsService.shared.track(.workoutStartTapped, properties: [
                                "workout_type": appState.currentRecommendation.type.rawValue
                            ])
                            showingRideSession = true
                        },
                        onEdit: hasCyclingSteps ? {
                            ensureEditor()
                            showingEditor = true
                            AnalyticsService.shared.track(.workoutEditorOpened)
                        } : nil
                    )
                    .animation(.easeInOut(duration: 0.3), value: appState.currentRecommendation.type)
                    .animation(.easeInOut(duration: 0.3), value: appState.currentRecommendation.title)

                    coachExplanationCard

                    WorkoutBreakdownCard(steps: appState.currentRecommendation.steps)

                    WorkoutFeedbackCard(
                        selectedFeedback: appState.todayFeedback,
                        onSelect: { appState.submitFeedback($0) }
                    )

                    UpcomingContextCard(
                        onAdd: { showingUpcomingContextAdd = true },
                        onEdit: { editingUpcomingContextEvent = $0 }
                    )

                    if !appState.currentRecommendation.optionalExtras.isEmpty {
                        OptionalExtrasCard(extras: appState.currentRecommendation.optionalExtras)
                    }

                    if let checkIn = appState.latestCheckIn {
                        CheckInSummaryCard(checkIn: checkIn) {
                            showingCheckIn = true
                        }
                    }

                    historyButton
                }
                .padding()
            }
            .background(Theme.Surface.background)
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
                SettingsView(subscriptionService: subscriptionService)
            }
            .sheet(isPresented: $showingEditor) {
                if let editor {
                    WorkoutEditorView(editor: editor)
                }
            }
            .sheet(isPresented: $showingUpcomingContextAdd) {
                UpcomingContextSheet()
            }
            .sheet(item: $editingUpcomingContextEvent) { event in
                UpcomingContextSheet(editingEvent: event)
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
            .task(id: appState.lastCheckInDate) {
                await fetchAIExplanation()
            }
            .onChange(of: appState.latestCheckIn?.timeAvailable) {
                editor = nil
                aiCoach.invalidateCache()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Today")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(appState.latestCheckIn != nil
                 ? "Here\u{2019}s the right move for today"
                 : "Your plan is ready")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Coach Explanation

    private var coachExplanationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WHY THIS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Brand.primary)
                .tracking(0.5)

            Text(appState.currentRecommendation.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let ai = aiCoach.explanation, !ai.isFallback, let tomorrow = ai.tomorrowImplication {
                Text(tomorrow)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
        .animation(.easeIn(duration: 0.3), value: aiCoach.explanation?.tomorrowImplication)
    }

    private func fetchAIExplanation() async {
        let summary = TrainingMemoryBuilder.build(
            history: appState.recentHistory,
            rides: appState.store.finishedRides()
        )
        await aiCoach.fetchExplanation(
            recommendation: appState.currentRecommendation,
            checkIn: appState.latestCheckIn,
            memorySummary: summary,
            lastFeedback: appState.todayFeedback,
            editedWorkout: editor?.isModified == true,
            upcomingContext: appState.upcomingContextSummary,
            auth: appState.auth
        )
    }

    // MARK: - Helpers

    private var hasCyclingSteps: Bool {
        appState.currentRecommendation.steps.contains { $0.modality == .cycling || $0.modality == .recovery }
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

    // MARK: - History Button

    private var historyButton: some View {
        Button {
            showingHistory = true
        } label: {
            Text("View history")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Workout Hero Card

struct WorkoutHeroCard: View {
    let recommendation: WorkoutRecommendation
    var isModified: Bool = false
    var hasCyclingSteps: Bool = false
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("FITS YOUR DAY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.TextStyle.onBrandSecondary)
                    .tracking(0.8)

                Spacer()

                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(Theme.TextStyle.onBrandSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(recommendation.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.TextStyle.onBrand)

                Text(recommendation.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.TextStyle.onBrandSecondary)
            }

            if isModified {
                Label("Modified from recommendation", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(Theme.TextStyle.onBrandSecondary)
            }

            if hasCyclingSteps, let onStart {
                Button(action: onStart) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "figure.indoor.cycle")
                            .font(.subheadline)
                        Text("Start Workout")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(.white)
                    .foregroundStyle(Theme.Brand.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(Theme.Brand.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
    }
}

// MARK: - Workout Breakdown Card

struct WorkoutBreakdownCard: View {
    let steps: [WorkoutStep]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WORKOUT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.5)
                .padding(.bottom, Theme.Spacing.xs)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                WorkoutStepRow(step: step)

                if index < steps.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
    }
}

// MARK: - Workout Step Row

struct WorkoutStepRow: View {
    let step: WorkoutStep

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(step.durationText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Brand.primary)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Also helpful today")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            ForEach(extras, id: \.self) { extra in
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(extra)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
    }
}

// MARK: - Check-In Summary Card

struct CheckInSummaryCard: View {
    let checkIn: CheckIn
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Today\u{2019}s check-in")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                HStack(spacing: 6) {
                    Text("\(checkIn.overallFeel) \u{00B7} \(checkIn.legs) legs \u{00B7} \(checkIn.motivation) motivation \u{00B7} \(checkIn.timeAvailable) min")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary.opacity(0.7))
                }

                if !checkIn.contextFlags.isEmpty {
                    Text(checkIn.contextFlags.joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's check-in: \(checkIn.overallFeel) feeling, \(checkIn.legs) legs, \(checkIn.motivation) motivation, \(checkIn.timeAvailable) minutes")
        .accessibilityHint("Tap to update your check-in")
    }
}

// MARK: - Workout Feedback Card

struct WorkoutFeedbackCard: View {
    let selectedFeedback: WorkoutFeedback?
    let onSelect: (WorkoutFeedback) -> Void

    @State private var isExpanded = true

    private let options: [WorkoutFeedback] = [.easy, .right, .hard, .tooMuch]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let selected = selectedFeedback, !isExpanded {
                collapsedState(selected)
            } else {
                expandedState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
        .animation(.easeInOut(duration: 0.25), value: selectedFeedback)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .onChange(of: selectedFeedback) {
            if selectedFeedback != nil {
                isExpanded = false
            }
        }
    }

    private func collapsedState(_ feedback: WorkoutFeedback) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(feedback.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(collapsedLabel(feedback))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Thanks for the feedback")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                isExpanded = true
            } label: {
                Text("Change")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Brand.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private var expandedState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How did this feel?")
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
                        .background(isSelected ? Theme.Surface.selectedControl : Theme.Surface.unselectedControl)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(isSelected ? Theme.Border.selected : .clear, lineWidth: Theme.Border.selectedWidth)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func collapsedLabel(_ feedback: WorkoutFeedback) -> String {
        switch feedback {
        case .easy: "This was easy"
        case .right: "This was just right"
        case .hard: "This was hard"
        case .tooMuch: "This was too much"
        }
    }
}

// MARK: - History View

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var rides: [CompletedWorkout] = []

    var body: some View {
        NavigationStack {
            Group {
                if appState.recentHistory.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock",
                        description: Text("Your training story will build here.")
                    )
                } else {
                    List {
                        ForEach(appState.recentHistory.reversed()) { entry in
                            NavigationLink {
                                WorkoutDetailView(entry: entry, ride: rideForEntry(entry))
                            } label: {
                                HistoryRowView(entry: entry)
                            }
                            .listRowSeparator(.hidden)
                        }
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
            .task { rides = appState.store.finishedRides() }
        }
    }

    private func rideForEntry(_ entry: WorkoutHistoryEntry) -> CompletedWorkout? {
        rides.first { Calendar.current.isDate($0.startDate, inSameDayAs: entry.date) }
    }
}

struct HistoryRowView: View {
    let entry: WorkoutHistoryEntry

    private var isCompleted: Bool { entry.feedback != nil }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isCompleted ? Theme.Semantic.recovery : Color(.quaternaryLabel))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(isCompleted ? .medium : .regular)
                    .foregroundStyle(isCompleted ? .primary : .secondary)

                HStack(spacing: 6) {
                    Text(entry.type.label)
                        .font(.caption)
                        .foregroundStyle(isCompleted ? .secondary : .tertiary)

                    if let feedback = entry.feedback {
                        Text(feedback.emoji)
                            .font(.caption2)
                    }
                }
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
