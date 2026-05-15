import Foundation

struct ShortTermTrainingIntent: Codable, Identifiable, Equatable {
    let id: UUID
    var generatedAt: Date
    var sourceWorkoutId: UUID
    var expiresAt: Date

    var day1Date: Date
    var day1RecommendedIntensity: RecommendedIntensity
    var day1Rationale: String

    var day2Date: Date
    var day2RecommendedIntensity: RecommendedIntensity
    var day2Rationale: String

    var qualitySubtype: QualitySubtype?

    enum RecommendedIntensity: String, Codable, Equatable {
        case rest
        case recovery
        case endurance
        case quality
        case flexible
    }

    enum QualitySubtype: String, Codable, Equatable {
        case vo2
        case threshold
        case muscularEndurance
        case tempo
        case overUnders
        case unspecified
    }

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        sourceWorkoutId: UUID,
        expiresAt: Date,
        day1Date: Date,
        day1RecommendedIntensity: RecommendedIntensity,
        day1Rationale: String,
        day2Date: Date,
        day2RecommendedIntensity: RecommendedIntensity,
        day2Rationale: String,
        qualitySubtype: QualitySubtype? = nil
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.sourceWorkoutId = sourceWorkoutId
        self.expiresAt = expiresAt
        self.day1Date = day1Date
        self.day1RecommendedIntensity = day1RecommendedIntensity
        self.day1Rationale = day1Rationale
        self.day2Date = day2Date
        self.day2RecommendedIntensity = day2RecommendedIntensity
        self.day2Rationale = day2Rationale
        self.qualitySubtype = qualitySubtype
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    func activeDay(on date: Date = Date()) -> ActiveDay? {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: day1Date) { return .day1 }
        if cal.isDate(date, inSameDayAs: day2Date) { return .day2 }
        return nil
    }

    func recommendedIntensity(on date: Date = Date()) -> RecommendedIntensity? {
        switch activeDay(on: date) {
        case .day1: return day1RecommendedIntensity
        case .day2: return day2RecommendedIntensity
        case nil: return nil
        }
    }

    func rationale(on date: Date = Date()) -> String? {
        switch activeDay(on: date) {
        case .day1: return day1Rationale
        case .day2: return day2Rationale
        case nil: return nil
        }
    }

    enum ActiveDay {
        case day1, day2
    }
}

// MARK: - Intent Builder

enum TrainingIntentBuilder {

    static func build(
        from reflection: PostWorkoutReflection,
        sourceWorkoutId: UUID,
        workoutCompletedAt: Date,
        workoutType: WorkoutType?
    ) -> ShortTermTrainingIntent {
        let cal = Calendar.current
        let day1Date = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: workoutCompletedAt)!)
        let day2Date = cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: workoutCompletedAt)!)
        let expiresAt = cal.startOfDay(for: cal.date(byAdding: .day, value: 3, to: workoutCompletedAt)!)

        let day1 = reflection.nextTwoDays.first
        let day2 = reflection.nextTwoDays.count > 1 ? reflection.nextTwoDays[1] : nil

        let day1Intensity = sanitizeIntensity(
            parseIntensity(day1?.recommendedIntensity),
            forDay: .day1,
            workoutType: workoutType
        )
        let day2Intensity = sanitizeIntensity(
            parseIntensity(day2?.recommendedIntensity),
            forDay: .day2,
            workoutType: workoutType
        )

        return ShortTermTrainingIntent(
            sourceWorkoutId: sourceWorkoutId,
            expiresAt: expiresAt,
            day1Date: day1Date,
            day1RecommendedIntensity: day1Intensity,
            day1Rationale: day1?.guidance ?? "Take it easy after yesterday's session.",
            day2Date: day2Date,
            day2RecommendedIntensity: day2Intensity,
            day2Rationale: day2?.guidance ?? "Adjust based on how you feel.",
            qualitySubtype: nil
        )
    }

    static func buildFromFeedback(
        sourceWorkoutId: UUID,
        workoutCompletedAt: Date,
        workoutType: WorkoutType?,
        feedback: WorkoutFeedback?,
        perceivedEffort: Int?
    ) -> ShortTermTrainingIntent {
        let cal = Calendar.current
        let day1Date = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: workoutCompletedAt)!)
        let day2Date = cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: workoutCompletedAt)!)
        let expiresAt = cal.startOfDay(for: cal.date(byAdding: .day, value: 3, to: workoutCompletedAt)!)

        let isHard = feedback == .hard || feedback == .tooMuch || (perceivedEffort ?? 0) >= 8
        let isQuality = workoutType == .quality

        let day1Intensity: ShortTermTrainingIntent.RecommendedIntensity
        let day1Rationale: String
        let day2Intensity: ShortTermTrainingIntent.RecommendedIntensity
        let day2Rationale: String

        if isHard || isQuality {
            day1Intensity = .recovery
            day1Rationale = "Yesterday's session was enough stress. Keep today easy or rest."
            day2Intensity = .flexible
            day2Rationale = "If your legs feel good, today can be your next quality opportunity."
        } else {
            day1Intensity = .endurance
            day1Rationale = "You have room for another session if you want it."
            day2Intensity = .flexible
            day2Rationale = "Adjust based on how you feel."
        }

        return ShortTermTrainingIntent(
            sourceWorkoutId: sourceWorkoutId,
            expiresAt: expiresAt,
            day1Date: day1Date,
            day1RecommendedIntensity: day1Intensity,
            day1Rationale: day1Rationale,
            day2Date: day2Date,
            day2RecommendedIntensity: day2Intensity,
            day2Rationale: day2Rationale
        )
    }

    // MARK: - Sanitization

    static func sanitizeIntensity(
        _ intensity: ShortTermTrainingIntent.RecommendedIntensity,
        forDay day: ShortTermTrainingIntent.ActiveDay,
        workoutType: WorkoutType?
    ) -> ShortTermTrainingIntent.RecommendedIntensity {
        if day == .day1 && workoutType == .quality && intensity == .quality {
            return .endurance
        }
        if day == .day1 && intensity == .quality {
            return .endurance
        }
        return intensity
    }

    private static func parseIntensity(_ raw: String?) -> ShortTermTrainingIntent.RecommendedIntensity {
        guard let raw else { return .flexible }
        return ShortTermTrainingIntent.RecommendedIntensity(rawValue: raw) ?? .flexible
    }
}
