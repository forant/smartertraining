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

    enum RideStatus: String, Codable {
        case inProgress
        case finished
    }

    enum HealthKitSaveStatus: String, Codable {
        case saved
        case failed
        case unavailable
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
        healthKitFailureReason: String? = nil
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
    }
}
