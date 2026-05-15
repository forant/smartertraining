import Foundation

struct CadenceGuidance {

    var minimumCadence: Double = 75.0
    var warningDelay: TimeInterval = 10.0

    private var lowCadenceSince: Date?

    enum Status: Equatable {
        case ok
        case low(current: Int)
        case noData
    }

    mutating func update(cadence: Double?, stepRole: WorkoutStepRole, stepElapsed: TimeInterval) -> Status {
        guard stepRole == .primary else {
            lowCadenceSince = nil
            return .ok
        }

        guard let cadence, cadence > 0 else {
            lowCadenceSince = nil
            return .noData
        }

        guard stepElapsed > warningDelay else {
            lowCadenceSince = nil
            return .ok
        }

        if cadence < minimumCadence {
            let now = Date()
            if lowCadenceSince == nil {
                lowCadenceSince = now
            }
            if let since = lowCadenceSince, now.timeIntervalSince(since) >= 3.0 {
                return .low(current: Int(cadence))
            }
            return .ok
        } else {
            lowCadenceSince = nil
            return .ok
        }
    }

    mutating func reset() {
        lowCadenceSince = nil
    }
}
