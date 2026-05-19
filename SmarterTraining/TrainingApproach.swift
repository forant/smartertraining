import Foundation

/// How the athlete wants the adaptive coach to balance progression pressure,
/// recovery, and long-term sustainability.
///
/// IMPORTANT design notes:
///   - None of these are "better" — they reflect different goals, schedules,
///     and recovery realities. The UI must never imply otherwise.
///   - `.balanced` is the canonical / default coaching model.
///   - Even `.ambitious` respects every readiness, load, and recovery
///     protection in the engine. Approach biases thresholds; it never
///     overrides safeguards.
enum TrainingApproach: String, Codable, Equatable, CaseIterable {
    case sustainable
    case balanced
    case ambitious

    static let `default`: TrainingApproach = .balanced

    var title: String {
        switch self {
        case .sustainable: "Sustainable"
        case .balanced: "Balanced"
        case .ambitious: "Ambitious"
        }
    }

    var shortDescription: String {
        switch self {
        case .sustainable: "Prioritize consistency and recovery."
        case .balanced: "Push when the signals support it."
        case .ambitious: "Seek adaptation opportunities more aggressively when recovery allows."
        }
    }

    /// Slightly longer copy used in the coach-facing settings card.
    var coachExplanation: String {
        switch self {
        case .sustainable:
            return "Slower progression, more recovery-protective. Best when consistency matters more than peak adaptation right now."
        case .balanced:
            return "The canonical coaching model. Pushes when the signals are clearly there, backs off when they're not."
        case .ambitious:
            return "Pursues adaptation more aggressively when recovery allows. Still respects fatigue and readiness — never reckless."
        }
    }

    // MARK: - Behavioral knobs

    /// How many consecutive confident successes are required to advance a tier.
    var advancementThreshold: Int {
        switch self {
        case .sustainable: 3
        case .balanced: 2
        case .ambitious: 2
        }
    }

    /// How many consecutive struggles are required before regressing a tier.
    /// Ambitious tolerates one extra strike before pulling back.
    var regressionThreshold: Int {
        switch self {
        case .sustainable: 2
        case .balanced: 2
        case .ambitious: 3
        }
    }

    /// Ambitious doesn't let a single "hard but completed" session reset the
    /// success streak — the athlete is asking the coach to hold confidence.
    var preservesSuccessOnMixed: Bool {
        self == .ambitious
    }

    /// Static willingness bias applied on top of profile and progression.
    /// Capped within the existing -2…+2 willingness band.
    var willingnessBias: Int {
        switch self {
        case .sustainable: -1
        case .balanced: 0
        case .ambitious: 1
        }
    }
}
