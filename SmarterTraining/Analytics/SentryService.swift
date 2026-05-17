import Foundation
import Sentry

enum SentryService {

    static func start() {
        SentrySDK.start { options in
            options.dsn = "https://71614ddaa655bf8222ac8adf7650d344@o4511407386263552.ingest.us.sentry.io/4511407390523392"
            options.environment = AnalyticsConfig.environment
            options.releaseName = "\(Bundle.main.bundleIdentifier ?? "com.smartertraining")@\(AnalyticsConfig.appVersion)+\(AnalyticsConfig.buildNumber)"
            options.enableAutoSessionTracking = true
            options.enableCaptureFailedRequests = true
            options.attachScreenshot = true
            options.enableMetricKit = true
            #if DEBUG
            options.debug = true
            options.tracesSampleRate = 1.0
            #else
            options.tracesSampleRate = 0.2
            #endif
        }
    }

    static func setUser(id: String) {
        let user = User(userId: id)
        SentrySDK.setUser(user)
    }

    static func clearUser() {
        SentrySDK.setUser(nil)
    }

    static func capture(
        category: ErrorCategory,
        message: String,
        properties: [String: any Sendable]
    ) {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: message)
        event.tags = [
            "error_category": category.rawValue,
        ]

        if let subsystem = properties["subsystem"] as? String {
            event.tags?["subsystem"] = subsystem
        }
        if let duringWorkout = properties["during_workout"] as? Bool, duringWorkout {
            event.tags?["during_workout"] = "true"
        }
        if let recoverable = properties["recoverable"] as? Bool {
            event.tags?["recoverable"] = String(recoverable)
        }

        var extras: [String: Any] = [:]
        for (key, value) in properties {
            extras[key] = value
        }
        event.extra = extras

        SentrySDK.capture(event: event)
    }

    static func addBreadcrumb(category: String, message: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}
