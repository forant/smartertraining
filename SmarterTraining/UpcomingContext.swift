import Foundation

// MARK: - Event Type

enum UpcomingContextEventType: String, Codable, CaseIterable {
    case bigOutdoorRide = "big_outdoor_ride"
    case raceOrEvent = "race_or_event"
    case travel = "travel"
    case busyWorkday = "busy_workday"
    case familyCommitment = "family_commitment"
    case limitedTime = "limited_time"
    case recoveryFocused = "recovery_focused"
    case wantToPushHarder = "want_to_push_harder"
    case other = "other"

    var displayText: String {
        switch self {
        case .bigOutdoorRide: "Big ride"
        case .raceOrEvent: "Race/event"
        case .travel: "Travel"
        case .busyWorkday: "Busy workday"
        case .familyCommitment: "Family commitment"
        case .limitedTime: "Limited time"
        case .recoveryFocused: "Recovery-focused"
        case .wantToPushHarder: "Want to push harder"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .bigOutdoorRide: "bicycle"
        case .raceOrEvent: "flag.checkered"
        case .travel: "airplane"
        case .busyWorkday: "briefcase"
        case .familyCommitment: "house"
        case .limitedTime: "clock"
        case .recoveryFocused: "heart"
        case .wantToPushHarder: "flame"
        case .other: "ellipsis.circle"
        }
    }

    var isHighIntensity: Bool {
        switch self {
        case .bigOutdoorRide, .raceOrEvent, .wantToPushHarder: true
        default: false
        }
    }

    var isConstraint: Bool {
        switch self {
        case .travel, .busyWorkday, .familyCommitment, .limitedTime: true
        default: false
        }
    }

    var isRangeContext: Bool {
        switch self {
        case .travel, .recoveryFocused, .familyCommitment: true
        default: false
        }
    }

    var showsImpact: Bool {
        switch self {
        case .recoveryFocused, .wantToPushHarder: false
        default: true
        }
    }

    var reasonLabel: String {
        switch self {
        case .bigOutdoorRide: "big ride"
        case .raceOrEvent: "race"
        case .travel: "travel"
        case .busyWorkday: "busy day"
        case .familyCommitment: "commitment"
        case .limitedTime: "time constraint"
        case .recoveryFocused: "recovery focus"
        case .wantToPushHarder: "pushing harder"
        case .other: "upcoming plans"
        }
    }
}

// MARK: - Impact

enum UpcomingContextImpact: String, Codable, CaseIterable {
    case light
    case moderate
    case hard
    case veryHard = "very_hard"
    case unknown

    var displayText: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .veryHard: "Very hard"
        case .unknown: "Not sure"
        }
    }
}

// MARK: - Duration (for range contexts)

enum UpcomingContextDuration: String, Codable, CaseIterable {
    case oneToTwoDays = "1_2_days"
    case threeToFiveDays = "3_5_days"
    case aboutAWeek = "about_a_week"
    case notSure = "not_sure"

    var displayText: String {
        switch self {
        case .oneToTwoDays: "1\u{2013}2 days"
        case .threeToFiveDays: "3\u{2013}5 days"
        case .aboutAWeek: "About a week"
        case .notSure: "Not sure yet"
        }
    }

    var approximateDays: Int {
        switch self {
        case .oneToTwoDays: 2
        case .threeToFiveDays: 4
        case .aboutAWeek: 7
        case .notSure: 3
        }
    }
}

// MARK: - Event

struct UpcomingContextEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var date: Date
    var type: UpcomingContextEventType
    var impact: UpcomingContextImpact
    var duration: UpcomingContextDuration?
    var note: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        date: Date,
        type: UpcomingContextEventType,
        impact: UpcomingContextImpact = .unknown,
        duration: UpcomingContextDuration? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.type = type
        self.impact = impact
        self.duration = duration
        self.note = note
    }

    var isExpired: Bool {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfEvent = cal.startOfDay(for: date)
        if let duration {
            let endDate = cal.date(byAdding: .day, value: duration.approximateDays, to: startOfEvent)!
            return endDate < startOfToday
        }
        return startOfEvent < startOfToday
    }

    var daysFromNow: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    var dayLabel: String {
        switch daysFromNow {
        case 0: "Today"
        case 1: "Tomorrow"
        default: date.formatted(.dateTime.weekday(.wide))
        }
    }

    var narrativeLabel: String {
        if type.isRangeContext, let duration {
            if daysFromNow < 0 {
                let remaining = duration.approximateDays + daysFromNow
                if remaining <= 1 { return "\(type.displayText) wrapping up" }
                return "\(type.displayText) \u{00B7} \(remaining) more days"
            }
            switch daysFromNow {
            case 0: return "\(type.displayText) \u{00B7} \(duration.displayText.lowercased())"
            case 1: return "\(type.displayText) starting tomorrow \u{00B7} \(duration.displayText.lowercased())"
            default: return "\(type.displayText) starting \(dayLabel.lowercased()) \u{00B7} \(duration.displayText.lowercased())"
            }
        }
        switch daysFromNow {
        case 0: return "\(type.displayText) today"
        case 1: return "\(type.displayText) tomorrow"
        default: return "\(type.displayText) \(dayLabel.lowercased())"
        }
    }
}

// MARK: - Summary

struct UpcomingContextSummary: Equatable {
    var hasBigRideSoon = false
    var daysUntilBigRide: Int?
    var bigRideLabel: String?

    var hasBusyDaySoon = false
    var daysUntilBusyDay: Int?

    var hasTravelSoon = false
    var daysUntilTravel: Int?

    var hasLimitedTimeSoon = false
    var recoveryFocusedActive = false
    var wantsToPushHarder = false
    var upcomingHardEventCount = 0

    var events: [UpcomingContextEvent] = []

    var isEmpty: Bool { events.isEmpty }

    static let empty = UpcomingContextSummary()

    static func build(from events: [UpcomingContextEvent]) -> UpcomingContextSummary {
        let active = events.filter { !$0.isExpired && $0.daysFromNow <= 7 }
        guard !active.isEmpty else { return .empty }

        var summary = UpcomingContextSummary()
        summary.events = active

        let bigRides = active.filter { $0.type == .bigOutdoorRide || $0.type == .raceOrEvent }
        if let nearest = bigRides.min(by: { $0.daysFromNow < $1.daysFromNow }) {
            summary.hasBigRideSoon = true
            summary.daysUntilBigRide = nearest.daysFromNow
            summary.bigRideLabel = nearest.type.reasonLabel
        }

        let busyDays = active.filter { $0.type == .busyWorkday || $0.type == .familyCommitment }
        if let nearest = busyDays.min(by: { $0.daysFromNow < $1.daysFromNow }) {
            summary.hasBusyDaySoon = true
            summary.daysUntilBusyDay = nearest.daysFromNow
        }

        let travel = active.filter { $0.type == .travel }
        if let nearest = travel.min(by: { $0.daysFromNow < $1.daysFromNow }) {
            summary.hasTravelSoon = true
            summary.daysUntilTravel = nearest.daysFromNow
        }

        summary.hasLimitedTimeSoon = active.contains { $0.type == .limitedTime }
        summary.recoveryFocusedActive = active.contains { $0.type == .recoveryFocused }
        summary.wantsToPushHarder = active.contains { $0.type == .wantToPushHarder }

        summary.upcomingHardEventCount = active.filter {
            $0.type.isHighIntensity || $0.impact == .hard || $0.impact == .veryHard
        }.count

        return summary
    }
}
