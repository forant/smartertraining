import Foundation

// MARK: - Tags

enum CoachNoteTag: String, Codable, CaseIterable, Equatable {
    case kneeSensitivity
    case legsFatigueFirst
    case limitedWeekdayTime
    case moreWeekendAvailability
    case poorSleepRecently
    case returningAfterBreak
    case strongAerobicFitness
    case vo2MentallyDifficult

    var label: String {
        switch self {
        case .kneeSensitivity: "Knee sensitivity"
        case .legsFatigueFirst: "Legs fatigue first"
        case .limitedWeekdayTime: "Limited weekday time"
        case .moreWeekendAvailability: "More weekend availability"
        case .poorSleepRecently: "Poor sleep recently"
        case .returningAfterBreak: "Returning after break"
        case .strongAerobicFitness: "Strong aerobic fitness"
        case .vo2MentallyDifficult: "VO2 mentally difficult"
        }
    }
}

// MARK: - Model

struct CoachNotes: Codable, Equatable {
    var freeformNote: String
    var tags: Set<CoachNoteTag>
    var updatedAt: Date?

    static let empty = CoachNotes(freeformNote: "", tags: [], updatedAt: nil)

    var isEmpty: Bool {
        freeformNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty
    }

    /// Short summary used on the TodayView entry card.
    /// "Legs fatigue first · 2 more"  /  "Working on cardio · 1 more"
    var summaryLine: String {
        let trimmedNote = freeformNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstTag = tags.sorted(by: { $0.rawValue < $1.rawValue }).first
        let extra = max(0, tags.count - 1)

        if !trimmedNote.isEmpty {
            let snippet = trimmedNote.firstSentenceOrSnippet(maxLength: 60)
            if extra > 0 {
                return "\(snippet) \u{00B7} \(tags.count) tag\(tags.count == 1 ? "" : "s")"
            }
            if let firstTag {
                return "\(snippet) \u{00B7} \(firstTag.label)"
            }
            return snippet
        }
        if let firstTag {
            if extra > 0 {
                return "\(firstTag.label) \u{00B7} \(extra) more"
            }
            return firstTag.label
        }
        return ""
    }
}

// MARK: - String Helpers

private extension String {
    func firstSentenceOrSnippet(maxLength: Int) -> String {
        let collapsed = self
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let endIdx = collapsed.firstIndex(where: { ".!?".contains($0) }) {
            let upto = collapsed[..<endIdx]
            if upto.count >= 8 { return String(upto) }
        }
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength)) + "\u{2026}"
    }
}
