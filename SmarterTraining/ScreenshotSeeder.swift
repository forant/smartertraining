#if DEBUG
import Foundation

// MARK: - Seed

/// Snapshot of state the seeder wants to apply. Every field is optional so
/// scenarios only specify what matters; AppState fills the rest from defaults.
struct ScreenshotSeed {
    var profile: UserProfile?
    var checkIn: CheckIn?
    var history: [WorkoutHistoryEntry] = []
    var rides: [CompletedWorkout] = []
    var progressionState: ProgressionState = .empty
    var coachNotes: CoachNotes = .empty
    var approach: TrainingApproach = .default
    var intent: ShortTermTrainingIntent? = nil
    var feedback: WorkoutFeedback? = nil
}

// MARK: - Seeder

enum ScreenshotSeeder {

    /// Parses the current process launch arguments and applies a matching seed,
    /// if any. Called from `AppState.init` under `#if DEBUG`.
    static func applyIfRequested(to appState: AppState, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let scenario = scenario(from: arguments) else { return }
        let seed = build(scenario)
        appState.applyScreenshotSeed(seed)
    }

    static func scenario(from arguments: [String]) -> Scenario? {
        for arg in arguments {
            if let match = Scenario(rawValue: arg) {
                return match
            }
        }
        return nil
    }

    // MARK: - Scenarios

    enum Scenario: String, CaseIterable {
        case todayRecommendation = "-seedTodayRecommendation"
        case adaptiveCoaching = "-seedAdaptiveCoaching"
        case recoveryDay = "-seedRecoveryDay"
        case progression = "-seedProgression"
        case coachSettings = "-seedCoachSettings"
        case postWorkoutSummary = "-seedPostWorkoutSummary"
    }

    static func build(_ scenario: Scenario) -> ScreenshotSeed {
        switch scenario {
        case .todayRecommendation: return todayRecommendationSeed()
        case .adaptiveCoaching: return adaptiveCoachingSeed()
        case .recoveryDay: return recoveryDaySeed()
        case .progression: return progressionSeed()
        case .coachSettings: return coachSettingsSeed()
        case .postWorkoutSummary: return postWorkoutSummarySeed()
        }
    }

    // MARK: A. Today Recommendation
    // Peak readiness on a long-availability athlete who has been consistent. The
    // engine lands on a quality day; "Why This", "What matters today", and
    // "Likely tomorrow" all populate naturally.
    private static func todayRecommendationSeed() -> ScreenshotSeed {
        ScreenshotSeed(
            profile: ScreenshotFactory.powerAthleteProfile(),
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            history: ScreenshotFactory.realisticRecentHistory(),
            rides: [],
            progressionState: ScreenshotFactory.stableProgression(),
            coachNotes: .empty,
            approach: .balanced,
            intent: nil
        )
    }

    // MARK: B. Adaptive Coaching
    // Completed quality workout earlier today + saved coach reflection. Drives
    // the post-workout flow, including likely tomorrow + reflection card.
    private static func adaptiveCoachingSeed() -> ScreenshotSeed {
        let profile = ScreenshotFactory.powerAthleteProfile()
        let cal = Calendar.current
        let workoutStart = cal.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        var ride = ScreenshotFactory.completedThresholdRide(
            startedAt: workoutStart,
            ftp: profile.ftp ?? 240
        )
        ride.coachReflection = ScreenshotFactory.savedReflection(for: ride.id)

        // Today's history entry mirrors the completed ride.
        let todayEntry = WorkoutHistoryEntry(
            date: Date(),
            title: ride.title,
            type: .quality,
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            feedback: .right,
            feedbackAt: Date(),
            qualitySubtype: .threshold
        )
        var history = ScreenshotFactory.realisticRecentHistory()
        history.append(todayEntry)

        return ScreenshotSeed(
            profile: profile,
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            history: history,
            rides: [ride],
            progressionState: ScreenshotFactory.advancedProgression(),
            coachNotes: .empty,
            approach: .ambitious,
            feedback: .right
        )
    }

    // MARK: C. Recovery Day
    // Sustainable approach + low-readiness check-in. Engine returns recovery,
    // the reason copy is calm, and the "What matters today" guidance is
    // recovery-flavored.
    private static func recoveryDaySeed() -> ScreenshotSeed {
        ScreenshotSeed(
            profile: ScreenshotFactory.consistentEnduranceProfile(),
            checkIn: ScreenshotFactory.lowReadinessCheckIn(timeAvailable: 30),
            history: ScreenshotFactory.realisticRecentHistory(),
            rides: [],
            progressionState: ScreenshotFactory.stableProgression(),
            coachNotes: CoachNotes(
                freeformNote: "Sleep has been inconsistent recently.",
                tags: [.poorSleepRecently],
                updatedAt: Date()
            ),
            approach: .sustainable
        )
    }

    // MARK: D. Progression State
    // Athlete is advanced in threshold + VO2, history populated. The engine
    // produces progression-aware copy ("opportunity to push progression slightly"
    // under ambitious, "extend the work" under balanced).
    private static func progressionSeed() -> ScreenshotSeed {
        ScreenshotSeed(
            profile: ScreenshotFactory.powerAthleteProfile(),
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            history: ScreenshotFactory.realisticRecentHistory(),
            rides: [],
            progressionState: ScreenshotFactory.advancedProgression(),
            coachNotes: .empty,
            approach: .ambitious
        )
    }

    // MARK: E. Coach Settings
    // Populated coach notes + a non-default approach so Settings → Coach Settings
    // and the TodayView Coach Notes card both render their "filled" state.
    private static func coachSettingsSeed() -> ScreenshotSeed {
        ScreenshotSeed(
            profile: ScreenshotFactory.consistentEnduranceProfile(),
            checkIn: ScreenshotFactory.moderateCheckIn(timeAvailable: 45),
            history: ScreenshotFactory.realisticRecentHistory(),
            rides: [],
            progressionState: ScreenshotFactory.stableProgression(),
            coachNotes: ScreenshotFactory.realisticCoachNotes(),
            approach: .balanced
        )
    }

    // MARK: F. Post-Workout Summary
    // A completed quality ride with NO saved reflection yet, so RideSessionView's
    // summary phase renders the interactive CoachReflectionCard prompt. TodayView
    // detects the screenshot ride and auto-opens the summary sheet on launch.
    private static func postWorkoutSummarySeed() -> ScreenshotSeed {
        let profile = ScreenshotFactory.powerAthleteProfile()
        let cal = Calendar.current
        let workoutStart = cal.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let ride = ScreenshotFactory.completedThresholdRide(
            startedAt: workoutStart,
            ftp: profile.ftp ?? 240
            // Intentionally no `reflection:` so coachReflection stays nil.
        )

        let todayEntry = WorkoutHistoryEntry(
            date: Date(),
            title: ride.title,
            type: .quality,
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            feedback: .right,
            feedbackAt: Date(),
            qualitySubtype: .threshold
        )
        var history = ScreenshotFactory.realisticRecentHistory()
        history.append(todayEntry)

        return ScreenshotSeed(
            profile: profile,
            checkIn: ScreenshotFactory.freshCheckIn(timeAvailable: 60),
            history: history,
            rides: [ride],
            progressionState: ScreenshotFactory.advancedProgression(),
            coachNotes: .empty,
            approach: .balanced,
            feedback: .right
        )
    }

    // MARK: - Appearance overrides

    enum AppearanceOverride: String, CaseIterable {
        case forceLightMode = "-forceLightMode"
        case forceDarkMode = "-forceDarkMode"
    }

    static func appearanceOverride(from arguments: [String] = ProcessInfo.processInfo.arguments) -> AppearanceOverride? {
        for arg in arguments {
            if let match = AppearanceOverride(rawValue: arg) {
                return match
            }
        }
        return nil
    }
}
#endif
