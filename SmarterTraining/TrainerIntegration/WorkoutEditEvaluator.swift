import Foundation

// MARK: - Evaluation Types

enum WorkoutEditGuidanceLevel: Comparable {
    case neutral
    case encouragement
    case notice
    case caution
    case strongDiscourage
}

struct WorkoutEditEvaluation {
    let level: WorkoutEditGuidanceLevel
    let title: String
    let message: String
    let preservesIntent: Bool
    let estimatedLoadChange: Double
}

// MARK: - Evaluator

struct WorkoutEditEvaluator {

    let workoutType: WorkoutType
    let originalSteps: [TrainerWorkoutStep]
    let editedSteps: [TrainerWorkoutStep]
    let checkIn: CheckIn?
    let recentHistory: [WorkoutHistoryEntry]
    let profile: UserProfile

    func evaluate() -> WorkoutEditEvaluation {
        let originalLoad = Self.computeLoad(originalSteps)
        let editedLoad = Self.computeLoad(editedSteps)
        let loadRatio = originalLoad > 0 ? editedLoad / originalLoad : 1.0
        let loadChange = loadRatio - 1.0

        let isIncrease = loadChange > 0.05
        let isDecrease = loadChange < -0.05
        let isMinor = abs(loadChange) < 0.10
        let isModerate = abs(loadChange) >= 0.10 && abs(loadChange) < 0.30
        let isLarge = abs(loadChange) >= 0.30 && abs(loadChange) < 0.50
        let isHuge = abs(loadChange) >= 0.50
        let preserves = intentPreserved(loadRatio: loadRatio)
        let stress = checkInStressLevel()
        let recentStress = recentStressSignal()

        if isDecrease {
            return evaluateDecrease(
                stress: stress, isHuge: isHuge,
                preserves: preserves, loadRatio: loadRatio
            )
        }

        if isMinor {
            return neutral(preserves: preserves, loadRatio: loadRatio)
        }

        if workoutType == .recovery && isIncrease {
            return evaluateRecoveryIncrease(
                isModerate: isModerate, preserves: preserves, loadRatio: loadRatio
            )
        }

        if isIncrease && (stress >= 2 || recentStress >= 2) {
            return evaluateStressedIncrease(
                isLarge: isLarge, isHuge: isHuge,
                preserves: preserves, loadRatio: loadRatio
            )
        }

        if isIncrease && stress == 1 && (isLarge || isHuge) {
            return WorkoutEditEvaluation(
                level: .caution,
                title: "That's a big jump",
                message: "You're adding a lot on a day you said was just okay. Make sure you're up for it.",
                preservesIntent: preserves,
                estimatedLoadChange: loadRatio
            )
        }

        if isModerate && isIncrease {
            return WorkoutEditEvaluation(
                level: .notice,
                title: "A bit more than planned",
                message: "You're pushing this up a notch. If you're feeling good, go for it.",
                preservesIntent: preserves,
                estimatedLoadChange: loadRatio
            )
        }

        if isLarge && isIncrease {
            return WorkoutEditEvaluation(
                level: .caution,
                title: "Noticeably harder",
                message: "This is a significant bump from the recommendation. Make sure it matches what your legs can deliver today.",
                preservesIntent: preserves,
                estimatedLoadChange: loadRatio
            )
        }

        if isHuge {
            return WorkoutEditEvaluation(
                level: .strongDiscourage,
                title: "Way beyond the plan",
                message: "This is a very different workout than what was recommended. The plan had a reason \u{2014} consider dialing it back.",
                preservesIntent: false,
                estimatedLoadChange: loadRatio
            )
        }

        return neutral(preserves: preserves, loadRatio: loadRatio)
    }

    // MARK: - Load Computation

    static func computeLoad(_ steps: [TrainerWorkoutStep]) -> Double {
        steps.reduce(0) { $0 + Double($1.targetPower) * $1.duration }
    }

    // MARK: - Private Evaluation Paths

    private func evaluateDecrease(
        stress: Int, isHuge: Bool,
        preserves: Bool, loadRatio: Double
    ) -> WorkoutEditEvaluation {
        if stress >= 2 {
            return WorkoutEditEvaluation(
                level: .encouragement,
                title: "Good call",
                message: "Dialing it back a bit fits how you're feeling today.",
                preservesIntent: preserves,
                estimatedLoadChange: loadRatio
            )
        }
        if isHuge {
            return WorkoutEditEvaluation(
                level: .notice,
                title: "Scaled way down",
                message: "You've cut this workout significantly. That's fine if today calls for it.",
                preservesIntent: preserves,
                estimatedLoadChange: loadRatio
            )
        }
        return neutral(preserves: preserves, loadRatio: loadRatio)
    }

    private func evaluateRecoveryIncrease(
        isModerate: Bool, preserves: Bool, loadRatio: Double
    ) -> WorkoutEditEvaluation {
        if isModerate {
            return WorkoutEditEvaluation(
                level: .caution,
                title: "Recovery works best when it's easy",
                message: "The recommendation was gentle for a reason. Pushing harder here may cost you tomorrow.",
                preservesIntent: false,
                estimatedLoadChange: loadRatio
            )
        }
        return WorkoutEditEvaluation(
            level: .strongDiscourage,
            title: "This isn't really recovery anymore",
            message: "At this intensity, you're doing a workout that won't let your body recover. Consider sticking closer to the original.",
            preservesIntent: false,
            estimatedLoadChange: loadRatio
        )
    }

    private func evaluateStressedIncrease(
        isLarge: Bool, isHuge: Bool,
        preserves: Bool, loadRatio: Double
    ) -> WorkoutEditEvaluation {
        if isLarge || isHuge {
            return WorkoutEditEvaluation(
                level: .strongDiscourage,
                title: "Your body is asking for less, not more",
                message: "Between how you're feeling and recent sessions, a big jump in load isn't the move today.",
                preservesIntent: false,
                estimatedLoadChange: loadRatio
            )
        }
        return WorkoutEditEvaluation(
            level: .caution,
            title: "Worth a second thought",
            message: "You checked in feeling rough. Adding load on top of that can dig a deeper hole.",
            preservesIntent: preserves,
            estimatedLoadChange: loadRatio
        )
    }

    // MARK: - Context Analysis

    func checkInStressLevel() -> Int {
        guard let checkIn else { return 0 }
        var stress = 0

        let feel = checkIn.overallFeel.lowercased()
        if feel == "bad" || feel == "terrible" { stress += 2 }
        else if feel == "okay" { stress += 1 }

        let legs = checkIn.legs.lowercased()
        if legs == "dead" { stress += 2 }
        else if legs == "heavy" { stress += 1 }

        let motivation = checkIn.motivation.lowercased()
        if motivation == "low" || motivation == "none" { stress += 1 }

        let flagsLower = checkIn.contextFlags.map { $0.lowercased() }
        if flagsLower.contains(where: { $0.contains("sick") || $0.contains("sleep") }) {
            stress += 1
        }

        let hardRecent = checkIn.recentActivities.filter {
            ($0.intensity == "Hard" || $0.intensity == "Very hard") &&
            ($0.timing == "Today" || $0.timing == "Yesterday")
        }
        if !hardRecent.isEmpty { stress += 1 }

        return min(3, stress)
    }

    func recentStressSignal() -> Int {
        guard let last = recentHistory.last else { return 0 }
        if last.feedback == .tooMuch { return 2 }
        if last.feedback == .hard { return 1 }
        return 0
    }

    private func intentPreserved(loadRatio: Double) -> Bool {
        switch workoutType {
        case .recovery:
            return loadRatio <= 1.15
        case .endurance:
            return loadRatio >= 0.7 && loadRatio <= 1.35
        case .quality:
            return loadRatio >= 0.7 && loadRatio <= 1.35
        }
    }

    private func neutral(preserves: Bool, loadRatio: Double) -> WorkoutEditEvaluation {
        WorkoutEditEvaluation(
            level: .neutral,
            title: "",
            message: "",
            preservesIntent: preserves,
            estimatedLoadChange: loadRatio
        )
    }
}
