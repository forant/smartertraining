import Foundation

enum AnalyticsEvent: String, Sendable {

    // MARK: - App Lifecycle
    case appOpened = "app_opened"

    // MARK: - Onboarding
    case onboardingIntroViewed = "onboarding_intro_viewed"
    case onboardingHowItWorksViewed = "onboarding_how_it_works_viewed"
    case onboardingStarted = "onboarding_started"
    case onboardingStepCompleted = "onboarding_step_completed"
    case onboardingCompleted = "onboarding_completed"

    // MARK: - Check-In
    case checkinStarted = "checkin_started"
    case checkinCompleted = "checkin_completed"

    // MARK: - Recommendation
    case recommendationGenerated = "recommendation_generated"

    // MARK: - AI Coach
    case aiCoachExplanationRequested = "ai_coach_explanation_requested"
    case aiCoachExplanationSucceeded = "ai_coach_explanation_succeeded"
    case aiCoachExplanationFailed = "ai_coach_explanation_failed"

    // MARK: - Workout Execution
    case workoutStartTapped = "workout_start_tapped"
    case workoutStarted = "workout_started"
    case workoutCompleted = "workout_completed"
    case workoutAbandoned = "workout_abandoned"
    case workoutFeedbackSubmitted = "workout_feedback_submitted"

    // MARK: - Workout Editing
    case workoutEditorOpened = "workout_editor_opened"
    case workoutEdited = "workout_edited"
    case workoutResetToRecommendation = "workout_reset_to_recommendation"

    // MARK: - Trainer
    case trainerScanStarted = "trainer_scan_started"
    case trainerFound = "trainer_found"
    case trainerConnectAttempted = "trainer_connect_attempted"
    case trainerConnected = "trainer_connected"
    case trainerConnectionFailed = "trainer_connection_failed"
    case trainerDisconnected = "trainer_disconnected"
    case trainerReconnectAttempted = "trainer_reconnect_attempted"
    case trainerReconnected = "trainer_reconnected"
    case trainerReconnectFailed = "trainer_reconnect_failed"

    // MARK: - ERG
    case ergEnabled = "erg_enabled"
    case ergDisabled = "erg_disabled"
    case ergControlAcquired = "erg_control_acquired"
    case ergControlFailed = "erg_control_failed"
    case ergFallbackToGuided = "erg_fallback_to_guided"

    // MARK: - HRM
    case hrmScanStarted = "hrm_scan_started"
    case hrmFound = "hrm_found"
    case hrmConnectAttempted = "hrm_connect_attempted"
    case hrmConnected = "hrm_connected"
    case hrmConnectionFailed = "hrm_connection_failed"
    case hrmDisconnected = "hrm_disconnected"
    case hrmReconnectAttempted = "hrm_reconnect_attempted"
    case hrmReconnected = "hrm_reconnected"
    case hrmReconnectFailed = "hrm_reconnect_failed"

    // MARK: - Strava
    case stravaConnectStarted = "strava_connect_started"
    case stravaConnected = "strava_connected"
    case stravaConnectFailed = "strava_connect_failed"
    case stravaUploadStarted = "strava_upload_started"
    case stravaUploadSucceeded = "strava_upload_succeeded"
    case stravaUploadFailed = "strava_upload_failed"

    // MARK: - HealthKit
    case healthkitPermissionRequested = "healthkit_permission_requested"
    case healthkitPermissionGranted = "healthkit_permission_granted"
    case healthkitPermissionDenied = "healthkit_permission_denied"
    case healthkitWorkoutSaveStarted = "healthkit_workout_save_started"
    case healthkitWorkoutSaveSucceeded = "healthkit_workout_save_succeeded"
    case healthkitWorkoutSaveFailed = "healthkit_workout_save_failed"

    // MARK: - Backend Auth & Sync
    case siwaStarted = "siwa_started"
    case siwaSucceeded = "siwa_succeeded"
    case siwaFailed = "siwa_failed"
    case syncStarted = "sync_started"
    case syncSucceeded = "sync_succeeded"
    case syncFailed = "sync_failed"

    // MARK: - Post-Workout Reflection
    case postWorkoutFeedbackSubmitted = "post_workout_feedback_submitted"
    case postWorkoutReflectionRequested = "post_workout_reflection_requested"
    case postWorkoutReflectionSucceeded = "post_workout_reflection_succeeded"
    case postWorkoutReflectionFailed = "post_workout_reflection_failed"
    case shortTermIntentCreated = "short_term_intent_created"

    // MARK: - Upcoming Context
    case upcomingContextAdded = "upcoming_context_added"
    case upcomingContextEdited = "upcoming_context_edited"
    case upcomingContextDeleted = "upcoming_context_deleted"

    // MARK: - Coach Notes
    case coachNotesUpdated = "coach_notes_updated"

    // MARK: - Coach Reflection (post-workout Q&A)
    case coachReflectionShown = "coach_reflection_shown"
    case coachReflectionAnswered = "coach_reflection_answered"

    // MARK: - Progression
    case progressionTierChanged = "progression_tier_changed"

    // MARK: - Training Approach
    case trainingApproachChanged = "training_approach_changed"

    // MARK: - Notifications
    case notificationPermissionRequested = "notification_permission_requested"
    case notificationPermissionGranted = "notification_permission_granted"
    case notificationPermissionDenied = "notification_permission_denied"
    case coachingNotificationScheduled = "coaching_notification_scheduled"

    // MARK: - Subscription & Paywall
    case paywallViewed = "paywall_viewed"
    case freeFounderSelected = "free_founder_selected"
    case purchaseMonthlyTapped = "purchase_monthly_tapped"
    case purchaseAnnualTapped = "purchase_annual_tapped"
    case purchaseSucceeded = "purchase_succeeded"
    case purchaseCancelled = "purchase_cancelled"
    case purchaseFailed = "purchase_failed"
    case restoreTapped = "restore_tapped"
    case restoreSucceeded = "restore_succeeded"
    case restoreFailed = "restore_failed"
    case entitlementResolved = "entitlement_resolved"

    // MARK: - Account Deletion
    case deleteAccountTapped = "delete_account_tapped"
    case deleteAccountConfirmed = "delete_account_confirmed"
    case deleteAccountSucceeded = "delete_account_succeeded"
    case deleteAccountFailed = "delete_account_failed"
}

// MARK: - Property Helpers

enum AnalyticsProperties {

    static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<600: "under_10m"
        case ..<1200: "10_20m"
        case ..<1800: "20_30m"
        case ..<2700: "30_45m"
        case ..<3600: "45_60m"
        default: "over_60m"
        }
    }

    static func timeBucket(_ minutes: Int) -> String {
        switch minutes {
        case ..<20: "under_20m"
        case ..<30: "20_30m"
        case ..<45: "30_45m"
        case ..<60: "45_60m"
        default: "60m_plus"
        }
    }

    static func countBucket(_ count: Int) -> String {
        switch count {
        case 0: "0"
        case 1: "1"
        case 2...3: "2_3"
        case 4...6: "4_6"
        default: "7_plus"
        }
    }

    static func effortBucket(_ effort: Int) -> String {
        switch effort {
        case ..<4: "low"
        case ..<7: "moderate"
        case ..<9: "hard"
        default: "max"
        }
    }

    static func sanitizeMessage(_ message: String) -> String {
        let trimmed = String(message.prefix(200))
        return trimmed
            .replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+"#, with: "[email]", options: .regularExpression)
            .replacingOccurrences(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, with: "[uuid]", options: .regularExpression)
    }
}
