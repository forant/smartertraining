import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Test Helpers

private let engine = RecommendationEngine()

private func makeProfile(
    currentState: FitnessState? = .consistent,
    goals: [TrainingGoal] = [.endurance],
    availability: TypicalAvailability? = .medium,
    frequency: TrainingFrequency? = .moderate,
    equipment: [Equipment] = [.bikeTrainer],
    ftp: Int? = 250
) -> UserProfile {
    UserProfile(
        name: "Test",
        currentState: currentState,
        goals: goals,
        typicalAvailability: availability,
        trainingFrequency: frequency,
        equipment: equipment,
        ftp: ftp
    )
}

private func makeCheckIn(
    feel: String = "Good",
    legs: String = "Normal",
    motivation: String = "Medium",
    time: Int = 45,
    flags: [String] = [],
    activities: [RecentActivity] = []
) -> CheckIn {
    CheckIn(
        overallFeel: feel,
        legs: legs,
        motivation: motivation,
        timeAvailable: time,
        contextFlags: flags,
        recentActivities: activities
    )
}

private func makeHistory(
    _ entries: [(WorkoutType, WorkoutFeedback?)] = []
) -> [WorkoutHistoryEntry] {
    entries.enumerated().map { index, pair in
        let date = Calendar.current.date(byAdding: .day, value: -(entries.count - index), to: Date()) ?? Date()
        return WorkoutHistoryEntry(
            date: date,
            title: pair.0.label,
            type: pair.0,
            checkIn: nil,
            feedback: pair.1
        )
    }
}

private func makeMemory(
    count7d: Int = 0,
    count14d: Int = 0,
    hardDays: Int = 0,
    recoveryDays: Int = 0,
    daysSince: Int? = nil,
    lastFeedback: WorkoutFeedback? = nil,
    hadTooMuch: Bool = false,
    activities: [RecentActivity] = [],
    stressors: [String] = [],
    load: Double = 0
) -> TrainingMemorySummary {
    TrainingMemorySummary(
        completedWorkoutCount7d: count7d,
        completedWorkoutCount14d: count14d,
        hardDayCount7d: hardDays,
        recoveryDayCount7d: recoveryDays,
        daysSinceLastWorkout: daysSince,
        lastWorkoutFeedback: lastFeedback,
        hadTooMuchFeedback7d: hadTooMuch,
        recentActivities: activities,
        recentLifeStressors: stressors,
        recentIntensityLoadEstimate: load
    )
}

private func inputs(
    profile: UserProfile = makeProfile(),
    checkIn: CheckIn = makeCheckIn(),
    history: [WorkoutHistoryEntry] = [],
    memory: TrainingMemorySummary = .empty
) -> RecommendationEngine.Inputs {
    RecommendationEngine.Inputs(
        profile: profile,
        checkIn: checkIn,
        recentHistory: history,
        memorySummary: memory
    )
}

// MARK: - Training Memory Builder Tests

struct TrainingMemoryBuilderTests {

    @Test func emptyHistoryProducesEmptySummary() {
        let summary = TrainingMemoryBuilder.build(history: [])
        #expect(summary.completedWorkoutCount7d == 0)
        #expect(summary.completedWorkoutCount14d == 0)
        #expect(summary.daysSinceLastWorkout == nil)
        #expect(summary.hardDayCount7d == 0)
    }

    @Test func countsWorkoutsInTimeWindows() {
        let now = Date()
        let cal = Calendar.current
        let entries = [
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -1, to: now)!, title: "A", type: .endurance),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -3, to: now)!, title: "B", type: .quality),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -5, to: now)!, title: "C", type: .endurance),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -10, to: now)!, title: "D", type: .recovery),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -20, to: now)!, title: "E", type: .quality),
        ]
        let summary = TrainingMemoryBuilder.build(history: entries, now: now)
        #expect(summary.completedWorkoutCount7d == 3)
        #expect(summary.completedWorkoutCount14d == 4)
    }

    @Test func countsHardAndRecoveryDays() {
        let now = Date()
        let cal = Calendar.current
        let entries = [
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -1, to: now)!, title: "A", type: .quality),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -2, to: now)!, title: "B", type: .endurance, feedback: .hard),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -3, to: now)!, title: "C", type: .recovery),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -4, to: now)!, title: "D", type: .endurance, feedback: .tooMuch),
        ]
        let summary = TrainingMemoryBuilder.build(history: entries, now: now)
        #expect(summary.hardDayCount7d == 3)
        #expect(summary.recoveryDayCount7d == 1)
        #expect(summary.hadTooMuchFeedback7d == true)
    }

    @Test func computesDaysSinceLastWorkout() {
        let now = Date()
        let cal = Calendar.current
        let entries = [
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -3, to: now)!, title: "A", type: .endurance),
        ]
        let summary = TrainingMemoryBuilder.build(history: entries, now: now)
        #expect(summary.daysSinceLastWorkout == 3)
    }

    @Test func computesIntensityLoadEstimate() {
        let now = Date()
        let cal = Calendar.current
        let entries = [
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -1, to: now)!, title: "A", type: .quality),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -2, to: now)!, title: "B", type: .endurance),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -3, to: now)!, title: "C", type: .recovery),
        ]
        let summary = TrainingMemoryBuilder.build(history: entries, now: now)
        #expect(summary.recentIntensityLoadEstimate == 6.0)
    }

    @Test func aggregatesRecentActivitiesFromCheckIns() {
        let now = Date()
        let cal = Calendar.current
        let checkIn1 = CheckIn(
            overallFeel: "Good", legs: "Normal", motivation: "Medium",
            timeAvailable: 45, contextFlags: ["Poor sleep"],
            recentActivities: [RecentActivity(type: "Tennis", timing: "Yesterday", intensity: "Hard")]
        )
        let checkIn2 = CheckIn(
            overallFeel: "Good", legs: "Normal", motivation: "Medium",
            timeAvailable: 45, contextFlags: ["High work stress"],
            recentActivities: [RecentActivity(type: "Strength training", timing: "Today", intensity: "Moderate")]
        )
        let entries = [
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -1, to: now)!, title: "A", type: .endurance, checkIn: checkIn1),
            WorkoutHistoryEntry(date: cal.date(byAdding: .day, value: -2, to: now)!, title: "B", type: .endurance, checkIn: checkIn2),
        ]
        let summary = TrainingMemoryBuilder.build(history: entries, now: now)
        #expect(summary.recentActivities.count == 2)
        #expect(summary.recentLifeStressors.contains("Poor sleep"))
        #expect(summary.recentLifeStressors.contains("High work stress"))
    }
}

// MARK: - Recommendation Continuity Tests

struct RecommendationContinuityTests {

    @Test func recentHardLoadBlocksQuality() {
        let memory = makeMemory(count7d: 5, hardDays: 3, daysSince: 0, load: 11)
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil), (.endurance, nil)]),
            memory: memory
        ))
        #expect(type != .quality)
    }

    @Test func tooMuchFeedbackCarriesAcrossHistory() {
        let history = makeHistory([(.quality, .tooMuch), (.endurance, .right), (.endurance, .right)])

        let typeNoMemory = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(typeNoMemory == .quality)

        let memory = makeMemory(count7d: 3, hardDays: 1, hadTooMuch: true)
        let typeWithMemory = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history,
            memory: memory
        ))
        #expect(typeWithMemory != .quality)
    }

    @Test func inactivityLeadsToGentleRestart() {
        let memory = makeMemory(daysSince: 6)

        let type1 = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium"),
            memory: memory
        ))
        #expect(type1 == .recovery)

        let type2 = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            memory: memory
        ))
        #expect(type2 == .endurance)
    }

    @Test func consistentTrainingAllowsRecoveryWithoutGuilt() {
        let memory = makeMemory(count7d: 4, hardDays: 1, daysSince: 0, load: 7)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low"),
            memory: memory
        )
        let type = engine.chooseWorkoutType(for: i)
        #expect(type == .recovery)

        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("consistent") || reason.contains("showing up"))
    }

    @Test func recentHardActivityAffectsRecommendation() {
        let profile = makeProfile(goals: [.consistent])
        let history = makeHistory([(.endurance, nil)])

        let typeNoMemory = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(typeNoMemory == .quality)

        let memory = makeMemory(
            count7d: 2,
            activities: [RecentActivity(type: "Tennis", timing: "Today", intensity: "Hard")]
        )
        let typeWithMemory = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history,
            memory: memory
        ))
        #expect(typeWithMemory != .quality)
    }

    @Test func goodReadinessLowLoadAllowsQuality() {
        let memory = makeMemory(count7d: 2, hardDays: 0, daysSince: 1, load: 4)
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil), (.endurance, nil)]),
            memory: memory
        ))
        #expect(type == .quality)
    }
}

// MARK: - Memory-Aware Reasons Tests

struct MemoryAwareReasonTests {

    @Test func enduranceReasonMentionsHighWeekLoad() {
        let memory = makeMemory(count7d: 5, hardDays: 3)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal"),
            memory: memory
        )
        let reason = engine.buildReason(type: .endurance, inputs: i)
        #expect(reason.contains("harder days this week"))
    }

    @Test func recoveryReasonPositiveWhenConsistent() {
        let memory = makeMemory(count7d: 4, daysSince: 0)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal"),
            history: makeHistory([(.endurance, nil), (.endurance, nil), (.endurance, nil)]),
            memory: memory
        )
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("consistent") || reason.contains("showing up"))
    }

    @Test func enduranceReasonMentionsInactivity() {
        let memory = makeMemory(daysSince: 6)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh"),
            memory: memory
        )
        let reason = engine.buildReason(type: .endurance, inputs: i)
        #expect(reason.contains("days off"))
    }

    @Test func enduranceReasonMentionsMemoryActivity() {
        let memory = makeMemory(
            count7d: 2,
            activities: [RecentActivity(type: "Tennis", timing: "Today", intensity: "Hard")]
        )
        let i = inputs(checkIn: makeCheckIn(feel: "Good"), memory: memory)
        let reason = engine.buildReason(type: .endurance, inputs: i)
        #expect(reason.contains("tennis"))
    }

    @Test func recoveryReasonMentionsInactivity() {
        let memory = makeMemory(daysSince: 7)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Good"),
            memory: memory
        )
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("days off") || reason.contains("momentum"))
    }
}

// MARK: - Memory Helper Tests

struct MemoryHelperTests {

    @Test func memoryActivityStressFromHardActivity() {
        let memory = makeMemory(
            activities: [RecentActivity(type: "Tennis", timing: "Today", intensity: "Hard")]
        )
        #expect(engine.memoryActivityStress(memory) == 1)
    }

    @Test func memoryActivityStressFromVeryHardActivity() {
        let memory = makeMemory(
            activities: [RecentActivity(type: "MTB ride", timing: "Yesterday", intensity: "Very hard")]
        )
        #expect(engine.memoryActivityStress(memory) == 2)
    }

    @Test func memoryActivityStressFromMultipleHard() {
        let memory = makeMemory(
            activities: [
                RecentActivity(type: "Tennis", timing: "Today", intensity: "Hard"),
                RecentActivity(type: "Strength training", timing: "Yesterday", intensity: "Hard")
            ]
        )
        #expect(engine.memoryActivityStress(memory) == 2)
    }

    @Test func emptyMemoryHasNoActivityStress() {
        #expect(engine.memoryActivityStress(.empty) == 0)
    }

    @Test func lifeStressLevelFromStressors() {
        let memory = makeMemory(stressors: ["Poor sleep", "High work stress", "Other"])
        #expect(memory.recentLifeStressLevel == 2)
    }

    @Test func returningAfterBreakDetection() {
        #expect(makeMemory(daysSince: 5).isReturningAfterBreak)
        #expect(makeMemory(daysSince: 10).isReturningAfterBreak)
        #expect(!makeMemory(daysSince: 3).isReturningAfterBreak)
        #expect(!makeMemory(daysSince: nil).isReturningAfterBreak)
    }

    @Test func highRecentLoadDetection() {
        #expect(makeMemory(hardDays: 3).hasHighRecentLoad)
        #expect(!makeMemory(hardDays: 2).hasHighRecentLoad)
        #expect(!makeMemory(hardDays: 0).hasHighRecentLoad)
    }
}
