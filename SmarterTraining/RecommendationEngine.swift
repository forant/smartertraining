import Foundation

/// Pure, deterministic recommendation engine. Takes all inputs explicitly,
/// making it easy to test and later replace with AI-backed logic.
struct RecommendationEngine {

    struct Inputs {
        var profile: UserProfile
        var checkIn: CheckIn
        var recentHistory: [WorkoutHistoryEntry]
        var memorySummary: TrainingMemorySummary = .empty
        var activeIntent: ShortTermTrainingIntent? = nil
    }

    func recommend(for inputs: Inputs) -> WorkoutRecommendation {
        let type = chooseWorkoutType(for: inputs)
        let reason = buildReason(type: type, inputs: inputs)
        var workout = buildWorkout(type: type, time: inputs.checkIn.timeAvailable, reason: reason)
        workout.optionalExtras = adjustExtras(workout.optionalExtras, type: type, time: inputs.checkIn.timeAvailable, profile: inputs.profile)
        return workout
    }

    // MARK: - Profile Bias

    func qualityWillingness(for profile: UserProfile) -> Int {
        var score = 0

        switch profile.currentState {
        case .justStarting: score -= 2
        case .gettingBack: score -= 1
        case .consistent, .none: break
        case .veryConsistent: score += 1
        }

        switch profile.trainingFrequency {
        case .light: score -= 1
        case .moderate, .flexible, .none: break
        case .heavy: score += 1
        }

        let goals = Set(profile.goals)
        if goals.contains(.endurance) || goals.contains(.bikePerformance) {
            score += 1
        }
        if goals.contains(.consistent) || goals.contains(.healthier) {
            score -= 1
        }

        return max(-2, min(2, score))
    }

    func favorsConsistency(_ profile: UserProfile) -> Bool {
        profile.goals.contains(.consistent) || profile.goals.contains(.healthier)
    }

    func hasStrengthEquipment(_ profile: UserProfile) -> Bool {
        let eq = Set(profile.equipment)
        return !eq.isEmpty
            && !eq.isSubset(of: [.noEquipment, .bikeTrainer, .outdoorBike])
    }

    // MARK: - Activity Stress

    func activityStress(from checkIn: CheckIn) -> Int {
        guard !checkIn.recentActivities.isEmpty else { return 0 }

        let hardRecent = checkIn.recentActivities.filter { a in
            let isHard = a.intensity == "Hard" || a.intensity == "Very hard"
            let isRecent = a.timing == "Today" || a.timing == "Yesterday"
            return isHard && isRecent
        }

        if hardRecent.contains(where: { $0.intensity == "Very hard" }) { return 2 }
        if !hardRecent.isEmpty { return 1 }

        let moderateToday = checkIn.recentActivities.filter {
            $0.intensity == "Moderate" && $0.timing == "Today"
        }
        if !moderateToday.isEmpty { return 1 }

        return 0
    }

    // MARK: - Type Selection

    func chooseWorkoutType(for inputs: Inputs) -> WorkoutType {
        let checkIn = inputs.checkIn
        let lastFeedback = inputs.recentHistory.last?.feedback
        let lastType = inputs.recentHistory.last?.type
        let willingness = qualityWillingness(for: inputs.profile)
        let memory = inputs.memorySummary
        let todayActStress = activityStress(from: checkIn)
        let actStress = max(todayActStress, memoryActivityStress(memory))

        // Step A: Hard recovery overrides
        if checkIn.overallFeel == "Bad" || checkIn.contextFlags.contains("Getting sick") {
            return .recovery
        }
        if checkIn.legs == "Dead" {
            return .recovery
        }
        if checkIn.overallFeel == "Okay" && checkIn.motivation == "Low" && checkIn.legs == "Heavy" {
            return .recovery
        }
        if checkIn.contextFlags.contains("Poor sleep") && checkIn.legs == "Heavy" {
            return .recovery
        }

        // Step A1.5: Coaching intent from prior workout
        if let intent = inputs.activeIntent, !intent.isExpired, let intentIntensity = intent.recommendedIntensity() {
            let intentResult = applyIntent(intentIntensity, intent: intent, checkIn: checkIn, actStress: actStress)
            if let result = intentResult { return result }
        }

        // Step A2: Activity-based overrides
        if actStress >= 2 && checkIn.overallFeel != "Great" {
            return checkIn.legs == "Heavy" ? .recovery : .endurance
        }

        // Step A3: Training memory — returning after extended break
        if memory.isReturningAfterBreak {
            if checkIn.overallFeel != "Great" || checkIn.legs != "Fresh" {
                return .recovery
            }
            return .endurance
        }

        // Step B: Prior feedback — tooMuch is a strong signal
        if lastFeedback == .tooMuch {
            if checkIn.overallFeel == "Okay" || checkIn.legs == "Heavy" || checkIn.motivation == "Low" {
                return .recovery
            }
            return .endurance
        }

        // Step B2: Training memory — tooMuch in recent window
        if memory.hadTooMuchFeedback7d && lastFeedback != .tooMuch {
            if checkIn.legs == "Heavy" || checkIn.overallFeel == "Okay" {
                return .endurance
            }
        }

        // Step C: History guardrails — no back-to-back quality
        if lastType == .quality {
            if checkIn.legs == "Heavy" || checkIn.overallFeel == "Okay" {
                return checkIn.motivation == "Low" ? .recovery : .endurance
            }
            return .endurance
        }

        // Step D: Prior feedback — hard mildly discourages quality; hard activity does too
        let hardBias = lastFeedback == .hard || actStress >= 2 || memory.hadTooMuchFeedback7d

        // Step E: After easier stretch, allow quality if signals support it
        let recentTypes = inputs.recentHistory.suffix(3).map(\.type)
        let easierCount = recentTypes.filter({ $0 == .endurance || $0 == .recovery }).count
        let legsReady = checkIn.legs == "Fresh" || checkIn.legs == "Normal"
        let signalsStrong = checkIn.overallFeel == "Great"
            && checkIn.motivation == "High"
            && legsReady
        let easyBoost = lastFeedback == .easy

        let qualityHistoryThreshold = willingness >= 1 ? 1 : 2

        let weekLoadHigh = memory.hasHighRecentLoad
            || (memory.hardDayCount7d >= 2 && memory.recentLifeStressLevel >= 2)

        if !weekLoadHigh && easierCount >= qualityHistoryThreshold && signalsStrong && !hardBias && willingness > -2 && actStress < 2 {
            return .quality
        }

        // Step F: Legs shape the default
        if checkIn.legs == "Heavy" {
            return .endurance
        }

        // Fresh legs + good signals can open quality
        if !weekLoadHigh && checkIn.legs == "Fresh"
            && checkIn.overallFeel == "Great"
            && checkIn.motivation == "High"
            && lastType != .quality
            && !hardBias
            && willingness >= -1
            && actStress == 0 {
            return .quality
        }

        // Easy boost
        if !weekLoadHigh && easyBoost
            && signalsStrong
            && easierCount >= 1
            && lastType != .quality
            && willingness >= 0
            && actStress == 0 {
            return .quality
        }

        // Default
        return .endurance
    }

    // MARK: - Intent Application

    private func applyIntent(
        _ intensity: ShortTermTrainingIntent.RecommendedIntensity,
        intent: ShortTermTrainingIntent,
        checkIn: CheckIn,
        actStress: Int
    ) -> WorkoutType? {
        switch intensity {
        case .rest, .recovery:
            return .recovery
        case .endurance:
            if checkIn.legs == "Dead" || checkIn.overallFeel == "Bad" {
                return .recovery
            }
            return .endurance
        case .quality:
            if checkIn.legs == "Heavy" || checkIn.legs == "Dead"
                || checkIn.overallFeel == "Bad" || checkIn.overallFeel == "Okay"
                || checkIn.contextFlags.contains("Getting sick")
                || checkIn.contextFlags.contains("Poor sleep")
                || actStress >= 2 {
                return .endurance
            }
            return nil
        case .flexible:
            return nil
        }
    }

    // MARK: - Reason Builder

    func buildReason(type: WorkoutType, inputs: Inputs) -> String {
        if let intent = inputs.activeIntent, !intent.isExpired, let rationale = intent.rationale() {
            let intentIntensity = intent.recommendedIntensity()
            if intentIntensity == .rest || intentIntensity == .recovery {
                return rationale
            }
            if intentIntensity == .endurance && type == .endurance {
                return rationale
            }
            if intentIntensity == .quality && type == .quality {
                return rationale
            }
        }

        let checkIn = inputs.checkIn
        let lastType = inputs.recentHistory.last?.type
        let lastFeedback = inputs.recentHistory.last?.feedback
        let recentTypes = inputs.recentHistory.suffix(3).map(\.type)
        let easierCount = recentTypes.filter({ $0 == .endurance || $0 == .recovery }).count
        let historyCount = inputs.recentHistory.count
        let actStress = activityStress(from: checkIn)
        let memory = inputs.memorySummary

        switch type {
        case .recovery:
            return buildRecoveryReason(checkIn: checkIn, lastFeedback: lastFeedback, historyCount: historyCount, actStress: actStress, memory: memory)
        case .endurance:
            return buildEnduranceReason(checkIn: checkIn, lastType: lastType, lastFeedback: lastFeedback, easierCount: easierCount, profile: inputs.profile, actStress: actStress, memory: memory)
        case .quality:
            return buildQualityReason(checkIn: checkIn, lastFeedback: lastFeedback, easierCount: easierCount, profile: inputs.profile, memory: memory)
        }
    }

    private func buildRecoveryReason(checkIn: CheckIn, lastFeedback: WorkoutFeedback?, historyCount: Int, actStress: Int, memory: TrainingMemorySummary) -> String {
        if actStress >= 2 && checkIn.legs == "Heavy" {
            let activityName = hardRecentActivityName(from: checkIn) ?? "recent activity"
            return "Your \(activityName) was hard and your legs are still feeling it. Easy recovery today lets your body catch up."
        }

        if checkIn.contextFlags.contains("Poor sleep") && checkIn.legs == "Heavy" {
            return "Poor sleep and heavy legs are both saying the same thing. Recovery keeps you moving without digging a hole."
        }

        if checkIn.contextFlags.contains("Getting sick") {
            if checkIn.legs == "Dead" || checkIn.overallFeel == "Bad" {
                return "It looks like you might be getting sick and your body is already showing it. Taking it easy today is the right call."
            }
            return "You flagged that you might be getting sick, so the focus today is rest. Protect the bigger picture."
        }

        if checkIn.legs == "Dead" && checkIn.overallFeel == "Bad" {
            return "Dead legs and low energy are clear signals. A recovery day lets your body catch up."
        }
        if checkIn.legs == "Dead" {
            if lastFeedback == .hard || lastFeedback == .tooMuch {
                return "Dead legs after a tough session — your body is asking for recovery, so we'll keep things easy."
            }
            return "Dead legs are a clear signal your body needs a break. Easy recovery today."
        }

        if checkIn.overallFeel == "Bad" {
            if checkIn.motivation == "Low" {
                return "You're not feeling great and motivation is low. Recovery keeps you moving without digging a hole."
            }
            return "Given how you're feeling today, backing off is the smart move. Light recovery only."
        }

        if lastFeedback == .tooMuch {
            if checkIn.legs == "Heavy" {
                return "Yesterday was too much and your legs are still feeling it. A recovery day helps you reset."
            }
            return "The last session was too much, so today is better used for easy recovery work."
        }

        if checkIn.motivation == "Low" && checkIn.legs == "Heavy" {
            if memory.completedWorkoutCount7d >= 3 {
                return "You've been consistent this week, and heavy legs with low motivation is a clear signal. Smart recovery keeps the streak going."
            }
            return "Heavy legs and low motivation both point the same way. Easy recovery keeps you on track."
        }

        if memory.isReturningAfterBreak {
            return "After a few days off, this rebuilds momentum without overreaching."
        }

        if historyCount == 0 {
            return "Today's signals suggest starting easy. A light recovery session is the right first step."
        }

        if memory.completedWorkoutCount7d >= 3 {
            return "You've been showing up consistently. A recovery day is part of training smart, not a step back."
        }

        return "Today's signals point toward recovery. Easy does it."
    }

    private func buildEnduranceReason(checkIn: CheckIn, lastType: WorkoutType?, lastFeedback: WorkoutFeedback?, easierCount: Int, profile: UserProfile, actStress: Int, memory: TrainingMemorySummary) -> String {
        if actStress >= 2 {
            let activityName = hardRecentActivityName(from: checkIn) ?? "recent activity"
            return "Your \(activityName) added real load. Steady aerobic work today lets you absorb that without piling on."
        }
        if actStress >= 1 && checkIn.legs == "Heavy" {
            let activityName = hardRecentActivityName(from: checkIn) ?? "recent activity"
            return "Between your \(activityName) and heavy legs, a controlled endurance ride is the right call."
        }

        if memory.hasHighRecentLoad {
            return "You've already had \(memory.hardDayCount7d) harder days this week. Steady aerobic work keeps things balanced."
        }

        if memoryActivityStress(memory) >= 1, let name = memoryHardActivityName(memory) {
            return "Your recent \(name) counts as meaningful stress. Steady aerobic work today keeps things balanced."
        }

        if memory.isReturningAfterBreak {
            return "After a few days off, this gets you moving again without jumping back in too hard."
        }

        if lastFeedback == .tooMuch {
            if checkIn.overallFeel == "Good" || checkIn.overallFeel == "Great" {
                return "Yesterday felt like too much, but you're bouncing back well. Steady aerobic work lets you build without overdoing it."
            }
            return "Yesterday felt like too much, so today is better used for controlled aerobic work."
        }

        if lastFeedback == .hard && checkIn.legs == "Heavy" {
            return "Your last session hit hard and your legs are still heavy, so the focus today is steady endurance work."
        }
        if lastFeedback == .hard {
            if checkIn.motivation == "High" {
                return "The last session was tough. You're motivated, which is great — steady aerobic work today helps you absorb that effort."
            }
            return "Given that the last session was tough, a steady aerobic day helps you absorb that work."
        }

        if lastType == .quality {
            if checkIn.legs == "Heavy" {
                return "Yesterday was a quality session and your legs are feeling it. An easier aerobic ride helps you recover."
            }
            if checkIn.overallFeel == "Good" || checkIn.overallFeel == "Great" {
                return "Yesterday was quality work. You're feeling decent, but steady endurance today helps you absorb that effort."
            }
            return "Yesterday was a quality session, so an easier aerobic ride today helps you absorb that work."
        }

        if checkIn.legs == "Heavy" {
            if checkIn.motivation == "High" {
                return "You're motivated today, but your legs are heavy. Steady endurance keeps you moving without pushing too hard."
            }
            return "Heavy legs suggest keeping today aerobic. Steady endurance work without pushing it."
        }

        if favorsConsistency(profile) {
            if easierCount >= 2 {
                return "Your recent work has been lighter, which is fine. A steady endurance ride keeps you building consistency."
            }
            return "A steady endurance ride keeps you on track with your consistency goal."
        }

        if checkIn.motivation == "High" && checkIn.overallFeel == "Good" {
            return "You're in a good spot today. Steady aerobic work makes the most of where you are."
        }

        if memory.completedWorkoutCount7d >= 4 {
            return "You've been consistent lately, so today can stay aerobic."
        }

        return "Today's inputs line up well for steady endurance work. Controlled effort, nothing forced."
    }

    private func buildQualityReason(checkIn: CheckIn, lastFeedback: WorkoutFeedback?, easierCount: Int, profile: UserProfile, memory: TrainingMemorySummary) -> String {
        let highWillingness = qualityWillingness(for: profile) >= 1

        if lastFeedback == .easy && easierCount >= 1 {
            if checkIn.legs == "Fresh" {
                return "Recent sessions have been landing easy and your legs are fresh, which makes today a good fit for quality work."
            }
            return "Your recent work has been landing well and today's signals are strong. Time for some structured intensity."
        }

        if easierCount >= 2 {
            if checkIn.motivation == "High" {
                return "You've had a lighter stretch and you're motivated today. Your body and mind are ready for quality work."
            }
            return "Given your recent easier stretch, today's signals support adding some structured quality work."
        }

        if highWillingness && checkIn.legs == "Fresh" {
            if checkIn.motivation == "High" {
                return "Your training background supports it, your legs are fresh, and motivation is high. Today can handle quality."
            }
            return "Your training consistency can handle it, and fresh legs make today right for quality work."
        }

        if checkIn.legs == "Fresh" && checkIn.motivation == "High" {
            return "Fresh legs and strong motivation — the signals line up for focused quality work today."
        }

        if checkIn.legs == "Fresh" {
            return "Fresh legs are a good foundation. Today is a chance for some focused intensity."
        }

        if memory.completedWorkoutCount7d >= 2 && memory.recentIntensityLoadEstimate <= 4 {
            return "Your recent load has been manageable and today's signals are strong. Good conditions for quality work."
        }

        return "Your signals are strong today, so the focus is quality. Controlled intensity with purpose."
    }

    // MARK: - Workout Builder

    func buildWorkout(type: WorkoutType, time: Int, reason: String) -> WorkoutRecommendation {
        switch type {
        case .recovery: return buildRecovery(time: time, reason: reason)
        case .endurance: return buildEndurance(time: time, reason: reason)
        case .quality: return buildQuality(time: time, reason: reason)
        }
    }

    private func buildRecovery(time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 20 {
            return WorkoutRecommendation(
                type: .recovery,
                title: "Easy Spin",
                summary: "Very light movement or full rest",
                reason: reason,
                steps: [
                    WorkoutStep(role: .primary, modality: .recovery, name: "Easy spin", durationText: "15\u{2013}20 min", targetText: "<55% FTP, keep it effortless")
                ],
                optionalExtras: []
            )
        }
        return WorkoutRecommendation(
            type: .recovery,
            title: "Recovery Day",
            summary: "Easy spin and mobility",
            reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .recovery, name: "Warm-up", durationText: "5 min", targetText: "Easy spin"),
                WorkoutStep(role: .primary, modality: .recovery, name: "Main", durationText: "\(max(time - 10, 15)) min", targetText: "<60% FTP"),
                WorkoutStep(role: .cooldown, modality: .recovery, name: "Cool down", durationText: "5 min", targetText: "Fade down gradually")
            ],
            optionalExtras: []
        )
    }

    private func buildEndurance(time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 20 {
            return WorkoutRecommendation(
                type: .endurance,
                title: "Short Aerobic Spin",
                summary: "Quick Zone 2 hit",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "3 min", targetText: "Easy spin"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "15 min", targetText: "Zone 2 / 70\u{2013}80% FTP"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "2 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        if time <= 30 {
            return WorkoutRecommendation(
                type: .endurance,
                title: "30 min Zone 2 Ride",
                summary: "Compact aerobic session",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "5 min", targetText: "60% FTP"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "20 min", targetText: "Zone 2 / 70\u{2013}80% FTP"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "5 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        let mainDuration = time >= 60 ? "50 min" : "35 min"
        let title = time >= 60 ? "60 min Endurance Ride" : "45 min Zone 2 Ride"
        return WorkoutRecommendation(
            type: .endurance,
            title: title,
            summary: "Steady aerobic base work",
            reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "5 min", targetText: "60% FTP"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: mainDuration, targetText: "Zone 2 / 70\u{2013}80% FTP"),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "5 min", targetText: "60% \u{2192} 40% FTP")
            ],
            optionalExtras: []
        )
    }

    private func buildQuality(time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 30 {
            return WorkoutRecommendation(
                type: .quality,
                title: "Compact Threshold",
                summary: "Short and sharp quality session",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "5 min", targetText: "Build from easy to steady"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "3 x 4 min", targetText: "95\u{2013}100% FTP with 2 min easy between reps"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "5 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        if time >= 60 {
            return WorkoutRecommendation(
                type: .quality,
                title: "Threshold Intervals",
                summary: "Full quality session with warm-up and cool-down",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "15 min", targetText: "Build from easy to steady, include 2 x 1 min openers"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "4 x 6 min", targetText: "95\u{2013}100% FTP with 3 min easy between reps"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "10 min", targetText: "Easy spin, gradually fade")
                ],
                optionalExtras: []
            )
        }
        return WorkoutRecommendation(
            type: .quality,
            title: "Threshold Intervals",
            summary: "Controlled quality work",
            reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "10 min", targetText: "Build from easy to steady"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "4 x 5 min", targetText: "95\u{2013}100% FTP with 3 min easy between reps"),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "10 min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: - Equipment-Aware Extras

    func adjustExtras(_ base: [String], type: WorkoutType, time: Int, profile: UserProfile) -> [String] {
        var extras = base

        switch type {
        case .recovery:
            extras.append("Light mobility")
            extras.append("Short walk later in the day")

        case .endurance where time >= 45:
            if hasStrengthEquipment(profile) {
                let eq = Set(profile.equipment)
                if eq.contains(.dumbbells) || eq.contains(.kettlebells) {
                    extras.append("10\u{2013}15 min dumbbell or kettlebell core circuit")
                } else if eq.contains(.gym) {
                    extras.append("10\u{2013}15 min core and upper body work")
                } else if eq.contains(.bands) {
                    extras.append("10\u{2013}15 min band-assisted core work")
                }
            } else {
                extras.append("10\u{2013}15 min bodyweight core work")
            }

        case .quality:
            extras.append("5\u{2013}10 min mobility later")

        default:
            break
        }

        return extras
    }

    // MARK: - Helpers

    private func hardRecentActivityName(from checkIn: CheckIn) -> String? {
        checkIn.recentActivities
            .filter { ($0.intensity == "Hard" || $0.intensity == "Very hard") && ($0.timing == "Today" || $0.timing == "Yesterday") }
            .first
            .map { $0.type.lowercased() }
    }

    // MARK: - Training Memory Helpers

    func memoryActivityStress(_ memory: TrainingMemorySummary) -> Int {
        let hard = memory.recentActivities.filter {
            $0.intensity == "Hard" || $0.intensity == "Very hard"
        }
        if hard.contains(where: { $0.intensity == "Very hard" }) { return 2 }
        if hard.count >= 2 { return 2 }
        if !hard.isEmpty { return 1 }
        return 0
    }

    private func memoryHardActivityName(_ memory: TrainingMemorySummary) -> String? {
        memory.recentActivities
            .filter { $0.intensity == "Hard" || $0.intensity == "Very hard" }
            .first
            .map { $0.type.lowercased() }
    }
}
