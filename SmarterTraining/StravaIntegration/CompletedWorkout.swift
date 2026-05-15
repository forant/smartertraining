import Foundation

struct CompletedWorkout: Codable, Identifiable {
    let id: UUID
    var startDate: Date
    var duration: TimeInterval
    var title: String
    var samples: [TrainerMetrics]
    var status: RideStatus
    var isPostedToStrava: Bool
    var updatedAt: Date?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var healthKitWorkoutUUID: UUID?
    var healthKitSaveStatus: HealthKitSaveStatus?
    var healthKitFailureReason: String?

    // Post-workout feedback
    var workoutFeedback: WorkoutFeedback?
    var perceivedEffort: Int?
    var postWorkoutNote: String?

    // Post-workout reflection
    var reflection: PostWorkoutReflection?
    var reflectionStatus: ReflectionStatus?

    // Session stats
    var averagePower: Int?
    var maxPower: Int?
    var averageCadence: Int?
    var ergWasEnabled: Bool?
    var workoutType: WorkoutType?

    enum RideStatus: String, Codable {
        case inProgress
        case finished
    }

    enum HealthKitSaveStatus: String, Codable {
        case saved
        case failed
        case unavailable
    }

    enum ReflectionStatus: String, Codable {
        case notRequested
        case loading
        case generated
        case failed
    }

    init(
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval = 0,
        title: String,
        samples: [TrainerMetrics] = [],
        status: RideStatus = .inProgress,
        isPostedToStrava: Bool = false,
        updatedAt: Date? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        healthKitWorkoutUUID: UUID? = nil,
        healthKitSaveStatus: HealthKitSaveStatus? = nil,
        healthKitFailureReason: String? = nil,
        workoutFeedback: WorkoutFeedback? = nil,
        perceivedEffort: Int? = nil,
        postWorkoutNote: String? = nil,
        reflection: PostWorkoutReflection? = nil,
        reflectionStatus: ReflectionStatus? = nil,
        averagePower: Int? = nil,
        maxPower: Int? = nil,
        averageCadence: Int? = nil,
        ergWasEnabled: Bool? = nil,
        workoutType: WorkoutType? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.title = title
        self.samples = samples
        self.status = status
        self.isPostedToStrava = isPostedToStrava
        self.updatedAt = updatedAt
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.healthKitSaveStatus = healthKitSaveStatus
        self.healthKitFailureReason = healthKitFailureReason
        self.workoutFeedback = workoutFeedback
        self.perceivedEffort = perceivedEffort
        self.postWorkoutNote = postWorkoutNote
        self.reflection = reflection
        self.reflectionStatus = reflectionStatus
        self.averagePower = averagePower
        self.maxPower = maxPower
        self.averageCadence = averageCadence
        self.ergWasEnabled = ergWasEnabled
        self.workoutType = workoutType
    }
}

// MARK: - Post-Workout Reflection

struct PostWorkoutReflection: Codable, Equatable {
    var sessionEvaluation: String
    var whatWentWell: String?
    var watchOut: String?
    var nextTwoDays: [DayGuidance]
    var confidence: String
    var isFallback: Bool
    var generatedAt: Date

    struct DayGuidance: Codable, Equatable {
        var dayLabel: String
        var guidance: String
        var recommendedIntensity: String
    }
}

// MARK: - Session Stats

extension CompletedWorkout {
    mutating func computeStats(from samples: [TrainerMetrics], ergEnabled: Bool, workoutType: WorkoutType?) {
        let powers = samples.compactMap(\.power).filter { $0 > 0 }
        if !powers.isEmpty {
            averagePower = powers.reduce(0, +) / powers.count
            maxPower = powers.max()
        }
        let cadences = samples.compactMap(\.cadence).filter { $0 > 0 }
        if !cadences.isEmpty {
            averageCadence = Int(cadences.reduce(0, +) / Double(cadences.count))
        }
        ergWasEnabled = ergEnabled
        self.workoutType = workoutType
    }
}
