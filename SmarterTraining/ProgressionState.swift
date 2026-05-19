import Foundation

// MARK: - Tier

/// A coarse, coach-readable progression level per quality subtype.
/// Intentionally only 4 levels — this is *coaching memory*, not periodization.
enum ProgressionTier: Int, Codable, Equatable, Comparable, CaseIterable {
    case starter = 0
    case progressing = 1
    case stable = 2
    case advanced = 3

    static func < (lhs: ProgressionTier, rhs: ProgressionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .starter: "Starter"
        case .progressing: "Progressing"
        case .stable: "Stable"
        case .advanced: "Advanced"
        }
    }

    func next() -> ProgressionTier { ProgressionTier(rawValue: min(rawValue + 1, ProgressionTier.advanced.rawValue))! }
    func previous() -> ProgressionTier { ProgressionTier(rawValue: max(rawValue - 1, ProgressionTier.starter.rawValue))! }
}

// MARK: - Per-subtype state

struct SubtypeProgressionState: Codable, Equatable {
    var tier: ProgressionTier
    var consecutiveSuccesses: Int
    var consecutiveStruggles: Int
    var sessionsAtCurrentTier: Int
    var lastUpdatedAt: Date?

    static let starter = SubtypeProgressionState(
        tier: .starter,
        consecutiveSuccesses: 0,
        consecutiveStruggles: 0,
        sessionsAtCurrentTier: 0,
        lastUpdatedAt: nil
    )
}

// MARK: - Signal

/// Coarse classification of how a quality session landed. Deliberately
/// three levels — the goal is conservative progression, not micro-tuning.
enum ProgressionSignal: Equatable {
    case confidentSuccess  // easy + completion (often + positive reflection)
    case mixed             // hard but completed, or shortened, or ambiguous reflection
    case struggle          // tooMuch, or shortened-due-to-fatigue + hard
}

// MARK: - State container

struct ProgressionState: Codable, Equatable {

    /// Storage keyed by the subtype's rawValue so the JSON form stays readable.
    private var storage: [String: SubtypeProgressionState]

    static let empty = ProgressionState(storage: [:])

    init(storage: [String: SubtypeProgressionState] = [:]) {
        self.storage = storage
    }

    func state(for subtype: QualitySubtype) -> SubtypeProgressionState {
        storage[subtype.rawValue] ?? .starter
    }

    func tier(for subtype: QualitySubtype) -> ProgressionTier {
        state(for: subtype).tier
    }

    /// Returns a new state with the signal applied to the given subtype.
    ///
    /// Tier transitions are driven by approach-specific thresholds:
    ///   - sustainable: 3 successes to advance, 2 struggles to regress
    ///   - balanced (default): 2 to advance, 2 to regress
    ///   - ambitious: 2 to advance (mixed forgiven), 3 struggles to regress
    func applying(
        signal: ProgressionSignal,
        to subtype: QualitySubtype,
        approach: TrainingApproach = .balanced,
        at now: Date = Date()
    ) -> ProgressionState {
        var sub = state(for: subtype)
        sub.sessionsAtCurrentTier += 1
        sub.lastUpdatedAt = now

        switch signal {
        case .confidentSuccess:
            sub.consecutiveSuccesses += 1
            sub.consecutiveStruggles = 0
            if sub.consecutiveSuccesses >= approach.advancementThreshold, sub.tier < .advanced {
                sub.tier = sub.tier.next()
                sub.consecutiveSuccesses = 0
                sub.sessionsAtCurrentTier = 0
            }
        case .struggle:
            sub.consecutiveStruggles += 1
            sub.consecutiveSuccesses = 0
            if sub.consecutiveStruggles >= approach.regressionThreshold, sub.tier > .starter {
                sub.tier = sub.tier.previous()
                sub.consecutiveStruggles = 0
                sub.sessionsAtCurrentTier = 0
            }
        case .mixed:
            // Mixed signals nudge both counters toward neutral, preserving prior bias slightly.
            // Ambitious holds the success streak — a "hard but completed" session is not
            // a confidence reset for athletes asking the coach to lean forward.
            if !approach.preservesSuccessOnMixed {
                sub.consecutiveSuccesses = max(0, sub.consecutiveSuccesses - 1)
            }
            sub.consecutiveStruggles = max(0, sub.consecutiveStruggles - 1)
        }

        var updated = storage
        updated[subtype.rawValue] = sub
        return ProgressionState(storage: updated)
    }

    /// Number of subtypes the athlete has demonstrably stabilized in or beyond.
    var stableOrBetterSubtypeCount: Int {
        QualitySubtype.allCases.filter { tier(for: $0) >= .stable }.count
    }
}

// MARK: - Signal Classification

/// Translates the post-workout signals available today (feedback + optional
/// coach reflection) into a coarse ProgressionSignal. Phase 1 keeps this
/// intentionally simple — feedback is the primary input.
enum ProgressionSignalClassifier {

    static func signal(
        feedback: WorkoutFeedback?,
        reflection: CoachReflection? = nil
    ) -> ProgressionSignal? {
        guard let feedback else { return nil }

        switch feedback {
        case .easy:
            return reflectionDowngrades(reflection) ? .mixed : .confidentSuccess
        case .right:
            if reflectionUpgrades(reflection) { return .confidentSuccess }
            if reflectionDowngrades(reflection) { return .mixed }
            return .confidentSuccess
        case .hard:
            return reflectionDowngrades(reflection) ? .struggle : .mixed
        case .tooMuch:
            return .struggle
        }
    }

    private static func reflectionUpgrades(_ r: CoachReflection?) -> Bool {
        guard let r else { return false }
        // "More repeatable", "Yes" (sustainable / late control), or "Neither" limited me
        return r.response == .easier
            || (r.response == .yes && (r.promptKind == .sustainability || r.promptKind == .controlLateInWorkout))
            || (r.promptKind == .effortLimit && r.response == .neither)
    }

    private static func reflectionDowngrades(_ r: CoachReflection?) -> Bool {
        guard let r else { return false }
        return r.response == .harder
            || (r.response == .no && (r.promptKind == .sustainability || r.promptKind == .controlLateInWorkout))
            || (r.promptKind == .shortenedReason && r.response == .fatigue)
    }
}
