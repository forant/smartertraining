import Foundation

struct CompletedWorkout {
    var startDate: Date
    var duration: TimeInterval
    var title: String
    var samples: [TrainerMetrics]
    var isPostedToStrava: Bool = false
}
