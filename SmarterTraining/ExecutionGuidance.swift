import Foundation
import SwiftUI

// MARK: - Builder

/// Deterministic generator for the "What matters today" execution-guidance line.
///
/// Returns a short paragraph (target: ~2 sentences, ~10-second read) that explains
/// *how* to execute the workout — pacing, what success feels like, what NOT to
/// optimize for. Never motivational, never hype, never bullets.
///
/// Generation layers:
///   1. Base template per workout type / quality subtype.
///   2. Optional tier addition (starter/stable/advanced).
///   3. Optional training-approach addition (sustainable/ambitious).
///   4. Optional coach-note addition (knees, vo2-mentally-difficult, legs-fatigue-first).
enum ExecutionGuidanceBuilder {

    /// Hard cap so the card stays readable in ~10 seconds.
    static let maxLength = 400

    static func build(
        recommendation: WorkoutRecommendation,
        progression: ProgressionState = .empty,
        approach: TrainingApproach = .balanced,
        coachNotes: CoachNotes = .empty
    ) -> String {
        var parts: [String] = []
        parts.append(baseTemplate(for: recommendation))

        if recommendation.type == .quality, let subtype = recommendation.qualitySubtype {
            let tier = progression.tier(for: subtype)
            if let tierLine = tierAddition(tier: tier, subtype: subtype) {
                parts.append(tierLine)
            }
            if let approachLine = approachAddition(approach: approach, subtype: subtype) {
                parts.append(approachLine)
            }
            if let noteLine = coachNoteAddition(notes: coachNotes, subtype: subtype) {
                parts.append(noteLine)
            }
        }

        let joined = parts.joined(separator: " ")
        // Trim to hard cap on a sentence boundary if we exceeded.
        return clamp(joined, maxLength: maxLength)
    }

    // MARK: - Base Templates

    private static func baseTemplate(for recommendation: WorkoutRecommendation) -> String {
        switch recommendation.type {
        case .recovery:
            return "The goal today is circulation and recovery, not fitness gain. Keep the effort easy enough that your legs gradually feel better, not heavier."
        case .endurance:
            return "Keep the effort conversational and relaxed. Finishing fresher than you expected is often a sign you paced this correctly."
        case .quality:
            return qualityTemplate(for: recommendation.qualitySubtype ?? .threshold)
        }
    }

    private static func qualityTemplate(for subtype: QualitySubtype) -> String {
        switch subtype {
        case .vo2:
            return "These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval \u{2014} the goal is consistent quality across the full session."
        case .threshold:
            return "Stay controlled early so the final interval remains smooth. Today is about repeatable sustained work, not survival."
        case .muscularEndurance:
            return "The goal today is sustained pressure, not explosive power. Your legs should gradually fatigue while breathing stays relatively controlled."
        case .tempo:
            return "This should feel steady and sustainable throughout. If you're gasping early, the effort is probably too high."
        case .overUnders:
            return "This isn't about chasing the highest possible heart rate. Focus on smooth control as fatigue accumulates \u{2014} each set should feel a little more taxing without falling apart."
        }
    }

    // MARK: - Tier Modifiers

    private static func tierAddition(tier: ProgressionTier, subtype: QualitySubtype) -> String? {
        switch tier {
        case .starter:
            return "Lean conservative early \u{2014} getting a feel for the work matters more than hitting every target."
        case .progressing:
            return nil
        case .stable:
            return "Smoothness under accumulating fatigue is the win today."
        case .advanced:
            return "Composure under sustained load is the goal. Form is the win, not the watts."
        }
    }

    // MARK: - Approach Modifiers

    private static func approachAddition(approach: TrainingApproach, subtype: QualitySubtype) -> String? {
        switch approach {
        case .sustainable:
            return "Leave a little in reserve."
        case .balanced:
            return nil
        case .ambitious:
            return "If the work feels repeatable, this is a fair day to lean into it \u{2014} composed, not reckless."
        }
    }

    // MARK: - Coach Note Modifiers

    private static func coachNoteAddition(notes: CoachNotes, subtype: QualitySubtype) -> String? {
        let tags = notes.tags
        if tags.contains(.kneeSensitivity),
           subtype == .muscularEndurance || subtype == .threshold || subtype == .overUnders {
            return "Keep the cadence comfortable \u{2014} no grinding."
        }
        if tags.contains(.vo2MentallyDifficult), subtype == .vo2 {
            return "Discomfort is the point. Just stay repeatable."
        }
        if tags.contains(.legsFatigueFirst),
           subtype == .muscularEndurance || subtype == .threshold {
            return "Pace the legs early \u{2014} they're the limiter today."
        }
        return nil
    }

    // MARK: - Length Clamp

    private static func clamp(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        // Cut at the last sentence boundary before the cap.
        let prefix = text.prefix(maxLength)
        if let lastTerminator = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefix[...lastTerminator])
        }
        return String(prefix)
    }
}

// MARK: - Card

struct ExecutionGuidanceCard: View {
    let guidance: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WHAT MATTERS TODAY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Brand.primary)
                .tracking(0.5)

            Text(guidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
    }
}
