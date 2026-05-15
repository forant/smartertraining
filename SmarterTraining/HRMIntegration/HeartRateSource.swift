import Foundation

enum HeartRateSource: String, Codable {
    case trainer
    case hrm
    case healthKit
    case none
}

struct ResolvedHeartRate: Equatable {
    var bpm: Int?
    var source: HeartRateSource

    static let unavailable = ResolvedHeartRate(bpm: nil, source: .none)
}

enum HeartRateResolver {
    static func resolve(
        trainerHR: Int?,
        hrmHR: Int?,
        healthKitHR: Int?
    ) -> ResolvedHeartRate {
        if let hr = trainerHR, hr > 0 {
            return ResolvedHeartRate(bpm: hr, source: .trainer)
        }
        if let hr = hrmHR, hr > 0 {
            return ResolvedHeartRate(bpm: hr, source: .hrm)
        }
        if let hr = healthKitHR, hr > 0 {
            return ResolvedHeartRate(bpm: hr, source: .healthKit)
        }
        return .unavailable
    }
}
