import Foundation

struct TrainingMemorySummary {
    var completedWorkoutCount7d: Int = 0
    var completedWorkoutCount14d: Int = 0
    var hardDayCount7d: Int = 0
    var recoveryDayCount7d: Int = 0
    var daysSinceLastWorkout: Int?
    var lastWorkoutFeedback: WorkoutFeedback?
    var hadTooMuchFeedback7d: Bool = false
    var recentActivities: [RecentActivity] = []
    var recentLifeStressors: [String] = []
    var recentIntensityLoadEstimate: Double = 0
    var lastQualitySubtype: QualitySubtype?
    var recentQualitySubtypes7d: [QualitySubtype] = []

    static let empty = TrainingMemorySummary()

    var isReturningAfterBreak: Bool {
        guard let days = daysSinceLastWorkout else { return false }
        return days >= 5
    }

    var hasHighRecentLoad: Bool {
        hardDayCount7d >= 3
    }

    var recentLifeStressLevel: Int {
        let high: Set<String> = ["Poor sleep", "Getting sick", "High work stress", "Family exhaustion", "Mentally drained"]
        return min(recentLifeStressors.filter { high.contains($0) }.count, 3)
    }
}

enum TrainingMemoryBuilder {

    static func build(
        history: [WorkoutHistoryEntry],
        rides: [CompletedWorkout] = [],
        now: Date = Date()
    ) -> TrainingMemorySummary {
        let cal = Calendar.current
        let start7d = cal.startOfDay(for: cal.date(byAdding: .day, value: -7, to: now)!)
        let start14d = cal.startOfDay(for: cal.date(byAdding: .day, value: -14, to: now)!)
        let start3d = cal.startOfDay(for: cal.date(byAdding: .day, value: -3, to: now)!)

        let in7d = history.filter { $0.date >= start7d }
        let in14d = history.filter { $0.date >= start14d }
        let in3d = history.filter { $0.date >= start3d }

        let hardDays = in7d.filter {
            $0.type == .quality || $0.feedback == .hard || $0.feedback == .tooMuch
        }.count

        let recoveryDays = in7d.filter { $0.type == .recovery }.count

        let sorted = history.sorted { $0.date < $1.date }
        let lastDate = sorted.last?.date
        let daysSince = lastDate.map {
            max(0, cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: now)).day ?? 0)
        }

        let lastFeedback = sorted.last?.feedback
        let hadTooMuch = in7d.contains { $0.feedback == .tooMuch }

        let activities = in3d.compactMap(\.checkIn).flatMap(\.recentActivities)
        let stressors = Array(Set(in3d.compactMap(\.checkIn).flatMap(\.contextFlags)))

        var load: Double = 0
        for entry in in7d {
            switch entry.type {
            case .quality: load += 3
            case .endurance: load += 2
            case .recovery: load += 1
            }
        }

        let lastQualitySubtype = sorted.last(where: { $0.type == .quality })?.qualitySubtype
        let recentQualitySubtypes = in7d
            .filter { $0.type == .quality }
            .compactMap(\.qualitySubtype)

        return TrainingMemorySummary(
            completedWorkoutCount7d: in7d.count,
            completedWorkoutCount14d: in14d.count,
            hardDayCount7d: hardDays,
            recoveryDayCount7d: recoveryDays,
            daysSinceLastWorkout: daysSince,
            lastWorkoutFeedback: lastFeedback,
            hadTooMuchFeedback7d: hadTooMuch,
            recentActivities: activities,
            recentLifeStressors: stressors,
            recentIntensityLoadEstimate: load,
            lastQualitySubtype: lastQualitySubtype,
            recentQualitySubtypes7d: recentQualitySubtypes
        )
    }
}
