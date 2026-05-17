import Foundation
import UserNotifications

final class CoachingNotificationManager {

    static let shared = CoachingNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let day1Prefix = "coaching-day1-"
    private let day2Prefix = "coaching-day2-"

    private init() {}

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            AnalyticsService.shared.track(.notificationPermissionRequested)
            self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                AnalyticsService.shared.track(
                    granted ? .notificationPermissionGranted : .notificationPermissionDenied
                )
            }
        }
    }

    var hasPermission: Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            result = settings.authorizationStatus == .authorized
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Scheduling

    func scheduleNotifications(for intent: ShortTermTrainingIntent) {
        cancelExistingCoachingNotifications()

        guard !intent.isExpired else { return }

        AnalyticsService.shared.track(.coachingNotificationScheduled, properties: [
            "day1_intensity": intent.day1RecommendedIntensity.rawValue,
            "day2_intensity": intent.day2RecommendedIntensity.rawValue
        ])

        let day1Fire = intent.day1Date.addingTimeInterval(-2 * 3600)
        let day2Fire = intent.day2Date.addingTimeInterval(-2 * 3600)

        scheduleIfFuture(
            id: day1Prefix + intent.id.uuidString,
            title: notificationTitle(for: intent.day1RecommendedIntensity),
            body: intent.day1Rationale,
            fireDate: day1Fire
        )

        scheduleIfFuture(
            id: day2Prefix + intent.id.uuidString,
            title: notificationTitle(for: intent.day2RecommendedIntensity),
            body: intent.day2Rationale,
            fireDate: day2Fire
        )
    }

    func cancelExistingCoachingNotifications() {
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.day1Prefix) || $0.hasPrefix(self.day2Prefix) }
            if !ids.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Private

    private func scheduleIfFuture(id: String, title: String, body: String, fireDate: Date) {
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            #if DEBUG
            if let error {
                print("[Notifications] Failed to schedule \(id): \(error.localizedDescription)")
            } else {
                print("[Notifications] Scheduled \(id) for \(fireDate)")
            }
            #endif
        }
    }

    private func notificationTitle(for intensity: ShortTermTrainingIntent.RecommendedIntensity) -> String {
        switch intensity {
        case .rest:
            return "Rest day"
        case .recovery:
            return "Recovery is part of the training"
        case .endurance:
            return "Steady day ahead"
        case .quality:
            return "Ready for the next one?"
        case .flexible:
            return "Check in when you're ready"
        }
    }
}
