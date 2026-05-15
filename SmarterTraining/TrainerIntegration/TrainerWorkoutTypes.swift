import Foundation

struct TrainerWorkoutStep: Codable, Identifiable {
    let id: UUID
    var name: String
    var duration: TimeInterval
    var targetPower: Int
    var role: WorkoutStepRole

    init(id: UUID = UUID(), name: String, duration: TimeInterval, targetPower: Int, role: WorkoutStepRole) {
        self.id = id
        self.name = name
        self.duration = duration
        self.targetPower = targetPower
        self.role = role
    }
}

enum WorkoutConverter {

    static func convert(recommendation: WorkoutRecommendation, ftp: Int?) -> [TrainerWorkoutStep] {
        recommendation.steps.flatMap { step in
            convertStep(step, workoutType: recommendation.type, ftp: ftp)
        }
    }

    private static func convertStep(_ step: WorkoutStep, workoutType: WorkoutType, ftp: Int?) -> [TrainerWorkoutStep] {
        let intervalParse = parseIntervalDuration(step.durationText)

        if let interval = intervalParse {
            return expandIntervals(
                step: step,
                reps: interval.reps,
                workSeconds: interval.workSeconds,
                workoutType: workoutType,
                ftp: ftp
            )
        }

        let seconds = parseSimpleDuration(step.durationText)
        let watts = resolveTargetPower(step.targetText, role: step.role, workoutType: workoutType, ftp: ftp)

        return [TrainerWorkoutStep(name: step.name, duration: seconds, targetPower: watts, role: step.role)]
    }

    private static func expandIntervals(
        step: WorkoutStep,
        reps: Int,
        workSeconds: TimeInterval,
        workoutType: WorkoutType,
        ftp: Int?
    ) -> [TrainerWorkoutStep] {
        let workWatts = resolveTargetPower(step.targetText, role: .primary, workoutType: workoutType, ftp: ftp)
        let restSeconds = parseRestDuration(step.targetText)
        let restWatts = ftp.map { Int(Double($0) * 0.55) } ?? 100

        var steps: [TrainerWorkoutStep] = []
        for i in 1...reps {
            steps.append(TrainerWorkoutStep(
                name: "Interval \(i) of \(reps)",
                duration: workSeconds,
                targetPower: workWatts,
                role: .primary
            ))
            if i < reps {
                steps.append(TrainerWorkoutStep(
                    name: "Recovery",
                    duration: restSeconds,
                    targetPower: restWatts,
                    role: .cooldown
                ))
            }
        }
        return steps
    }

    // MARK: - Duration parsing

    // "3 x 4 min" -> (reps: 3, workSeconds: 240)
    private static func parseIntervalDuration(_ text: String) -> (reps: Int, workSeconds: TimeInterval)? {
        let pattern = #"(\d+)\s*x\s*(\d+)\s*min"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(text[match])
        let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
        guard numbers.count >= 2,
              let reps = Int(numbers[0]),
              let mins = Int(numbers[1]) else { return nil }
        return (reps, TimeInterval(mins * 60))
    }

    // "5 min" -> 300, "15–20 min" -> 1050 (midpoint)
    private static func parseSimpleDuration(_ text: String) -> TimeInterval {
        let rangePattern = #"(\d+)\s*[–\-]\s*(\d+)\s*min"#
        if let match = text.range(of: rangePattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if numbers.count >= 2, let lo = Int(numbers[0]), let hi = Int(numbers[1]) {
                return TimeInterval((lo + hi) / 2 * 60)
            }
        }

        let simplePattern = #"(\d+)\s*min"#
        if let match = text.range(of: simplePattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if let mins = numbers.first.flatMap(Int.init) {
                return TimeInterval(mins * 60)
            }
        }

        return 300 // fallback: 5 min
    }

    // "... with 2 min easy between reps" -> 120
    private static func parseRestDuration(_ text: String) -> TimeInterval {
        let pattern = #"with\s+(\d+)\s*min"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if let mins = numbers.first.flatMap(Int.init) {
                return TimeInterval(mins * 60)
            }
        }
        return 120 // fallback: 2 min
    }

    // MARK: - Power resolution

    static func resolveTargetPower(_ targetText: String, role: WorkoutStepRole, workoutType: WorkoutType, ftp: Int?) -> Int {
        if let ftp {
            if let pct = parseFTPPercentage(targetText) {
                return Int(Double(ftp) * pct)
            }
            return defaultFTPFraction(role: role, workoutType: workoutType, ftp: ftp)
        }
        return defaultAbsoluteWatts(role: role, workoutType: workoutType)
    }

    // "60% FTP" -> 0.60, "70–80% FTP" -> 0.75, "<55% FTP" -> 0.50, "95–100% FTP ..." -> 0.975
    private static func parseFTPPercentage(_ text: String) -> Double? {
        guard text.contains("FTP") || text.contains("ftp") else { return nil }

        let rangePattern = #"(\d+)\s*[–\-]\s*(\d+)\s*%"#
        if let match = text.range(of: rangePattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if numbers.count >= 2, let lo = Int(numbers[0]), let hi = Int(numbers[1]) {
                return Double(lo + hi) / 200.0
            }
        }

        let lessPattern = #"<\s*(\d+)\s*%"#
        if let match = text.range(of: lessPattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if let pct = numbers.first.flatMap(Int.init) {
                return Double(pct - 5) / 100.0
            }
        }

        let singlePattern = #"(\d+)\s*%"#
        if let match = text.range(of: singlePattern, options: .regularExpression) {
            let matched = String(text[match])
            let numbers = matched.components(separatedBy: .decimalDigits.inverted).filter { !$0.isEmpty }
            if let pct = numbers.first.flatMap(Int.init) {
                return Double(pct) / 100.0
            }
        }

        return nil
    }

    private static func defaultFTPFraction(role: WorkoutStepRole, workoutType: WorkoutType, ftp: Int) -> Int {
        let fraction: Double = switch (workoutType, role) {
        case (.recovery, _):           0.50
        case (.endurance, .warmup):    0.60
        case (.endurance, .primary):   0.75
        case (.endurance, .cooldown):  0.50
        case (.quality, .warmup):      0.65
        case (.quality, .primary):     0.95
        case (.quality, .cooldown):    0.50
        case (_, .accessory):          0.55
        default:                       0.65
        }
        return Int(Double(ftp) * fraction)
    }

    private static func defaultAbsoluteWatts(role: WorkoutStepRole, workoutType: WorkoutType) -> Int {
        switch (workoutType, role) {
        case (.recovery, _):           80
        case (.endurance, .warmup):    100
        case (.endurance, .primary):   130
        case (.endurance, .cooldown):  90
        case (.quality, .warmup):      110
        case (.quality, .primary):     180
        case (.quality, .cooldown):    90
        case (_, .accessory):          90
        default:                       110
        }
    }
}
