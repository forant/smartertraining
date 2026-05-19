import Foundation

// MARK: - Types

/// The class of question being asked. Each kind has its own choice set and template.
enum CoachReflectionPromptKind: String, Codable, Equatable {
    case effortLimit          // "Did your legs or breathing limit you first?"
    case repeatability        // "Did this feel more repeatable than recent VO2 sessions?"
    case sustainability       // "Did the effort feel sustainable through the set?"
    case shortenedReason      // "You shortened today's workout. Time or fatigue?"
    case controlLateInWorkout // "HR stayed steadier late. Felt more controlled?"
}

enum CoachReflectionResponse: String, Codable, Equatable {
    case legs, breathing, both, neither           // effort limit
    case easier, sameAs, harder                   // comparative
    case time, fatigue, timeAndFatigue            // shortened reason
    case yes, somewhat, no                        // sustainability / control
}

struct CoachReflectionChoice: Equatable {
    let response: CoachReflectionResponse
    let label: String
}

/// A generated, athlete-targeted prompt. Built once at session-finish time.
struct CoachReflectionPrompt: Equatable {
    let kind: CoachReflectionPromptKind
    let question: String
    let choices: [CoachReflectionChoice]
}

/// The persisted record of one reflection interaction.
struct CoachReflection: Codable, Identifiable, Equatable {
    let id: UUID
    let workoutId: UUID
    let promptKind: CoachReflectionPromptKind
    let question: String
    let response: CoachReflectionResponse
    let responseLabel: String
    let note: String?
    let validation: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        promptKind: CoachReflectionPromptKind,
        question: String,
        response: CoachReflectionResponse,
        responseLabel: String,
        note: String? = nil,
        validation: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.promptKind = promptKind
        self.question = question
        self.response = response
        self.responseLabel = responseLabel
        self.note = note
        self.validation = validation
        self.createdAt = createdAt
    }
}

// MARK: - Generator

/// Deterministic prompt generator. Picks at most one targeted question based on
/// workout signals. Returns nil when no prompt is appropriate (recovery rides,
/// missing data) — the card is hidden in that case.
enum CoachReflectionGenerator {

    static func generate(
        workout: CompletedWorkout,
        recommendation: WorkoutRecommendation,
        expectedDuration: TimeInterval?,
        recentRides: [CompletedWorkout],
        coachNotes: CoachNotes = .empty
    ) -> CoachReflectionPrompt? {
        // Skip on recovery — reflection prompts should land on training stress days.
        if recommendation.type == .recovery { return nil }

        // Skip if the workout is too short or has no real engagement.
        guard workout.duration >= 60 else { return nil }

        // Shortened workout: prioritize asking why.
        if let expected = expectedDuration,
           expected > 0,
           workout.duration < expected * 0.75 {
            return shortenedPrompt()
        }

        // Quality workouts: comparative prompts when we have prior context.
        if recommendation.type == .quality, let subtype = recommendation.qualitySubtype {
            let priorSameSubtype = recentRides.filter { $0.workoutType == .quality && $0.id != workout.id }
            switch subtype {
            case .vo2:
                if !priorSameSubtype.isEmpty {
                    return repeatabilityPrompt(comparisonLabel: "your recent VO2 sessions")
                }
                return effortLimitPrompt()
            case .threshold:
                if !priorSameSubtype.isEmpty {
                    return sustainabilityPrompt(comparisonLabel: "your recent threshold work")
                }
                return effortLimitPrompt()
            case .muscularEndurance:
                return effortLimitPrompt()
            case .overUnders:
                return controlLatePrompt()
            case .tempo:
                return sustainabilityPrompt(comparisonLabel: "your recent tempo work")
            }
        }

        // Endurance default: keep it light — ask what limited you, if anything.
        return effortLimitPrompt()
    }

    // MARK: Prompt builders

    private static func effortLimitPrompt() -> CoachReflectionPrompt {
        CoachReflectionPrompt(
            kind: .effortLimit,
            question: "Did your legs or breathing limit you first?",
            choices: [
                CoachReflectionChoice(response: .legs, label: "Legs"),
                CoachReflectionChoice(response: .breathing, label: "Breathing"),
                CoachReflectionChoice(response: .both, label: "Both"),
                CoachReflectionChoice(response: .neither, label: "Neither")
            ]
        )
    }

    private static func repeatabilityPrompt(comparisonLabel: String) -> CoachReflectionPrompt {
        CoachReflectionPrompt(
            kind: .repeatability,
            question: "Did this feel more repeatable than \(comparisonLabel)?",
            choices: [
                CoachReflectionChoice(response: .easier, label: "More repeatable"),
                CoachReflectionChoice(response: .sameAs, label: "About the same"),
                CoachReflectionChoice(response: .harder, label: "Harder")
            ]
        )
    }

    private static func sustainabilityPrompt(comparisonLabel: String) -> CoachReflectionPrompt {
        CoachReflectionPrompt(
            kind: .sustainability,
            question: "Did the effort feel sustainable through the set?",
            choices: [
                CoachReflectionChoice(response: .yes, label: "Yes"),
                CoachReflectionChoice(response: .somewhat, label: "Somewhat"),
                CoachReflectionChoice(response: .no, label: "Not really")
            ]
        )
    }

    private static func shortenedPrompt() -> CoachReflectionPrompt {
        CoachReflectionPrompt(
            kind: .shortenedReason,
            question: "You shortened today's workout. Mostly time-constrained or fatigue-constrained?",
            choices: [
                CoachReflectionChoice(response: .time, label: "Time"),
                CoachReflectionChoice(response: .fatigue, label: "Fatigue"),
                CoachReflectionChoice(response: .timeAndFatigue, label: "Both")
            ]
        )
    }

    private static func controlLatePrompt() -> CoachReflectionPrompt {
        CoachReflectionPrompt(
            kind: .controlLateInWorkout,
            question: "Did the overs feel more controlled this time around?",
            choices: [
                CoachReflectionChoice(response: .yes, label: "Yes"),
                CoachReflectionChoice(response: .somewhat, label: "Somewhat"),
                CoachReflectionChoice(response: .no, label: "Not really")
            ]
        )
    }
}

// MARK: - Validator

/// Produces a short, validating coach response. Layered: a baseline reflection
/// per (kind × response), optionally extended with one history reference and/or
/// one coach-note reference when applicable. Stays grounded, no overstatement.
enum CoachReflectionValidator {

    struct Context {
        let recentSameSubtypeCount: Int
        let priorSameResponse: Bool
        let coachNoteTags: Set<CoachNoteTag>

        static let empty = Context(recentSameSubtypeCount: 0, priorSameResponse: false, coachNoteTags: [])
    }

    static func validate(
        promptKind: CoachReflectionPromptKind,
        response: CoachReflectionResponse,
        context: Context
    ) -> String {
        let baseline = baselineLine(for: promptKind, response: response)
        let suffix = historySuffix(for: promptKind, response: response, context: context)
        if suffix.isEmpty { return baseline }
        return "\(baseline) \(suffix)"
    }

    // MARK: Baseline

    private static func baselineLine(for kind: CoachReflectionPromptKind, response: CoachReflectionResponse) -> String {
        switch (kind, response) {
        case (.effortLimit, .legs):
            return "Noted — legs giving in first is common on this kind of work."
        case (.effortLimit, .breathing):
            return "Noted — breathing-limited is the more aerobic side of the equation."
        case (.effortLimit, .both):
            return "Both at once usually means the workout did its job."
        case (.effortLimit, .neither):
            return "That suggests there's still gas in the tank for next time."

        case (.repeatability, .easier):
            return "Repeatability landing easier is a meaningful sign your engine is adapting."
        case (.repeatability, .sameAs):
            return "Holding steady on repeatability is its own kind of progress."
        case (.repeatability, .harder):
            return "Harder days happen — load, sleep, or stress can all show up here."

        case (.sustainability, .yes):
            return "Sustainable effort at this intensity is exactly what builds the ceiling."
        case (.sustainability, .somewhat):
            return "Partial sustainability is honest data — worth tracking how it evolves."
        case (.sustainability, .no):
            return "Not sustainable today doesn't undo the work. The session still counts."

        case (.shortenedReason, .time):
            return "Real-life days happen. Showing up for what fit is the point."
        case (.shortenedReason, .fatigue):
            return "Backing off when fatigue is real is the smart call — that's how consistency lasts."
        case (.shortenedReason, .timeAndFatigue):
            return "Both at once is a fair signal to keep today modest."

        case (.controlLateInWorkout, .yes):
            return "Late-set control suggests the lactate handling is coming together."
        case (.controlLateInWorkout, .somewhat):
            return "Partial late control still beats a hard fade — worth noting the direction."
        case (.controlLateInWorkout, .no):
            return "Late-set struggle is normal on over/unders. It's a tough kind of quality."

        // Defensive fallback — should never hit in normal flow.
        default:
            return "Noted. Thanks for the read on how that felt."
        }
    }

    // MARK: History suffix

    private static func historySuffix(
        for kind: CoachReflectionPromptKind,
        response: CoachReflectionResponse,
        context: Context
    ) -> String {
        switch kind {
        case .effortLimit:
            if response == .legs, context.coachNoteTags.contains(.legsFatigueFirst) {
                return "That's consistent with what you've told me about your legs going first — useful as we tune the work."
            }
            if response == .legs, context.priorSameResponse {
                return "You've flagged legs limiting first before, which lines up with where you're building durability."
            }
            if response == .breathing, context.coachNoteTags.contains(.strongAerobicFitness) {
                return "Your aerobic side is strong, so getting breathing-limited usually means the intensity is in the right zone."
            }
            return ""

        case .repeatability:
            if response == .easier, context.recentSameSubtypeCount >= 1 {
                return "Compared to your last \(recentLabel(count: context.recentSameSubtypeCount)), that's a positive trend in repeatability."
            }
            if response == .harder, context.coachNoteTags.contains(.vo2MentallyDifficult) {
                return "You've mentioned VO2 can feel mentally tough — getting through the session is still the win."
            }
            return ""

        case .sustainability:
            if response == .yes, context.recentSameSubtypeCount >= 1 {
                return "That's a step forward compared to the last \(recentLabel(count: context.recentSameSubtypeCount))."
            }
            return ""

        case .shortenedReason:
            if response == .time, context.coachNoteTags.contains(.limitedWeekdayTime) {
                return "Matches what you've told me about weekday time — we can lean shorter on these days."
            }
            if response == .fatigue, context.coachNoteTags.contains(.poorSleepRecently) {
                return "Sleep has been inconsistent lately — that's a credible reason to dial it back."
            }
            return ""

        case .controlLateInWorkout:
            if response == .yes, context.recentSameSubtypeCount >= 1 {
                return "That looks smoother than recent over/under work — a good sign."
            }
            return ""
        }
    }

    private static func recentLabel(count: Int) -> String {
        count == 1 ? "session of this kind" : "few sessions of this kind"
    }
}
