import Foundation

enum ErrorLogger {

    private static var tracker: AnalyticsTracking { AnalyticsService.shared }

    static func log(
        _ category: ErrorCategory,
        message: String,
        subsystem: String? = nil,
        duringWorkout: Bool = false,
        recoverable: Bool = true,
        fallbackUsed: Bool = false,
        extra: [String: any Sendable] = [:]
    ) {
        var props: [String: any Sendable] = extra
        if let subsystem { props["subsystem"] = subsystem }
        props["during_workout"] = duringWorkout
        props["recoverable"] = recoverable
        props["fallback_used"] = fallbackUsed
        tracker.trackError(category: category, message: message, properties: props)
        SentryService.capture(category: category, message: message, properties: props)
    }

    static func bluetooth(
        message: String,
        duringWorkout: Bool = false,
        controlPointAvailable: Bool? = nil,
        controlAcquired: Bool? = nil,
        operation: String? = nil
    ) {
        var props: [String: any Sendable] = [:]
        props["during_workout"] = duringWorkout
        if let cp = controlPointAvailable { props["control_point_available"] = cp }
        if let ca = controlAcquired { props["control_acquired"] = ca }
        if let op = operation { props["operation"] = op }
        tracker.trackError(category: .bluetooth, message: message, properties: props)
        SentryService.capture(category: .bluetooth, message: message, properties: props)
    }

    static func erg(
        message: String,
        duringWorkout: Bool = true,
        controlPointAvailable: Bool? = nil,
        controlAcquired: Bool? = nil
    ) {
        var props: [String: any Sendable] = ["during_workout": duringWorkout]
        if let cp = controlPointAvailable { props["control_point_available"] = cp }
        if let ca = controlAcquired { props["control_acquired"] = ca }
        tracker.trackError(category: .erg, message: message, properties: props)
        SentryService.capture(category: .erg, message: message, properties: props)
    }
}
