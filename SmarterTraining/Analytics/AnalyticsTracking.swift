import Foundation

protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
    func track(_ event: AnalyticsEvent, properties: [String: any Sendable])
    func trackError(category: ErrorCategory, message: String, properties: [String: any Sendable])
    func identify(userId: String)
    func reset()
    func setUserProperties(_ properties: [String: any Sendable])
    func flush()
}

extension AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {
        track(event, properties: [:])
    }
}

enum ErrorCategory: String, Sendable {
    case bluetooth
    case erg
    case hrm
    case healthkit
    case strava
    case backendSync = "backend_sync"
    case aiCoach = "ai_coach"
    case persistence
    case notification
    case subscription
}
