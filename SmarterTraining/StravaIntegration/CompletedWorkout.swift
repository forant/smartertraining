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

    enum RideStatus: String, Codable {
        case inProgress
        case finished
    }

    init(
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval = 0,
        title: String,
        samples: [TrainerMetrics] = [],
        status: RideStatus = .inProgress,
        isPostedToStrava: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.title = title
        self.samples = samples
        self.status = status
        self.isPostedToStrava = isPostedToStrava
        self.updatedAt = updatedAt
    }
}
