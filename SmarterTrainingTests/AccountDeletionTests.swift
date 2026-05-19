import Foundation
import Testing
@testable import SmarterTraining

@Suite("Account Deletion")
struct AccountDeletionTests {

    @Test func deleteAllLocalDataClearsOnboarding() {
        let state = AppState()
        state.completeOnboarding(profile: UserProfile(
            name: "Test",
            currentState: .consistent,
            goals: [.endurance],
            typicalAvailability: .medium,
            trainingFrequency: .moderate,
            equipment: [.bikeTrainer],
            ftp: 250
        ))
        #expect(state.hasCompletedOnboarding)

        state.deleteAllLocalData()

        #expect(!state.hasCompletedOnboarding)
        #expect(state.userProfile.name == nil)
    }

    @Test func deleteAllLocalDataClearsCheckIn() {
        let state = AppState()
        state.submit(checkIn: CheckIn(
            overallFeel: "Good",
            legs: "Normal",
            motivation: "High",
            timeAvailable: 30,
            contextFlags: [],
            notes: nil
        ))
        #expect(state.hasCheckedInToday)

        state.deleteAllLocalData()

        #expect(!state.hasCheckedInToday)
        #expect(state.latestCheckIn == nil)
        #expect(state.todayFeedback == nil)
    }

    @Test func deleteAllLocalDataClearsHistory() {
        let state = AppState()
        state.submit(checkIn: CheckIn(
            overallFeel: "Good",
            legs: "Normal",
            motivation: "High",
            timeAvailable: 30,
            contextFlags: [],
            notes: nil
        ))
        #expect(!state.recentHistory.isEmpty)

        state.deleteAllLocalData()

        #expect(state.recentHistory.isEmpty)
    }

    @Test func deleteAllLocalDataResetsRecommendation() {
        let state = AppState()
        state.submit(checkIn: CheckIn(
            overallFeel: "Bad",
            legs: "Dead",
            motivation: "Low",
            timeAvailable: 20,
            contextFlags: [],
            notes: nil
        ))
        #expect(state.currentRecommendation.type == .recovery)

        state.deleteAllLocalData()

        #expect(state.currentRecommendation.title == WorkoutRecommendation.preview.title)
    }

    @Test func deleteAllLocalDataClearsUpcomingContext() {
        let state = AppState()
        let event = UpcomingContextEvent(
            date: Date(),
            type: .travel,
            impact: .moderate,
            duration: .threeToFiveDays,
            note: nil
        )
        state.addUpcomingContext(event)
        #expect(!state.upcomingContextEvents.isEmpty)

        state.deleteAllLocalData()

        #expect(state.upcomingContextEvents.isEmpty)
    }

    @Test func localStoreDeleteAllDataClearsFiles() {
        let store = LocalStore()

        let ride = CompletedWorkout(
            startDate: Date(),
            title: "Test Ride",
            status: .finished
        )
        store.saveRide(ride)
        #expect(store.loadRide(id: ride.id) != nil)

        store.deleteAllData()

        #expect(store.loadRide(id: ride.id) == nil)
        #expect(store.loadWorkouts().isEmpty)
        #expect(store.loadUpcomingContext().isEmpty)
    }

    @Test func subscriptionClearLocalEntitlement() {
        let service = SubscriptionService()
        #if DEBUG
        service.debugSimulateFounderClaimed()
        #expect(service.entitlement == .freeFounder)
        #endif

        service.clearLocalEntitlement()

        #expect(service.entitlement == .none)
    }

    @Test func analyticsEventsHaveUniqueRawValues() {
        let deletionEvents: [AnalyticsEvent] = [
            .deleteAccountTapped,
            .deleteAccountConfirmed,
            .deleteAccountSucceeded,
            .deleteAccountFailed
        ]
        let rawValues = Set(deletionEvents.map(\.rawValue))
        #expect(rawValues.count == deletionEvents.count)
    }
}
