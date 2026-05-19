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
        var upcomingContext: UpcomingContextSummary = .empty
        var coachNotes: CoachNotes = .empty
        var progression: ProgressionState = .empty
        var approach: TrainingApproach = .balanced
    }

    func recommend(for inputs: Inputs) -> WorkoutRecommendation {
        let type = chooseWorkoutType(for: inputs)
        let subtype: QualitySubtype? = (type == .quality) ? chooseQualitySubtype(for: inputs) : nil
        let tier = subtype.map { inputs.progression.tier(for: $0) }
        let reason = buildReason(type: type, subtype: subtype, tier: tier, inputs: inputs)
        var workout = buildWorkout(
            type: type,
            subtype: subtype,
            tier: tier ?? .progressing,
            time: inputs.checkIn.timeAvailable,
            reason: reason
        )
        workout.optionalExtras = adjustExtras(workout.optionalExtras, type: type, time: inputs.checkIn.timeAvailable, profile: inputs.profile)
        return workout
    }

    // MARK: - Profile Bias

    func qualityWillingness(for profile: UserProfile) -> Int {
        qualityWillingness(for: profile, progression: .empty, approach: .balanced)
    }

    func qualityWillingness(for profile: UserProfile, progression: ProgressionState) -> Int {
        qualityWillingness(for: profile, progression: progression, approach: .balanced)
    }

    /// Willingness to prescribe quality. Bumped by demonstrable progression —
    /// an athlete who has stabilized in 2+ subtypes has earned more frequent quality.
    /// Training approach also nudges willingness up (ambitious) or down (sustainable).
    func qualityWillingness(for profile: UserProfile, progression: ProgressionState, approach: TrainingApproach) -> Int {
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

        // Progression boost: stable+ in 2+ subtypes earns a small willingness bump.
        if progression.stableOrBetterSubtypeCount >= 2 {
            score += 1
        }

        // Approach bias (sustainable -1, balanced 0, ambitious +1).
        score += approach.willingnessBias

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
        let willingness = qualityWillingness(for: inputs.profile, progression: inputs.progression, approach: inputs.approach)
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

        // Step A4: Upcoming context
        let upcoming = inputs.upcomingContext

        if upcoming.hasBigRideSoon, let days = upcoming.daysUntilBigRide, days <= 1 {
            if checkIn.overallFeel == "Great" && checkIn.legs == "Fresh" {
                return .endurance
            }
            return .recovery
        }

        if upcoming.recoveryFocusedActive {
            if checkIn.legs == "Heavy" || checkIn.overallFeel != "Great" {
                return .recovery
            }
            return .endurance
        }

        if upcoming.hasTravelSoon, let days = upcoming.daysUntilTravel, days <= 1 {
            if checkIn.legs == "Heavy" || checkIn.overallFeel != "Great" {
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

        let pushHarderBoost = upcoming.wantsToPushHarder && checkIn.legs != "Heavy" && actStress == 0
        let qualityHistoryThreshold = (willingness >= 1 || pushHarderBoost) ? 1 : 2

        let weekLoadHigh = memory.hasHighRecentLoad
            || (memory.hardDayCount7d >= 2 && memory.recentLifeStressLevel >= 2)

        let upcomingBlocksQuality = (upcoming.hasBigRideSoon && (upcoming.daysUntilBigRide ?? 99) <= 1)
            || upcoming.recoveryFocusedActive

        if !upcomingBlocksQuality && !weekLoadHigh && easierCount >= qualityHistoryThreshold && signalsStrong && !hardBias && willingness > -2 && actStress < 2 {
            return .quality
        }

        // Step F: Legs shape the default
        if checkIn.legs == "Heavy" {
            return .endurance
        }

        // Fresh legs + good signals can open quality
        if !upcomingBlocksQuality && !weekLoadHigh && checkIn.legs == "Fresh"
            && checkIn.overallFeel == "Great"
            && checkIn.motivation == "High"
            && lastType != .quality
            && !hardBias
            && willingness >= -1
            && actStress == 0 {
            return .quality
        }

        // Easy boost
        if !upcomingBlocksQuality && !weekLoadHigh && easyBoost
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

    // MARK: - Quality Subtype Selection

    /// Picks the most appropriate quality subtype for today. Honors intent hints
    /// (when the intent is active today), down-shifts on heavy recent load, matches
    /// readiness to fatigue cost, enforces week-level variety, and falls back to
    /// tempo (the lowest-cost quality option).
    func chooseQualitySubtype(for inputs: Inputs) -> QualitySubtype {
        // Fix A: only honor the intent hint when the intent is active today.
        if let intent = inputs.activeIntent, !intent.isExpired,
           intent.activeDay() != nil,
           let hinted = intent.qualitySubtype {
            return hinted
        }

        let checkIn = inputs.checkIn
        let memory = inputs.memorySummary
        let time = checkIn.timeAvailable
        let legs = checkIn.legs
        let feel = checkIn.overallFeel
        let motivation = checkIn.motivation
        let willingness = qualityWillingness(for: inputs.profile, progression: inputs.progression, approach: inputs.approach)
        let history = inputs.recentHistory

        let peakReadiness = feel == "Great" && legs == "Fresh" && motivation == "High"
        let goodReadiness = (feel == "Great" || feel == "Good")
            && (legs == "Fresh" || legs == "Normal")
            && motivation != "Low"

        // Fix B: when the week has already absorbed real load, the body needs
        // sub-threshold work — not VO2 / over-unders. Down-shift the priority order.
        let loadDownshift = memory.hasHighRecentLoad
            || memory.hardDayCount7d >= 2
            || memory.recentIntensityLoadEstimate >= 8

        // Fix E: VO2 is the highest-cost option. Withhold it from users who are
        // returning after a break, who have very little recent history to build on,
        // or whose profile genuinely doesn't support that intensity yet.
        let vo2Allowed = !memory.isReturningAfterBreak
            && history.count >= 2
            && willingness >= 1

        // Build eligibility list in priority order. Under load down-shift, low-cost
        // options lead; otherwise hardest-first.
        var preferred: [QualitySubtype] = []

        if loadDownshift {
            if time >= 35 { preferred.append(.muscularEndurance) }
            preferred.append(.tempo)
            if goodReadiness && time >= 25 { preferred.append(.threshold) }
            // VO2 and over-unders intentionally omitted under load down-shift.
        } else {
            if peakReadiness && vo2Allowed && time >= 25 {
                preferred.append(.vo2)
            }
            if goodReadiness && time >= 35 {
                preferred.append(.overUnders)
            }
            if goodReadiness && time >= 25 {
                preferred.append(.threshold)
            }
            if time >= 35 {
                preferred.append(.muscularEndurance)
            }
            preferred.append(.tempo)
        }

        // Coach notes: apply persistent athlete context as soft biases.
        // These are intentionally minimal and explainable — not a planning engine.
        let notes = inputs.coachNotes
        if notes.tags.contains(.vo2MentallyDifficult) {
            preferred.removeAll { $0 == .vo2 }
        }
        if notes.tags.contains(.kneeSensitivity), preferred.count > 1 {
            // Long sustained sub-threshold work tends to load the knees; de-prioritize ME.
            preferred.removeAll { $0 == .muscularEndurance }
        }
        if notes.tags.contains(.legsFatigueFirst),
           let idx = preferred.firstIndex(of: .muscularEndurance), idx > 0 {
            // Up-prioritize muscular endurance to build durable strength.
            preferred.remove(at: idx)
            preferred.insert(.muscularEndurance, at: 0)
        }

        // Fix C: enforce week-level variety in two layers.
        //   1. Drop subtypes already used 2+ times in the last 7 days.
        //   2. Prefer subtypes never used this week over ones used once.
        //   3. Drop the immediately-prior subtype to prevent back-to-back repeats.
        let weeklyCounts = Dictionary(grouping: memory.recentQualitySubtypes7d, by: { $0 })
            .mapValues(\.count)

        let underUsed = preferred.filter { (weeklyCounts[$0] ?? 0) < 2 }
        if !underUsed.isEmpty { preferred = underUsed }

        let neverUsedThisWeek = preferred.filter { weeklyCounts[$0] == nil }
        if !neverUsedThisWeek.isEmpty { preferred = neverUsedThisWeek }

        if let last = memory.lastQualitySubtype, preferred.count > 1,
           let idx = preferred.firstIndex(of: last) {
            preferred.remove(at: idx)
        }

        return preferred.first ?? .tempo
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
        buildReason(type: type, subtype: nil, tier: nil, inputs: inputs)
    }

    func buildReason(type: WorkoutType, subtype: QualitySubtype?, inputs: Inputs) -> String {
        buildReason(type: type, subtype: subtype, tier: nil, inputs: inputs)
    }

    func buildReason(type: WorkoutType, subtype: QualitySubtype?, tier: ProgressionTier?, inputs: Inputs) -> String {
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

        let upcoming = inputs.upcomingContext

        if let reason = buildUpcomingContextReason(type: type, upcoming: upcoming, checkIn: checkIn) {
            return reason
        }

        switch type {
        case .recovery:
            return buildRecoveryReason(checkIn: checkIn, lastFeedback: lastFeedback, historyCount: historyCount, actStress: actStress, memory: memory)
        case .endurance:
            return buildEnduranceReason(checkIn: checkIn, lastType: lastType, lastFeedback: lastFeedback, easierCount: easierCount, profile: inputs.profile, actStress: actStress, memory: memory)
        case .quality:
            let baseline = buildQualityReason(subtype: subtype, checkIn: checkIn, lastFeedback: lastFeedback, easierCount: easierCount, profile: inputs.profile, memory: memory)
            guard let subtype, let tier else { return baseline }
            let progressionLine = progressionFraming(
                subtype: subtype,
                tier: tier,
                state: inputs.progression.state(for: subtype),
                approach: inputs.approach
            )
            return progressionLine.isEmpty ? baseline : "\(baseline) \(progressionLine)"
        }
    }

    /// Short coach-style line that explains why today's workout is at this tier,
    /// flavored by training approach. Empty when there's nothing meaningful to add
    /// (e.g. starter tier with no history).
    private func progressionFraming(
        subtype: QualitySubtype,
        tier: ProgressionTier,
        state: SubtypeProgressionState,
        approach: TrainingApproach
    ) -> String {
        let subtypeName = subtype.label.lowercased()
        switch tier {
        case .starter:
            // Don't volunteer "you're a beginner" — silent at this tier.
            return ""
        case .progressing:
            guard state.consecutiveSuccesses >= 1 else { return "" }
            switch approach {
            case .sustainable:
                return "Recent \(subtypeName) work has been landing — keeping the structure steady today."
            case .balanced:
                return "Recent \(subtypeName) work has been landing — keeping the structure consistent today."
            case .ambitious:
                return "Recent \(subtypeName) work has been landing — small bump in progression pressure today."
            }
        case .stable:
            switch approach {
            case .sustainable:
                return "You've handled recent \(subtypeName) work consistently — keeping progression steady and sustainable."
            case .balanced:
                return "You've handled recent \(subtypeName) work consistently, so this is a good chance to extend the work."
            case .ambitious:
                return "You've been handling recent \(subtypeName) work consistently, so this is a good opportunity to push progression slightly."
            }
        case .advanced:
            return "\(subtype.label) is one of your stronger systems right now — today reflects that."
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

    private func buildQualityReason(subtype: QualitySubtype?, checkIn: CheckIn, lastFeedback: WorkoutFeedback?, easierCount: Int, profile: UserProfile, memory: TrainingMemorySummary) -> String {
        let baseline = baselineQualityReason(checkIn: checkIn, lastFeedback: lastFeedback, easierCount: easierCount, profile: profile, memory: memory)
        guard let subtype else { return baseline }
        return "\(baseline) \(subtypeFraming(subtype))"
    }

    private func baselineQualityReason(checkIn: CheckIn, lastFeedback: WorkoutFeedback?, easierCount: Int, profile: UserProfile, memory: TrainingMemorySummary) -> String {
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

    /// Short coach-style framing line that explains *what kind* of quality and why it fits today.
    private func subtypeFraming(_ subtype: QualitySubtype) -> String {
        switch subtype {
        case .vo2:
            return "VO2 intervals make sense when you're peaked — short, sharp efforts above threshold."
        case .threshold:
            return "Threshold work builds the ceiling: sustained efforts right at your limit."
        case .muscularEndurance:
            return "Long sub-threshold blocks build durable strength without the spike of full quality."
        case .tempo:
            return "Tempo is the most repeatable quality dose — productive without digging a hole."
        case .overUnders:
            return "Over/unders teach you to ride through brief surges and recover at pace."
        }
    }

    // MARK: - Workout Builder

    func buildWorkout(type: WorkoutType, time: Int, reason: String) -> WorkoutRecommendation {
        buildWorkout(type: type, subtype: nil, tier: .progressing, time: time, reason: reason)
    }

    func buildWorkout(type: WorkoutType, subtype: QualitySubtype?, time: Int, reason: String) -> WorkoutRecommendation {
        buildWorkout(type: type, subtype: subtype, tier: .progressing, time: time, reason: reason)
    }

    func buildWorkout(type: WorkoutType, subtype: QualitySubtype?, tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        switch type {
        case .recovery: return buildRecovery(time: time, reason: reason)
        case .endurance: return buildEndurance(time: time, reason: reason)
        case .quality: return buildQuality(subtype: subtype ?? .threshold, tier: tier, time: time, reason: reason)
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

    private func buildQuality(subtype: QualitySubtype, tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        switch subtype {
        case .vo2: return buildVO2(tier: tier, time: time, reason: reason)
        case .threshold: return buildThreshold(tier: tier, time: time, reason: reason)
        case .muscularEndurance: return buildMuscularEndurance(tier: tier, time: time, reason: reason)
        case .tempo: return buildTempo(tier: tier, time: time, reason: reason)
        case .overUnders: return buildOverUnders(tier: tier, time: time, reason: reason)
        }
    }

    // MARK: VO2 Max (106–115% FTP)

    private func buildVO2(tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        // Short time uses the compact pattern regardless of tier — keeps trainer-friendly.
        if time <= 30 {
            return WorkoutRecommendation(
                type: .quality, qualitySubtype: .vo2,
                title: "Compact VO2 Intervals",
                summary: "Short, sharp efforts above threshold",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "6 min", targetText: "Build from easy to steady, include 2 x 30 sec openers"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "5 x 2 min", targetText: "108\u{2013}115% FTP with 2 min easy between reps"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "4 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        // Tier-aware main set, picking the highest tier that fits.
        let resolved = resolveTier(requested: tier, time: time, minimums: [
            .advanced: 55, .stable: 48, .progressing: 40, .starter: 0
        ])
        let mainText: (String, String)
        let title: String
        let summary: String
        switch resolved {
        case .starter:
            mainText = ("4 x 2 min", "108\u{2013}115% FTP with 2 min easy between reps")
            title = "VO2 Intervals \u{2014} Starter"
            summary = "Short reps above threshold"
        case .progressing:
            mainText = ("5 x 3 min", "106\u{2013}112% FTP with 3 min easy between reps")
            title = "VO2 Max Intervals"
            summary = "Hard intervals above threshold"
        case .stable:
            mainText = ("6 x 3 min", "106\u{2013}112% FTP with 3 min easy between reps")
            title = "VO2 Max Intervals"
            summary = "Extended VO2 set"
        case .advanced:
            mainText = ("6 x 3 min", "110\u{2013}115% FTP with 2 min 30 sec easy between reps")
            title = "VO2 Max Intervals \u{2014} Dense"
            summary = "Dense VO2 set, tighter recoveries"
        }
        let warmupMin = time >= 60 ? 12 : 10
        let cooldownMin = time >= 60 ? 8 : 5
        return WorkoutRecommendation(
            type: .quality, qualitySubtype: .vo2,
            title: title, summary: summary, reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "\(warmupMin) min", targetText: "Build from easy to steady, include 2 x 30 sec openers"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: mainText.0, targetText: mainText.1),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "\(cooldownMin) min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: Threshold (95–100% FTP)

    private func buildThreshold(tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 30 {
            return WorkoutRecommendation(
                type: .quality, qualitySubtype: .threshold,
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
        let resolved = resolveTier(requested: tier, time: time, minimums: [
            .advanced: 55, .stable: 55, .progressing: 35, .starter: 0
        ])
        let mainText: (String, String)
        let title: String
        let summary: String
        switch resolved {
        case .starter:
            mainText = ("3 x 5 min", "95\u{2013}100% FTP with 3 min easy between reps")
            title = "Threshold Intervals \u{2014} Starter"
            summary = "Shorter at-threshold blocks"
        case .progressing:
            mainText = ("4 x 5 min", "95\u{2013}100% FTP with 3 min easy between reps")
            title = "Threshold Intervals"
            summary = "Controlled quality work"
        case .stable:
            mainText = ("3 x 10 min", "95\u{2013}100% FTP with 3 min easy between reps")
            title = "Threshold Intervals \u{2014} Extended"
            summary = "Longer time at threshold"
        case .advanced:
            mainText = ("2 x 15 min", "95\u{2013}100% FTP with 4 min easy between reps")
            title = "Threshold Intervals \u{2014} Sustained"
            summary = "Sustained time at threshold"
        }
        // Match the historical "long" threshold pacing for time>=60 so users get
        // a real 15-min warmup at full sessions; shorter sessions keep a 10-min warmup.
        let warmupMin = time >= 60 ? 15 : 10
        let cooldownMin = time >= 60 ? 10 : 5
        return WorkoutRecommendation(
            type: .quality, qualitySubtype: .threshold,
            title: title, summary: summary, reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "\(warmupMin) min", targetText: "Build from easy to steady"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: mainText.0, targetText: mainText.1),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "\(cooldownMin) min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: Muscular Endurance (88–95% FTP)

    private func buildMuscularEndurance(tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 35 {
            return WorkoutRecommendation(
                type: .quality, qualitySubtype: .muscularEndurance,
                title: "Muscular Endurance",
                summary: "Sustained sub-threshold blocks",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "6 min", targetText: "Build from easy to steady"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "2 x 10 min", targetText: "88\u{2013}95% FTP with 3 min easy between reps"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "4 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        let resolved = resolveTier(requested: tier, time: time, minimums: [
            .advanced: 60, .stable: 60, .progressing: 40, .starter: 0
        ])
        let mainText: (String, String)
        let title: String
        let summary: String
        switch resolved {
        case .starter:
            mainText = ("4 x 8 min", "88\u{2013}95% FTP with 3 min easy between reps")
            title = "Muscular Endurance \u{2014} Starter"
            summary = "Shorter sub-threshold blocks"
        case .progressing:
            mainText = ("3 x 9 min", "88\u{2013}95% FTP with 3 min easy between reps")
            title = "Muscular Endurance"
            summary = "Sustained sub-threshold blocks"
        case .stable:
            mainText = ("3 x 12 min", "88\u{2013}95% FTP with 4 min easy between reps")
            title = "Muscular Endurance \u{2014} Extended"
            summary = "Longer sub-threshold blocks"
        case .advanced:
            mainText = ("2 x 20 min", "88\u{2013}95% FTP with 5 min easy between reps")
            title = "Muscular Endurance \u{2014} Sustained"
            summary = "Sustained force production"
        }
        let warmupMin = time >= 60 ? 10 : 8
        let cooldownMin = time >= 60 ? 8 : 5
        return WorkoutRecommendation(
            type: .quality, qualitySubtype: .muscularEndurance,
            title: title, summary: summary, reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "\(warmupMin) min", targetText: "Build from easy to steady"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: mainText.0, targetText: mainText.1),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "\(cooldownMin) min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: Tempo (78–87% FTP)

    private func buildTempo(tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        if time <= 30 {
            return WorkoutRecommendation(
                type: .quality, qualitySubtype: .tempo,
                title: "Compact Tempo",
                summary: "Controlled steady tempo block",
                reason: reason,
                steps: [
                    WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "5 min", targetText: "Build from easy to steady"),
                    WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "18 min", targetText: "80\u{2013}87% FTP, steady"),
                    WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "5 min", targetText: "Easy spin")
                ],
                optionalExtras: []
            )
        }
        let resolved = resolveTier(requested: tier, time: time, minimums: [
            .advanced: 55, .stable: 45, .progressing: 35, .starter: 0
        ])
        let mainStep: WorkoutStep
        let title: String
        let summary: String
        switch resolved {
        case .starter:
            mainStep = WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "20 min", targetText: "80\u{2013}87% FTP, steady")
            title = "Tempo Ride \u{2014} Starter"
            summary = "Steady tempo block"
        case .progressing:
            mainStep = WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "25 min", targetText: "80\u{2013}87% FTP, steady")
            title = "Tempo Ride"
            summary = "Steady tempo block"
        case .stable:
            mainStep = WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "2 x 15 min", targetText: "80\u{2013}87% FTP with 3 min easy between reps")
            title = "Tempo Blocks"
            summary = "Two sustained tempo blocks"
        case .advanced:
            mainStep = WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: "2 x 20 min", targetText: "80\u{2013}87% FTP with 5 min easy between reps")
            title = "Tempo Blocks \u{2014} Extended"
            summary = "Longer sustained tempo work"
        }
        let warmupMin = time >= 60 ? 10 : 8
        let cooldownMin = time >= 60 ? 8 : 5
        return WorkoutRecommendation(
            type: .quality, qualitySubtype: .tempo,
            title: title, summary: summary, reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "\(warmupMin) min", targetText: "Build from easy to steady"),
                mainStep,
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "\(cooldownMin) min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: Over/Unders (alternating 105% / 88% FTP within each set)

    private func buildOverUnders(tier: ProgressionTier, time: Int, reason: String) -> WorkoutRecommendation {
        let resolved = resolveTier(requested: tier, time: time, minimums: [
            .advanced: 60, .stable: 55, .progressing: 50, .starter: 0
        ])
        let mainText: (String, String)
        let title: String
        let summary: String
        switch resolved {
        case .starter:
            mainText = ("3 x 6 min", "Alternate 2 min @ 105% FTP / 1 min @ 88% FTP, 4 min easy between sets")
            title = "Over/Under Sets \u{2014} Starter"
            summary = "Alternating supra/sub-threshold work"
        case .progressing:
            mainText = ("4 x 6 min", "Alternate 2 min @ 105% FTP / 1 min @ 88% FTP, 4 min easy between sets")
            title = "Over/Under Sets"
            summary = "Alternating supra/sub-threshold work"
        case .stable:
            mainText = ("4 x 6 min", "Alternate 2 min @ 105% FTP / 1 min @ 88% FTP, 3 min easy between sets")
            title = "Over/Under Sets \u{2014} Tight"
            summary = "Tighter recoveries between sets"
        case .advanced:
            mainText = ("5 x 6 min", "Alternate 2 min @ 105% FTP / 1 min @ 88% FTP, 4 min easy between sets")
            title = "Over/Under Sets \u{2014} Dense"
            summary = "Higher-density over/under work"
        }
        let warmupMin = time >= 60 ? 12 : 8
        let cooldownMin = time >= 60 ? 8 : 5
        return WorkoutRecommendation(
            type: .quality, qualitySubtype: .overUnders,
            title: title, summary: summary, reason: reason,
            steps: [
                WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "\(warmupMin) min", targetText: "Build from easy to steady, include 2 x 1 min openers"),
                WorkoutStep(role: .primary, modality: .cycling, name: "Main Set", durationText: mainText.0, targetText: mainText.1),
                WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "\(cooldownMin) min", targetText: "Easy spin")
            ],
            optionalExtras: []
        )
    }

    // MARK: - Tier Resolution

    /// Picks the highest tier (≤ requested) that fits in the available time.
    /// Floors at starter.
    private func resolveTier(
        requested: ProgressionTier,
        time: Int,
        minimums: [ProgressionTier: Int]
    ) -> ProgressionTier {
        var current = requested
        while current > .starter {
            let need = minimums[current] ?? 0
            if time >= need { return current }
            current = current.previous()
        }
        return .starter
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

    // MARK: - Upcoming Context Reasons

    private func buildUpcomingContextReason(type: WorkoutType, upcoming: UpcomingContextSummary, checkIn: CheckIn) -> String? {
        guard !upcoming.isEmpty else { return nil }

        if upcoming.hasBigRideSoon, let days = upcoming.daysUntilBigRide {
            let label = upcoming.bigRideLabel ?? "big ride"
            if days <= 1 {
                switch type {
                case .recovery:
                    return "Keeping today easy so you're fresher for tomorrow's \(label)."
                case .endurance:
                    return "Controlled endurance today to stay fresh for tomorrow's \(label)."
                case .quality:
                    return nil
                }
            }
            if days <= 3 && type == .quality {
                return "Today can carry some structured work because your \(label) is still a couple days out."
            }
        }

        if upcoming.recoveryFocusedActive {
            switch type {
            case .recovery:
                return "You flagged this as a recovery-focused period. Keeping things easy and intentional."
            case .endurance:
                return "Recovery-focused period, so today stays aerobic. Easy work is still forward progress."
            case .quality:
                return nil
            }
        }

        if upcoming.hasTravelSoon, let days = upcoming.daysUntilTravel, days <= 1 {
            switch type {
            case .recovery:
                return "With travel coming up, keeping today easy and low-friction."
            case .endurance:
                return "Travel is coming up, so today stays simple and controlled."
            case .quality:
                return nil
            }
        }

        if upcoming.hasBusyDaySoon, let days = upcoming.daysUntilBusyDay {
            if days == 0 && type != .quality {
                return "Today looks compressed, so we'll keep this efficient."
            }
            if days == 1 && type == .quality {
                return "Since tomorrow looks tight, today is a good chance to get focused work in\u{2014}without overdoing it."
            }
            if days == 1 && type == .endurance {
                return "Since tomorrow looks tight, today is a good chance to get useful work in\u{2014}without overdoing it."
            }
        }

        if upcoming.wantsToPushHarder && type == .quality {
            return "You flagged wanting to push harder, and today's signals support it. Controlled intensity with purpose."
        }

        return nil
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
