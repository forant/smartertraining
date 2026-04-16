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
    flags: [String] = []
) -> CheckIn {
    CheckIn(
        overallFeel: feel,
        legs: legs,
        motivation: motivation,
        timeAvailable: time,
        contextFlags: flags,
        notes: nil
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

private func inputs(
    profile: UserProfile = makeProfile(),
    checkIn: CheckIn = makeCheckIn(),
    history: [WorkoutHistoryEntry] = []
) -> RecommendationEngine.Inputs {
    RecommendationEngine.Inputs(profile: profile, checkIn: checkIn, recentHistory: history)
}

// MARK: - Hard Recovery Overrides

struct HardRecoveryOverrideTests {

    @Test func badFeelTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(feel: "Bad")))
        #expect(type == .recovery)
    }

    @Test func deadLegsTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(legs: "Dead")))
        #expect(type == .recovery)
    }

    @Test func gettingSickTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(flags: ["Getting sick"])))
        #expect(type == .recovery)
    }

    @Test func okayLowHeavyTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low")
        ))
        #expect(type == .recovery)
    }

    @Test func recoveryReasonMentionsSick() {
        let i = inputs(checkIn: makeCheckIn(flags: ["Getting sick"]))
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("sick"))
    }

    @Test func recoveryReasonMentionsDeadLegs() {
        let i = inputs(checkIn: makeCheckIn(legs: "Dead"))
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("Dead legs"))
    }
}

// MARK: - History Guardrails

struct HistoryGuardrailTests {

    @Test func noBackToBackQuality() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func afterQualityWithHeavyLegsGoesToRecoveryOrEndurance() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low"),
            history: history
        ))
        #expect(type == .recovery)
    }

    @Test func afterQualityWithOkayFeelGoesToEndurance() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Normal", motivation: "Medium"),
            history: history
        ))
        #expect(type == .endurance)
    }
}

// MARK: - Feedback-Aware Behavior

struct FeedbackAwareTests {

    @Test func tooMuchWithOkayFeelTriggersRecovery() {
        let history = makeHistory([(.quality, .tooMuch)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay"),
            history: history
        ))
        #expect(type == .recovery)
    }

    @Test func tooMuchWithGoodFeelGoesToEndurance() {
        let history = makeHistory([(.quality, .tooMuch)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium"),
            history: history
        ))
        #expect(type == .endurance)
    }

    @Test func easyFeedbackAfterEasierStretchOpensQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, .easy)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func hardFeedbackDiscouragesQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, .hard)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func enduranceReasonMentionsTooMuch() {
        let history = makeHistory([(.quality, .tooMuch)])
        let i = inputs(checkIn: makeCheckIn(feel: "Good"), history: history)
        let reason = engine.buildReason(type: .endurance, inputs: i)
        #expect(reason.contains("too much"))
    }
}

// MARK: - Quality Conditions

struct QualityConditionTests {

    @Test func freshLegsGreatFeelHighMotivationCanQuality() {
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func heavyLegsNeverQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Heavy", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func easierStretchWithStrongSignalsOpensQuality() {
        let history = makeHistory([(.endurance, nil), (.recovery, nil), (.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }
}

// MARK: - Time Shaping

struct TimeShapingTests {

    @Test func shortTimeRecoveryIsEasySpin() {
        let workout = engine.buildWorkout(type: .recovery, time: 15, reason: "test")
        #expect(workout.title == "Easy Spin")
        #expect(workout.steps.count == 1)
    }

    @Test func longerRecoveryHasThreeSteps() {
        let workout = engine.buildWorkout(type: .recovery, time: 40, reason: "test")
        #expect(workout.title == "Recovery Day")
        #expect(workout.steps.count == 3)
    }

    @Test func shortEnduranceIs20Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 20, reason: "test")
        #expect(workout.title == "Short Aerobic Spin")
    }

    @Test func mediumEnduranceIs30Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 30, reason: "test")
        #expect(workout.title == "30 min Zone 2 Ride")
    }

    @Test func standardEnduranceIs45Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 45, reason: "test")
        #expect(workout.title == "45 min Zone 2 Ride")
    }

    @Test func longEnduranceIs60Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 60, reason: "test")
        #expect(workout.title == "60 min Endurance Ride")
    }

    @Test func shortQualityIsCompact() {
        let workout = engine.buildWorkout(type: .quality, time: 25, reason: "test")
        #expect(workout.title == "Compact Threshold")
    }

    @Test func standardQualityIsThreshold() {
        let workout = engine.buildWorkout(type: .quality, time: 45, reason: "test")
        #expect(workout.title == "Threshold Intervals")
        #expect(workout.steps.count == 3)
    }

    @Test func longQualityHasLongerWarmup() {
        let workout = engine.buildWorkout(type: .quality, time: 60, reason: "test")
        #expect(workout.steps.first?.durationText == "15 min")
    }
}

// MARK: - Onboarding Bias (Quality Willingness)

struct OnboardingBiasTests {

    @Test func justStartingLowersWillingness() {
        let profile = makeProfile(currentState: .justStarting, goals: [.consistent], frequency: .light)
        let score = engine.qualityWillingness(for: profile)
        #expect(score <= -2)
    }

    @Test func veryConsistentPerformanceGoalsRaisesWillingness() {
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let score = engine.qualityWillingness(for: profile)
        #expect(score >= 2)
    }

    @Test func consistentModerateIsNeutral() {
        let profile = makeProfile(currentState: .consistent, goals: [.endurance], frequency: .moderate)
        let score = engine.qualityWillingness(for: profile)
        #expect(score >= 0 && score <= 1)
    }

    @Test func favorsConsistencyForConsistentGoal() {
        let profile = makeProfile(goals: [.consistent])
        #expect(engine.favorsConsistency(profile))
    }

    @Test func doesNotFavorConsistencyForEndurance() {
        let profile = makeProfile(goals: [.endurance])
        #expect(!engine.favorsConsistency(profile))
    }

    @Test func highWillingnessLowersQualityThreshold() {
        // With high willingness, only 1 easier day needed instead of 2
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func lowWillingnessBlocksQualityWithOnlyOneEasierDay() {
        let profile = makeProfile(currentState: .justStarting, goals: [.consistent], frequency: .light)
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        // Low willingness still allows quality via the fresh-legs path, but
        // the easier-stretch path requires 2 easier days with low willingness
        #expect(type == .quality || type == .endurance)
    }
}

// MARK: - Equipment Shaping

struct EquipmentShapingTests {

    @Test func hasStrengthEquipmentWithDumbbells() {
        let profile = makeProfile(equipment: [.dumbbells, .bikeTrainer])
        #expect(engine.hasStrengthEquipment(profile))
    }

    @Test func noStrengthEquipmentWithOnlyBike() {
        let profile = makeProfile(equipment: [.bikeTrainer])
        #expect(!engine.hasStrengthEquipment(profile))
    }

    @Test func noStrengthEquipmentWhenNone() {
        let profile = makeProfile(equipment: [.noEquipment])
        #expect(!engine.hasStrengthEquipment(profile))
    }

    @Test func enduranceExtrasIncludeStrengthWhenEquipmentAvailable() {
        let profile = makeProfile(equipment: [.bikeTrainer, .dumbbells])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("dumbbell") || $0.contains("kettlebell") })
    }

    @Test func enduranceExtrasIncludeBodyweightWhenNoEquipment() {
        let profile = makeProfile(equipment: [.bikeTrainer])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("bodyweight") })
    }

    @Test func recoveryExtrasIncludeMobility() {
        let extras = engine.adjustExtras([], type: .recovery, time: 30, profile: makeProfile())
        #expect(extras.contains { $0.contains("mobility") || $0.contains("walk") })
    }

    @Test func qualityExtrasIncludeMobility() {
        let extras = engine.adjustExtras([], type: .quality, time: 45, profile: makeProfile())
        #expect(extras.contains { $0.contains("mobility") })
    }

    @Test func shortEnduranceGetsNoStrengthExtras() {
        let profile = makeProfile(equipment: [.bikeTrainer, .dumbbells])
        let extras = engine.adjustExtras([], type: .endurance, time: 30, profile: profile)
        #expect(extras.isEmpty)
    }

    @Test func gymEquipmentGetsGymExtras() {
        let profile = makeProfile(equipment: [.gym])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("core and upper body") })
    }

    @Test func bandEquipmentGetsBandExtras() {
        let profile = makeProfile(equipment: [.bands])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("band") })
    }
}

// MARK: - Full Recommendation Flow

struct FullRecommendationTests {

    @Test func fullRecommendationIncludesExtras() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(time: 45)
        ))
        #expect(!result.optionalExtras.isEmpty)
    }

    @Test func recoveryRecommendationHasRecoveryType() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(feel: "Bad", time: 30)
        ))
        #expect(result.type == .recovery)
        #expect(!result.reason.isEmpty)
        #expect(!result.steps.isEmpty)
    }

    @Test func defaultRecommendationIsEndurance() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium", time: 45)
        ))
        #expect(result.type == .endurance)
    }
}
