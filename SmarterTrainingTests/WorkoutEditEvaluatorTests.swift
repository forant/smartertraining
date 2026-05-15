import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Test Helpers

private func makeSteps(
    _ specs: [(name: String, duration: TimeInterval, power: Int, role: WorkoutStepRole)]
) -> [TrainerWorkoutStep] {
    specs.map { TrainerWorkoutStep(name: $0.name, duration: $0.duration, targetPower: $0.power, role: $0.role) }
}

private let recoveryOriginal = makeSteps([
    ("Warm-up", 300, 80, .warmup),
    ("Easy spin", 1200, 90, .primary),
    ("Cool down", 300, 70, .cooldown)
])

private let enduranceOriginal = makeSteps([
    ("Warm-up", 300, 120, .warmup),
    ("Main", 2100, 175, .primary),
    ("Cool down", 300, 100, .cooldown)
])

private let qualityOriginal = makeSteps([
    ("Warm-up", 600, 130, .warmup),
    ("Interval 1 of 4", 240, 250, .primary),
    ("Recovery", 120, 100, .cooldown),
    ("Interval 2 of 4", 240, 250, .primary),
    ("Recovery", 120, 100, .cooldown),
    ("Interval 3 of 4", 240, 250, .primary),
    ("Recovery", 120, 100, .cooldown),
    ("Interval 4 of 4", 240, 250, .primary),
    ("Cool down", 300, 100, .cooldown)
])

private func scaleSteps(_ steps: [TrainerWorkoutStep], powerFactor: Double = 1.0, durationFactor: Double = 1.0) -> [TrainerWorkoutStep] {
    steps.map {
        TrainerWorkoutStep(
            name: $0.name,
            duration: $0.duration * durationFactor,
            targetPower: Int(Double($0.targetPower) * powerFactor),
            role: $0.role
        )
    }
}

private func evaluator(
    type: WorkoutType = .endurance,
    original: [TrainerWorkoutStep],
    edited: [TrainerWorkoutStep],
    feel: String = "Good",
    legs: String = "Normal",
    motivation: String = "Medium",
    flags: [String] = [],
    history: [WorkoutHistoryEntry] = [],
    profile: UserProfile = .empty
) -> WorkoutEditEvaluator {
    let checkIn = CheckIn(
        overallFeel: feel,
        legs: legs,
        motivation: motivation,
        timeAvailable: 45,
        contextFlags: flags,
        notes: nil
    )
    return WorkoutEditEvaluator(
        workoutType: type,
        originalSteps: original,
        editedSteps: edited,
        checkIn: checkIn,
        recentHistory: history,
        profile: profile
    )
}

private func makeHistory(
    _ entries: [(WorkoutType, WorkoutFeedback?)]
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

// MARK: - Load Computation

struct LoadComputationTests {

    @Test func loadIsProductOfPowerAndDuration() {
        let steps = makeSteps([("Test", 300, 200, .primary)])
        #expect(WorkoutEditEvaluator.computeLoad(steps) == 60_000)
    }

    @Test func loadSumsAllSteps() {
        let steps = makeSteps([
            ("A", 300, 100, .warmup),
            ("B", 600, 200, .primary)
        ])
        #expect(WorkoutEditEvaluator.computeLoad(steps) == 300 * 100 + 600 * 200)
    }

    @Test func emptyStepsHaveZeroLoad() {
        #expect(WorkoutEditEvaluator.computeLoad([]) == 0)
    }
}

// MARK: - Neutral (Minor Changes)

struct NeutralEvaluationTests {

    @Test func noChangeIsNeutral() {
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal
        ).evaluate()
        #expect(eval.level == .neutral)
        #expect(eval.preservesIntent == true)
    }

    @Test func tinyPowerBumpIsNeutral() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.05)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited
        ).evaluate()
        #expect(eval.level == .neutral)
    }

    @Test func tinyDecreaseIsNeutral() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 0.97)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited
        ).evaluate()
        #expect(eval.level == .neutral)
    }
}

// MARK: - Decreases

struct DecreaseEvaluationTests {

    @Test func moderateDecreaseWhenStressedIsEncouragement() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 0.7)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Bad",
            legs: "Dead"
        ).evaluate()
        #expect(eval.level == .encouragement)
    }

    @Test func hugeDecreaseWithoutStressIsNotice() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 0.4)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Good"
        ).evaluate()
        #expect(eval.level == .notice)
    }

    @Test func moderateDecreaseWithoutStressIsNeutral() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 0.85)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Good"
        ).evaluate()
        #expect(eval.level == .neutral)
    }
}

// MARK: - Recovery Increases

struct RecoveryIncreaseTests {

    @Test func moderateRecoveryIncreaseIsCaution() {
        let edited = scaleSteps(recoveryOriginal, powerFactor: 1.25)
        let eval = evaluator(
            type: .recovery,
            original: recoveryOriginal,
            edited: edited
        ).evaluate()
        #expect(eval.level == .caution)
        #expect(eval.preservesIntent == false)
    }

    @Test func largeRecoveryIncreaseIsStrongDiscourage() {
        let edited = scaleSteps(recoveryOriginal, powerFactor: 1.6)
        let eval = evaluator(
            type: .recovery,
            original: recoveryOriginal,
            edited: edited
        ).evaluate()
        #expect(eval.level == .strongDiscourage)
        #expect(eval.preservesIntent == false)
    }

    @Test func smallRecoveryIncreasePreservesIntent() {
        let edited = scaleSteps(recoveryOriginal, powerFactor: 1.08)
        let eval = evaluator(
            type: .recovery,
            original: recoveryOriginal,
            edited: edited
        ).evaluate()
        #expect(eval.level == .neutral)
        #expect(eval.preservesIntent == true)
    }
}

// MARK: - Stressed Increases

struct StressedIncreaseTests {

    @Test func largeIncreaseWhenBadFeelIsStrongDiscourage() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.4)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Bad",
            legs: "Heavy"
        ).evaluate()
        #expect(eval.level == .strongDiscourage)
    }

    @Test func moderateIncreaseWhenStressedIsCaution() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.2)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Bad"
        ).evaluate()
        #expect(eval.level == .caution)
    }

    @Test func largeIncreaseAfterTooMuchFeedbackIsStrongDiscourage() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.4)
        let history = makeHistory([(.quality, .tooMuch)])
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Good",
            history: history
        ).evaluate()
        #expect(eval.level == .strongDiscourage)
    }

    @Test func moderateIncreaseAfterHardFeedbackWhenOkayIsCaution() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.2)
        let history = makeHistory([(.endurance, .hard)])
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Okay",
            legs: "Heavy",
            history: history
        ).evaluate()
        #expect(eval.level == .caution)
    }

    @Test func sickFlagRaisesStress() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.2)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Okay",
            flags: ["Getting sick"]
        )
        #expect(eval.checkInStressLevel() >= 2)
    }
}

// MARK: - Moderate/Large Increases (No Stress)

struct UnstressedIncreaseTests {

    @Test func moderateIncreaseIsNotice() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.2)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Great",
            legs: "Fresh"
        ).evaluate()
        #expect(eval.level == .notice)
    }

    @Test func largeIncreaseIsCaution() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.4)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Great",
            legs: "Fresh"
        ).evaluate()
        #expect(eval.level == .caution)
    }

    @Test func hugeIncreaseIsStrongDiscourage() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.6)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Great",
            legs: "Fresh"
        ).evaluate()
        #expect(eval.level == .strongDiscourage)
    }
}

// MARK: - Okay Feel with Large Increase

struct OkayFeelTests {

    @Test func largeIncreaseOnOkayDayIsCaution() {
        let edited = scaleSteps(enduranceOriginal, powerFactor: 1.4)
        let eval = evaluator(
            original: enduranceOriginal,
            edited: edited,
            feel: "Okay",
            legs: "Normal",
            motivation: "Medium"
        ).evaluate()
        #expect(eval.level == .caution)
    }
}

// MARK: - Quality Workout Edits

struct QualityEditTests {

    @Test func smallQualityEditPreservesIntent() {
        let edited = scaleSteps(qualityOriginal, powerFactor: 1.05)
        let eval = evaluator(
            type: .quality,
            original: qualityOriginal,
            edited: edited,
            feel: "Great",
            legs: "Fresh"
        ).evaluate()
        #expect(eval.preservesIntent == true)
    }

    @Test func largeQualityEditDoesNotPreserveIntent() {
        let edited = scaleSteps(qualityOriginal, powerFactor: 1.5)
        let eval = evaluator(
            type: .quality,
            original: qualityOriginal,
            edited: edited,
            feel: "Great",
            legs: "Fresh"
        ).evaluate()
        #expect(eval.preservesIntent == false)
    }
}

// MARK: - Stress Level Computation

struct StressLevelTests {

    @Test func goodFeelFreshLegsIsZero() {
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            feel: "Good",
            legs: "Fresh",
            motivation: "High"
        )
        #expect(eval.checkInStressLevel() == 0)
    }

    @Test func badFeelDeadLegsIsCapped() {
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            feel: "Bad",
            legs: "Dead",
            motivation: "Low"
        )
        #expect(eval.checkInStressLevel() == 3)
    }

    @Test func okayFeelHeavyLegsIsModerate() {
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            feel: "Okay",
            legs: "Heavy"
        )
        #expect(eval.checkInStressLevel() == 2)
    }

    @Test func noCheckInIsZeroStress() {
        let eval = WorkoutEditEvaluator(
            workoutType: .endurance,
            originalSteps: enduranceOriginal,
            editedSteps: enduranceOriginal,
            checkIn: nil,
            recentHistory: [],
            profile: .empty
        )
        #expect(eval.checkInStressLevel() == 0)
    }
}

// MARK: - Recent Stress Signal

struct RecentStressSignalTests {

    @Test func tooMuchFeedbackIsHighStress() {
        let history = makeHistory([(.quality, .tooMuch)])
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            history: history
        )
        #expect(eval.recentStressSignal() == 2)
    }

    @Test func hardFeedbackIsModerateStress() {
        let history = makeHistory([(.endurance, .hard)])
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            history: history
        )
        #expect(eval.recentStressSignal() == 1)
    }

    @Test func rightFeedbackIsNoStress() {
        let history = makeHistory([(.endurance, .right)])
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            history: history
        )
        #expect(eval.recentStressSignal() == 0)
    }

    @Test func emptyHistoryIsNoStress() {
        let eval = evaluator(
            original: enduranceOriginal,
            edited: enduranceOriginal,
            history: []
        )
        #expect(eval.recentStressSignal() == 0)
    }
}
