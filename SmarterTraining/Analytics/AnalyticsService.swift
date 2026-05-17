import Foundation
import Mixpanel

enum AnalyticsConfig {
    static let mixpanelToken = "4f618858e030fc5e3128c1bee536c8e1"

    static var isConfigured: Bool {
        mixpanelToken != "YOUR_MIXPANEL_TOKEN" && !mixpanelToken.isEmpty
    }

    static var environment: String {
        #if DEBUG
        return "debug"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return "production"
        #endif
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}

final class AnalyticsService: AnalyticsTracking, @unchecked Sendable {

    static let shared = AnalyticsService()

    private let enabled: Bool

    private init() {
        if AnalyticsConfig.isConfigured {
            Mixpanel.initialize(token: AnalyticsConfig.mixpanelToken, trackAutomaticEvents: false)
            enabled = true
            Mixpanel.mainInstance().registerSuperProperties([
                "app_version": AnalyticsConfig.appVersion,
                "build_number": AnalyticsConfig.buildNumber,
                "environment": AnalyticsConfig.environment,
            ])
        } else {
            enabled = false
            #if DEBUG
            print("[Analytics] No Mixpanel token configured, running in log-only mode")
            #endif
        }
    }

    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]) {
        let mixpanelProps = properties.asMixpanelProperties()

        #if DEBUG
        let propsDesc = properties.isEmpty ? "" : " \(properties)"
        print("[Analytics] \(event.rawValue)\(propsDesc)")
        #endif

        guard enabled else { return }
        Mixpanel.mainInstance().track(event: event.rawValue, properties: mixpanelProps)
    }

    func trackError(category: ErrorCategory, message: String, properties: [String: any Sendable]) {
        var props: [String: any Sendable] = properties
        props["error_category"] = category.rawValue
        props["error_message"] = AnalyticsProperties.sanitizeMessage(message)

        let mixpanelProps = props.asMixpanelProperties()

        #if DEBUG
        print("[Analytics] error: \(category.rawValue) — \(AnalyticsProperties.sanitizeMessage(message))")
        #endif

        guard enabled else { return }
        Mixpanel.mainInstance().track(event: "error_logged", properties: mixpanelProps)
    }

    func identify(userId: String) {
        #if DEBUG
        print("[Analytics] identify: \(userId.prefix(8))...")
        #endif
        guard enabled else { return }
        Mixpanel.mainInstance().identify(distinctId: userId)
    }

    func reset() {
        #if DEBUG
        print("[Analytics] reset identity")
        #endif
        guard enabled else { return }
        Mixpanel.mainInstance().reset()
    }

    func setUserProperties(_ properties: [String: any Sendable]) {
        #if DEBUG
        print("[Analytics] user properties: \(properties)")
        #endif
        guard enabled else { return }
        Mixpanel.mainInstance().people.set(properties: properties.asMixpanelProperties())
    }

    func flush() {
        guard enabled else { return }
        Mixpanel.mainInstance().flush()
    }
}

// MARK: - Mixpanel Bridging

private extension Dictionary where Key == String, Value == any Sendable {
    func asMixpanelProperties() -> [String: MixpanelType] {
        var result: [String: MixpanelType] = [:]
        for (key, value) in self {
            if let s = value as? String { result[key] = s }
            else if let b = value as? Bool { result[key] = b }
            else if let i = value as? Int { result[key] = i }
            else if let d = value as? Double { result[key] = d }
            else { result[key] = String(describing: value) }
        }
        return result
    }
}
