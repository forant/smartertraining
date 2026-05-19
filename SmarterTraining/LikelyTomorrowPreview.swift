import Foundation
import SwiftUI

// MARK: - Preview Model

/// Lightweight, probabilistic guidance about what tomorrow's workout is likely to be.
/// Built deterministically from today's workout context, the active training intent,
/// and recent memory. Never a prescription — always a preview the next check-in can override.
struct LikelyWorkoutPreview: Equatable {
    let intensity: WorkoutType
    let qualitySubtype: QualitySubtype?

    /// Human-readable name of what tomorrow likely looks like. Examples:
    /// "Recovery spin", "Endurance", "Muscular endurance", "VO2 work".
    let intensityLabel: String

    /// Realistic duration guidance. Examples:
    /// "20–30 min", "30–45 min", "ideally 60 min".
    let durationGuidance: String

    /// Optional flexibility qualifier. Examples:
    /// "if recovery stays on track", "depending on how your legs feel".
    let qualifier: String?

    /// Compact single-line headline used in small surfaces (hero card etc).
    /// "Muscular endurance · ideally 60 min"
    var compactHeadline: String {
        "\(intensityLabel) \u{00B7} \(durationGuidance)"
    }

    /// Full headline including any flexibility qualifier.
    /// "Muscular endurance · ideally 60 min, if recovery stays on track"
    var fullHeadline: String {
        guard let qualifier else { return compactHeadline }
        return "\(compactHeadline), \(qualifier)"
    }
}

// MARK: - Builder

/// Deterministic heuristic builder for the "Likely Tomorrow" preview.
/// Reads today's workout context + the active intent + memory and produces a
/// preview. Stays heuristic-driven on purpose — there is no scheduling engine.
enum LikelyTomorrowBuilder {

    static func preview(
        sourceWorkoutType: WorkoutType?,
        sourceQualitySubtype: QualitySubtype?,
        intent: ShortTermTrainingIntent?,
        profile: UserProfile,
        memory: TrainingMemorySummary,
        upcoming: UpcomingContextSummary = .empty,
        coachNotes: CoachNotes = .empty
    ) -> LikelyWorkoutPreview {
        // Resolve tomorrow's intensity, biasing toward intent.day1 when one exists.
        let intensity = resolveTomorrowIntensity(
            intent: intent,
            sourceWorkoutType: sourceWorkoutType,
            sourceQualitySubtype: sourceQualitySubtype
        )

        switch intensity {
        case .rest:
            return LikelyWorkoutPreview(
                intensity: .recovery,
                qualitySubtype: nil,
                intensityLabel: "Rest day",
                durationGuidance: "Off the bike",
                qualifier: "let your body catch up"
            )

        case .recovery:
            return LikelyWorkoutPreview(
                intensity: .recovery,
                qualitySubtype: nil,
                intensityLabel: "Recovery spin",
                durationGuidance: recoveryDuration(profile: profile),
                qualifier: nil
            )

        case .endurance:
            return LikelyWorkoutPreview(
                intensity: .endurance,
                qualitySubtype: nil,
                intensityLabel: "Endurance",
                durationGuidance: enduranceDuration(profile: profile),
                qualifier: enduranceQualifier(
                    sourceWorkoutType: sourceWorkoutType,
                    sourceQualitySubtype: sourceQualitySubtype,
                    upcoming: upcoming
                )
            )

        case .quality:
            let predicted = predictedQualitySubtype(
                sourceQualitySubtype: sourceQualitySubtype,
                memory: memory,
                coachNotes: coachNotes
            )
            return LikelyWorkoutPreview(
                intensity: .quality,
                qualitySubtype: predicted,
                intensityLabel: predicted?.label ?? "Quality",
                durationGuidance: qualityDuration(subtype: predicted, profile: profile),
                qualifier: "if recovery stays on track"
            )

        case .flexible:
            // The athlete has room; readiness will decide. Frame as "open"
            // and mention the likely quality flavor if recovery holds.
            let predicted = predictedQualitySubtype(
                sourceQualitySubtype: sourceQualitySubtype,
                memory: memory,
                coachNotes: coachNotes
            )
            let label: String
            if let predicted {
                label = "Open \u{00B7} likely \(predicted.label.lowercased())"
            } else {
                label = "Open"
            }
            return LikelyWorkoutPreview(
                intensity: .quality,
                qualitySubtype: predicted,
                intensityLabel: label,
                durationGuidance: flexibleDuration(profile: profile),
                qualifier: "depending on how your legs feel"
            )
        }
    }

    // MARK: Intensity Resolution

    private static func resolveTomorrowIntensity(
        intent: ShortTermTrainingIntent?,
        sourceWorkoutType: WorkoutType?,
        sourceQualitySubtype: QualitySubtype?
    ) -> ShortTermTrainingIntent.RecommendedIntensity {
        if let intent {
            return intent.day1RecommendedIntensity
        }
        // No intent on hand — infer a reasonable default from today's session.
        if sourceWorkoutType == .quality {
            // High-cost quality forces recovery; lower-cost allows endurance.
            return (sourceQualitySubtype?.recoveryCost ?? 3) >= 3 ? .recovery : .endurance
        }
        if sourceWorkoutType == .recovery {
            return .endurance
        }
        return .endurance
    }

    // MARK: Duration Guidance

    private static func recoveryDuration(profile: UserProfile) -> String {
        switch profile.typicalAvailability {
        case .short: return "20 min"
        default: return "20\u{2013}30 min"
        }
    }

    private static func enduranceDuration(profile: UserProfile) -> String {
        switch profile.typicalAvailability {
        case .short: return "20\u{2013}30 min"
        case .medium, .none: return "30\u{2013}45 min"
        case .long: return "45\u{2013}60 min"
        case .varies: return "30\u{2013}60 min"
        }
    }

    private static func qualityDuration(subtype: QualitySubtype?, profile: UserProfile) -> String {
        let availability = profile.typicalAvailability
        switch subtype {
        case .vo2, .overUnders:
            return availability == .short ? "ideally 30+ min" : "ideally 45 min"
        case .threshold:
            return availability == .short ? "ideally 30+ min" : "ideally 45\u{2013}60 min"
        case .muscularEndurance:
            return "ideally 45\u{2013}60 min"
        case .tempo:
            return "30\u{2013}45 min"
        case .none:
            return availability == .long ? "ideally 45\u{2013}60 min" : "30\u{2013}45 min"
        }
    }

    private static func flexibleDuration(profile: UserProfile) -> String {
        switch profile.typicalAvailability {
        case .short: return "20\u{2013}30 min"
        case .long: return "45\u{2013}60 min"
        default: return "30\u{2013}45 min"
        }
    }

    // MARK: Qualifiers

    private static func enduranceQualifier(
        sourceWorkoutType: WorkoutType?,
        sourceQualitySubtype: QualitySubtype?,
        upcoming: UpcomingContextSummary
    ) -> String? {
        if upcoming.hasBigRideSoon, (upcoming.daysUntilBigRide ?? 99) <= 2 {
            return "staying fresh for what's coming"
        }
        if let cost = sourceQualitySubtype?.recoveryCost, cost >= 3 {
            return "depending on how your legs respond"
        }
        if sourceWorkoutType == .quality {
            return "if you're feeling decent"
        }
        return nil
    }

    // MARK: Subtype Prediction

    /// Best-guess of the next likely quality subtype given today's context.
    /// Rotates away from the most recently completed subtype. Returns nil only
    /// when we have no useful signal at all.
    private static func predictedQualitySubtype(
        sourceQualitySubtype: QualitySubtype?,
        memory: TrainingMemorySummary,
        coachNotes: CoachNotes = .empty
    ) -> QualitySubtype? {
        // Highest signal: today was a quality day — rotate away from it.
        // Lower signal: today wasn't quality, fall back to the most recent quality subtype in memory.
        let avoid = sourceQualitySubtype ?? memory.lastQualitySubtype

        // Rotation order leans toward middle-cost options that are most often appropriate
        // "tomorrow" once you've already done something. VO2 is intentionally last because
        // it usually doesn't follow another quality day.
        var rotation: [QualitySubtype] = [
            .threshold,
            .muscularEndurance,
            .tempo,
            .overUnders,
            .vo2
        ]

        // Apply coach-note biases to the rotation.
        if coachNotes.tags.contains(.vo2MentallyDifficult) {
            rotation.removeAll { $0 == .vo2 }
        }
        if coachNotes.tags.contains(.kneeSensitivity) {
            rotation.removeAll { $0 == .muscularEndurance }
        }
        if coachNotes.tags.contains(.legsFatigueFirst),
           let idx = rotation.firstIndex(of: .muscularEndurance), idx > 0 {
            rotation.remove(at: idx)
            rotation.insert(.muscularEndurance, at: 0)
        }

        // Filter out the recently-used subtype and any with 2+ uses this week.
        let weeklyCounts = Dictionary(grouping: memory.recentQualitySubtypes7d, by: { $0 })
            .mapValues(\.count)
        let overused: Set<QualitySubtype> = Set(weeklyCounts.filter { $0.value >= 2 }.keys)

        let candidates = rotation.filter { candidate in
            if candidate == avoid { return false }
            if overused.contains(candidate) { return false }
            return true
        }

        return candidates.first ?? rotation.first
    }
}

// MARK: - Card View

struct LikelyTomorrowCard: View {
    let preview: LikelyWorkoutPreview

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            intensityDot
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Likely tomorrow")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .tracking(0.3)

                Text(preview.compactHeadline)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                if let qualifier = preview.qualifier {
                    Text(qualifier.capitalizedFirstLetter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(intensityColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var intensityDot: some View {
        Circle()
            .fill(intensityColor)
            .frame(width: 10, height: 10)
    }

    private var intensityColor: Color {
        switch preview.intensity {
        case .recovery: Theme.Semantic.recovery
        case .endurance: Theme.Semantic.endurance
        case .quality: Theme.Semantic.quality
        }
    }
}

/// Compact one-line "Likely tomorrow" used in space-constrained surfaces (hero cards etc).
struct LikelyTomorrowInlineLabel: View {
    let preview: LikelyWorkoutPreview
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.forward.circle")
                .font(.caption2)
            Text("Likely tomorrow: \(preview.compactHeadline)")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }
}

// MARK: - String Helper

private extension String {
    var capitalizedFirstLetter: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
