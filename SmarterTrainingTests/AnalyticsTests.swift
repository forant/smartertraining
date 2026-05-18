import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Mock Analytics Tracker

final class MockAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    struct TrackedEvent: Equatable {
        let name: String
        let propertyKeys: Set<String>
    }

    struct TrackedError {
        let category: ErrorCategory
        let message: String
        let propertyKeys: Set<String>
    }

    private(set) var events: [TrackedEvent] = []
    private(set) var errors: [TrackedError] = []
    private(set) var identifiedUserId: String?
    private(set) var didReset = false
    private(set) var userProperties: [String: any Sendable] = [:]
    private(set) var flushed = false

    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]) {
        events.append(TrackedEvent(
            name: event.rawValue,
            propertyKeys: Set(properties.keys)
        ))
    }

    func trackError(category: ErrorCategory, message: String, properties: [String: any Sendable]) {
        errors.append(TrackedError(
            category: category,
            message: message,
            propertyKeys: Set(properties.keys)
        ))
    }

    func identify(userId: String) {
        identifiedUserId = userId
    }

    func reset() {
        didReset = true
    }

    func setUserProperties(_ properties: [String: any Sendable]) {
        for (key, value) in properties {
            userProperties[key] = value
        }
    }

    func flush() {
        flushed = true
    }

    func eventNames() -> [String] {
        events.map(\.name)
    }

    func hasEvent(_ name: String) -> Bool {
        events.contains { $0.name == name }
    }

    func lastEvent() -> TrackedEvent? {
        events.last
    }

    func clear() {
        events.removeAll()
        errors.removeAll()
        identifiedUserId = nil
        didReset = false
        userProperties = [:]
        flushed = false
    }
}

// MARK: - AnalyticsEvent Tests

struct AnalyticsEventTests {

    @Test func allEventsHaveUniqueRawValues() {
        var seen = Set<String>()
        for event in allEvents {
            let raw = event.rawValue
            #expect(!seen.contains(raw), "Duplicate raw value: \(raw)")
            seen.insert(raw)
        }
    }

    @Test func eventRawValuesAreSnakeCase() {
        for event in allEvents {
            let raw = event.rawValue
            #expect(raw == raw.lowercased(), "\(raw) should be snake_case")
            #expect(!raw.contains(" "), "\(raw) should not contain spaces")
        }
    }

    private var allEvents: [AnalyticsEvent] {
        [
            .appOpened,
            .onboardingIntroViewed, .onboardingHowItWorksViewed,
            .onboardingStarted, .onboardingStepCompleted, .onboardingCompleted,
            .checkinStarted, .checkinCompleted,
            .recommendationGenerated,
            .aiCoachExplanationRequested, .aiCoachExplanationSucceeded, .aiCoachExplanationFailed,
            .workoutStartTapped, .workoutStarted, .workoutCompleted, .workoutAbandoned, .workoutFeedbackSubmitted,
            .workoutEditorOpened, .workoutEdited, .workoutResetToRecommendation,
            .trainerScanStarted, .trainerFound, .trainerConnectAttempted, .trainerConnected,
            .trainerConnectionFailed, .trainerDisconnected, .trainerReconnectAttempted,
            .trainerReconnected, .trainerReconnectFailed,
            .ergEnabled, .ergDisabled, .ergControlAcquired, .ergControlFailed, .ergFallbackToGuided,
            .hrmScanStarted, .hrmFound, .hrmConnectAttempted, .hrmConnected,
            .hrmConnectionFailed, .hrmDisconnected, .hrmReconnectAttempted,
            .hrmReconnected, .hrmReconnectFailed,
            .stravaConnectStarted, .stravaConnected, .stravaConnectFailed,
            .stravaUploadStarted, .stravaUploadSucceeded, .stravaUploadFailed,
            .healthkitPermissionRequested, .healthkitPermissionGranted, .healthkitPermissionDenied,
            .healthkitWorkoutSaveStarted, .healthkitWorkoutSaveSucceeded, .healthkitWorkoutSaveFailed,
            .siwaStarted, .siwaSucceeded, .siwaFailed,
            .syncStarted, .syncSucceeded, .syncFailed,
            .postWorkoutFeedbackSubmitted,
            .postWorkoutReflectionRequested, .postWorkoutReflectionSucceeded, .postWorkoutReflectionFailed,
            .shortTermIntentCreated,
            .upcomingContextAdded, .upcomingContextEdited, .upcomingContextDeleted,
            .notificationPermissionRequested, .notificationPermissionGranted, .notificationPermissionDenied,
            .coachingNotificationScheduled,
            .paywallViewed, .freeFounderSelected,
            .purchaseMonthlyTapped, .purchaseAnnualTapped,
            .purchaseSucceeded, .purchaseCancelled, .purchaseFailed,
            .restoreTapped, .restoreSucceeded, .restoreFailed,
            .entitlementResolved,
        ]
    }
}

// MARK: - AnalyticsProperties Tests

struct AnalyticsPropertiesTests {

    @Test func durationBucketUnder10m() {
        #expect(AnalyticsProperties.durationBucket(300) == "under_10m")
    }

    @Test func durationBucket10to20m() {
        #expect(AnalyticsProperties.durationBucket(900) == "10_20m")
    }

    @Test func durationBucket20to30m() {
        #expect(AnalyticsProperties.durationBucket(1500) == "20_30m")
    }

    @Test func durationBucket30to45m() {
        #expect(AnalyticsProperties.durationBucket(2400) == "30_45m")
    }

    @Test func durationBucket45to60m() {
        #expect(AnalyticsProperties.durationBucket(3000) == "45_60m")
    }

    @Test func durationBucketOver60m() {
        #expect(AnalyticsProperties.durationBucket(7200) == "over_60m")
    }

    @Test func timeBucketUnder20() {
        #expect(AnalyticsProperties.timeBucket(15) == "under_20m")
    }

    @Test func timeBucket20to30() {
        #expect(AnalyticsProperties.timeBucket(25) == "20_30m")
    }

    @Test func timeBucket45to60() {
        #expect(AnalyticsProperties.timeBucket(50) == "45_60m")
    }

    @Test func timeBucket60Plus() {
        #expect(AnalyticsProperties.timeBucket(90) == "60m_plus")
    }

    @Test func countBucketZero() {
        #expect(AnalyticsProperties.countBucket(0) == "0")
    }

    @Test func countBucketOne() {
        #expect(AnalyticsProperties.countBucket(1) == "1")
    }

    @Test func countBucket2to3() {
        #expect(AnalyticsProperties.countBucket(3) == "2_3")
    }

    @Test func countBucket4to6() {
        #expect(AnalyticsProperties.countBucket(5) == "4_6")
    }

    @Test func countBucket7Plus() {
        #expect(AnalyticsProperties.countBucket(10) == "7_plus")
    }

    @Test func effortBucketLow() {
        #expect(AnalyticsProperties.effortBucket(2) == "low")
    }

    @Test func effortBucketModerate() {
        #expect(AnalyticsProperties.effortBucket(5) == "moderate")
    }

    @Test func effortBucketHard() {
        #expect(AnalyticsProperties.effortBucket(8) == "hard")
    }

    @Test func effortBucketMax() {
        #expect(AnalyticsProperties.effortBucket(10) == "max")
    }

    @Test func sanitizeStripsEmail() {
        let input = "Error for user@example.com on login"
        let result = AnalyticsProperties.sanitizeMessage(input)
        #expect(result.contains("[email]"))
        #expect(!result.contains("user@example.com"))
    }

    @Test func sanitizeStripsUUID() {
        let input = "Failed for 550e8400-e29b-41d4-a716-446655440000"
        let result = AnalyticsProperties.sanitizeMessage(input)
        #expect(result.contains("[uuid]"))
        #expect(!result.contains("550e8400"))
    }

    @Test func sanitizeTruncatesLongMessages() {
        let longMessage = String(repeating: "a", count: 300)
        let result = AnalyticsProperties.sanitizeMessage(longMessage)
        #expect(result.count <= 200)
    }

    @Test func sanitizePreservesNormalText() {
        let input = "Connection timeout after 10 seconds"
        let result = AnalyticsProperties.sanitizeMessage(input)
        #expect(result == input)
    }
}

// MARK: - Mock Tracker Protocol Conformance Tests

struct MockTrackerTests {

    @Test func trackRecordsEvents() {
        let tracker = MockAnalyticsTracker()
        tracker.track(.appOpened, properties: ["test": true])

        #expect(tracker.events.count == 1)
        #expect(tracker.hasEvent("app_opened"))
        #expect(tracker.lastEvent()?.propertyKeys.contains("test") == true)
    }

    @Test func trackDefaultExtensionWorks() {
        let tracker = MockAnalyticsTracker()
        tracker.track(.checkinStarted)

        #expect(tracker.events.count == 1)
        #expect(tracker.hasEvent("checkin_started"))
        #expect(tracker.lastEvent()?.propertyKeys.isEmpty == true)
    }

    @Test func trackErrorRecordsErrors() {
        let tracker = MockAnalyticsTracker()
        tracker.trackError(category: .bluetooth, message: "test error", properties: ["key": "val"])

        #expect(tracker.errors.count == 1)
        #expect(tracker.errors.first?.category == .bluetooth)
        #expect(tracker.errors.first?.message == "test error")
    }

    @Test func identifyRecordsUserId() {
        let tracker = MockAnalyticsTracker()
        tracker.identify(userId: "user123")
        #expect(tracker.identifiedUserId == "user123")
    }

    @Test func resetSetsFlag() {
        let tracker = MockAnalyticsTracker()
        tracker.reset()
        #expect(tracker.didReset)
    }

    @Test func setUserPropertiesRecords() {
        let tracker = MockAnalyticsTracker()
        tracker.setUserProperties(["key": "value"])
        #expect(tracker.userProperties["key"] as? String == "value")
    }

    @Test func flushSetsFlag() {
        let tracker = MockAnalyticsTracker()
        tracker.flush()
        #expect(tracker.flushed)
    }

    @Test func clearResetsEverything() {
        let tracker = MockAnalyticsTracker()
        tracker.track(.appOpened)
        tracker.trackError(category: .erg, message: "err", properties: [:])
        tracker.identify(userId: "u")
        tracker.setUserProperties(["k": "v"])
        tracker.flush()

        tracker.clear()

        #expect(tracker.events.isEmpty)
        #expect(tracker.errors.isEmpty)
        #expect(tracker.identifiedUserId == nil)
        #expect(!tracker.didReset)
        #expect(tracker.userProperties.isEmpty)
        #expect(!tracker.flushed)
    }
}

// MARK: - ErrorCategory Tests

struct ErrorCategoryTests {

    @Test func allCategoriesHaveSnakeCaseRawValues() {
        let categories: [ErrorCategory] = [
            .bluetooth, .erg, .hrm, .healthkit, .strava,
            .backendSync, .aiCoach, .persistence, .notification, .subscription
        ]
        for cat in categories {
            #expect(cat.rawValue == cat.rawValue.lowercased())
            #expect(!cat.rawValue.contains(" "))
        }
    }
}

// MARK: - TrainingGoal Backward Compatibility Tests

struct TrainingGoalTests {

    @Test func displayTextValuesAreUnique() {
        var seen = Set<String>()
        for goal in TrainingGoal.allCases {
            #expect(!seen.contains(goal.displayText), "Duplicate displayText: \(goal.displayText)")
            seen.insert(goal.displayText)
        }
    }

    @Test func rawValuesPreservedForCodableCompat() {
        #expect(TrainingGoal.endurance.rawValue == "Improve cardio fitness")
        #expect(TrainingGoal.stronger.rawValue == "Build strength")
        #expect(TrainingGoal.consistent.rawValue == "Stay consistent")
        #expect(TrainingGoal.healthier.rawValue == "Increase energy and overall health")
        #expect(TrainingGoal.bikePerformance.rawValue == "Support performance on the bike")
    }

    @Test func decodingOldProfileGoalsStillWorks() throws {
        let json = """
        {
            "goals": ["Improve cardio fitness", "Stay consistent"],
            "equipment": []
        }
        """
        let data = Data(json.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(profile.goals.contains(.endurance))
        #expect(profile.goals.contains(.consistent))
        #expect(profile.goals.count == 2)
    }

    @Test func ftpSkipProducesNilFtp() throws {
        let json = """
        {
            "goals": ["Build strength"],
            "equipment": ["Dumbbells"]
        }
        """
        let data = Data(json.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(profile.ftp == nil)
    }
}
