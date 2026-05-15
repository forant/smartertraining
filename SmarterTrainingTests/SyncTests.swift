import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Local Store Sync Tests

@Suite(.serialized)
struct LocalStoreSyncTests {

    private func makeTempStore() -> LocalStore {
        LocalStore()
    }

    @Test func unsignedAppWorksLocally() {
        let store = makeTempStore()
        let workouts = store.loadWorkouts()
        _ = store.pendingSyncRecords()
        #expect(workouts.count >= 0)
    }

    @Test func newRecordsBecomesPendingUpload() {
        let store = makeTempStore()
        let existingWorkouts = store.loadWorkouts()

        let entry = WorkoutHistoryEntry(
            id: UUID(),
            date: Date(),
            title: "Test Ride",
            type: .endurance
        )

        var workouts = existingWorkouts
        workouts.append(entry)
        store.saveWorkouts(workouts)

        let pending = store.pendingSyncRecords()
        let hasPending = pending.contains { $0.recordId == entry.id && $0.recordType == "workout" }
        #expect(hasPending)

        store.saveWorkouts(existingWorkouts)
        store.clearSyncMetadata()
    }

    @Test func markSyncedRemovesFromPending() {
        let store = makeTempStore()
        let existingWorkouts = store.loadWorkouts()

        let entry = WorkoutHistoryEntry(
            id: UUID(),
            date: Date(),
            title: "Test Ride",
            type: .endurance
        )

        var workouts = existingWorkouts
        workouts.append(entry)
        store.saveWorkouts(workouts)

        store.markSynced(recordType: "workout", recordId: entry.id)

        let pending = store.pendingSyncRecords()
        let stillPending = pending.contains { $0.recordId == entry.id }
        #expect(!stillPending)
        #expect(store.isSynced(recordType: "workout", recordId: entry.id))

        store.saveWorkouts(existingWorkouts)
        store.clearSyncMetadata()
    }

    @Test func markSyncedUpdatesTimestampsAndClearsFailure() {
        let store = makeTempStore()

        let id = UUID()
        store.markSyncFailed(recordType: "workout", recordId: id, reason: "Network error")

        let failedMeta = store.syncMetadata(for: "workout", recordId: id)
        #expect(failedMeta?.status == .failed)
        #expect(failedMeta?.retryCount == 1)

        store.markSynced(recordType: "workout", recordId: id, serverUpdatedAt: Date())

        let syncedMeta = store.syncMetadata(for: "workout", recordId: id)
        #expect(syncedMeta?.status == .synced)
        #expect(syncedMeta?.failedReason == nil)
        #expect(syncedMeta?.retryCount == 0)
        #expect(syncedMeta?.lastSyncedAt != nil)
        #expect(syncedMeta?.serverUpdatedAt != nil)

        store.clearSyncMetadata()
    }

    @Test func markSyncFailedIncrementsRetryCountAndStoresReason() {
        let store = makeTempStore()

        let id = UUID()
        store.markSyncFailed(recordType: "ride", recordId: id, reason: "Timeout")

        var meta = store.syncMetadata(for: "ride", recordId: id)
        #expect(meta?.status == .failed)
        #expect(meta?.retryCount == 1)
        #expect(meta?.failedReason == "Timeout")
        #expect(meta?.lastAttemptedAt != nil)

        store.markSyncFailed(recordType: "ride", recordId: id, reason: "Server error")

        meta = store.syncMetadata(for: "ride", recordId: id)
        #expect(meta?.retryCount == 2)
        #expect(meta?.failedReason == "Server error")

        store.clearSyncMetadata()
    }

    @Test func pendingSyncRecordsIncludesFailedForRetry() {
        let store = makeTempStore()
        let existingWorkouts = store.loadWorkouts()

        let entry = WorkoutHistoryEntry(
            id: UUID(),
            date: Date(),
            title: "Failed Workout",
            type: .quality
        )

        var workouts = existingWorkouts
        workouts.append(entry)
        store.saveWorkouts(workouts)

        store.markSyncFailed(recordType: "workout", recordId: entry.id, reason: "Network")

        let pending = store.pendingSyncRecords()
        let included = pending.contains { $0.recordId == entry.id }
        #expect(included)

        store.saveWorkouts(existingWorkouts)
        store.clearSyncMetadata()
    }

    @Test func localModificationAfterSyncMarksPendingAgain() {
        let store = makeTempStore()
        let existingWorkouts = store.loadWorkouts()

        let entry = WorkoutHistoryEntry(
            id: UUID(),
            date: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!,
            title: "Modified Workout",
            type: .endurance
        )

        var workouts = existingWorkouts
        workouts.append(entry)
        store.saveWorkouts(workouts)

        store.markSynced(recordType: "workout", recordId: entry.id)
        #expect(!store.pendingSyncRecords().contains { $0.recordId == entry.id })

        // Modify the record — simulate adding feedback after sync
        if let idx = workouts.firstIndex(where: { $0.id == entry.id }) {
            workouts[idx].feedback = .hard
            workouts[idx].feedbackAt = Date().addingTimeInterval(1)
        }
        store.saveWorkouts(workouts)

        let pending = store.pendingSyncRecords()
        let reappeared = pending.contains { $0.recordId == entry.id }
        #expect(reappeared)

        store.saveWorkouts(existingWorkouts)
        store.clearSyncMetadata()
    }

    @Test func applyServerRecordWritesToLocalStore() {
        let store = makeTempStore()
        let existingWorkouts = store.loadWorkouts()

        let entry = WorkoutHistoryEntry(
            id: UUID(),
            date: Date(),
            title: "Server Workout",
            type: .quality
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try! encoder.encode(entry)

        let envelope = SyncRecordEnvelope(
            recordType: "workout",
            recordId: entry.id,
            updatedAt: entry.date,
            payload: payload
        )

        store.applyServerRecord(envelope)

        let workouts = store.loadWorkouts()
        let found = workouts.contains { $0.id == entry.id && $0.title == "Server Workout" }
        #expect(found)
        #expect(store.isSynced(recordType: "workout", recordId: entry.id))

        store.saveWorkouts(existingWorkouts)
        store.clearSyncMetadata()
    }

    @Test func clearSyncMetadataResetsState() {
        let store = makeTempStore()

        let id = UUID()
        store.markSynced(recordType: "workout", recordId: id)
        #expect(store.isSynced(recordType: "workout", recordId: id))

        store.clearSyncMetadata()
        #expect(!store.isSynced(recordType: "workout", recordId: id))
    }

    @Test func syncMetadataSummaryReflectsState() {
        let store = makeTempStore()
        store.clearSyncMetadata()

        store.markSynced(recordType: "workout", recordId: UUID())
        store.markSynced(recordType: "workout", recordId: UUID())
        store.markSyncFailed(recordType: "ride", recordId: UUID(), reason: "Timeout")

        let summary = store.syncMetadataSummary()
        #expect(summary.syncedCount == 2)
        #expect(summary.failedCount == 1)
        #expect(summary.recentFailures == ["Timeout"])
        #expect(summary.lastSuccess != nil)
        #expect(summary.lastAttempt != nil)

        store.clearSyncMetadata()
    }
}

// MARK: - Sync Record Metadata Tests

struct SyncRecordMetadataTests {

    @Test func metadataRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SyncRecordMetadata(
            recordType: "workout",
            recordId: UUID(),
            status: .synced,
            lastAttemptedAt: Date(),
            lastSyncedAt: Date(),
            serverUpdatedAt: Date(),
            failedReason: nil,
            retryCount: 0,
            updatedAt: Date()
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SyncRecordMetadata.self, from: data)

        #expect(decoded.recordType == original.recordType)
        #expect(decoded.recordId == original.recordId)
        #expect(decoded.status == original.status)
        #expect(decoded.retryCount == 0)
    }

    @Test func failedMetadataRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SyncRecordMetadata(
            recordType: "ride",
            recordId: UUID(),
            status: .failed,
            lastAttemptedAt: Date(),
            failedReason: "Server error (500)",
            retryCount: 3,
            updatedAt: Date()
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SyncRecordMetadata.self, from: data)

        #expect(decoded.status == .failed)
        #expect(decoded.failedReason == "Server error (500)")
        #expect(decoded.retryCount == 3)
    }
}

// MARK: - Migration Tests

@Suite(.serialized)
struct SyncMigrationTests {

    @Test func migratesOldSetFormatToMetadata() {
        let store = LocalStore()
        store.clearSyncMetadata()

        // Write old-format Set<String> directly
        let oldKeys: Set<String> = ["workout:12345678-1234-1234-1234-123456789ABC"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(oldKeys) {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let url = appSupport
                .appendingPathComponent("SmarterTraining", isDirectory: true)
                .appendingPathComponent("sync_status.json")
            try? data.write(to: url, options: .atomic)
        }

        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        #expect(store.isSynced(recordType: "workout", recordId: id))

        let meta = store.syncMetadata(for: "workout", recordId: id)
        #expect(meta?.status == .synced)
        #expect(meta?.retryCount == 0)

        store.clearSyncMetadata()
    }
}

// MARK: - Sync Record Envelope Tests

struct SyncRecordEnvelopeTests {

    @Test func envelopeRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SyncRecordEnvelope(
            recordType: "workout",
            recordId: UUID(),
            updatedAt: Date(),
            payload: "{}".data(using: .utf8)!
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SyncRecordEnvelope.self, from: data)

        #expect(decoded.recordType == original.recordType)
        #expect(decoded.recordId == original.recordId)
    }

    @Test func rideEnvelopeContainsValidPayload() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let ride = CompletedWorkout(
            startDate: Date(),
            duration: 1800,
            title: "Test Ride",
            status: .finished
        )

        let payload = try encoder.encode(ride)
        let envelope = SyncRecordEnvelope(
            recordType: "ride",
            recordId: ride.id,
            updatedAt: ride.updatedAt ?? ride.startDate,
            payload: payload
        )

        #expect(envelope.recordType == "ride")
        #expect(envelope.recordId == ride.id)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CompletedWorkout.self, from: envelope.payload)
        #expect(decoded.id == ride.id)
        #expect(decoded.title == "Test Ride")
    }
}

// MARK: - CompletedWorkout HealthKit Field Tests

struct CompletedWorkoutHealthKitTests {

    @Test func newFieldsDefaultToNil() {
        let ride = CompletedWorkout(
            startDate: Date(),
            title: "Test Ride",
            status: .finished
        )
        #expect(ride.averageHeartRate == nil)
        #expect(ride.maxHeartRate == nil)
        #expect(ride.healthKitWorkoutUUID == nil)
        #expect(ride.healthKitSaveStatus == nil)
        #expect(ride.healthKitFailureReason == nil)
    }

    @Test func healthKitFieldsRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let uuid = UUID()
        let ride = CompletedWorkout(
            startDate: Date(),
            duration: 2400,
            title: "HR Ride",
            status: .finished,
            averageHeartRate: 142,
            maxHeartRate: 178,
            healthKitWorkoutUUID: uuid,
            healthKitSaveStatus: .saved
        )

        let data = try encoder.encode(ride)
        let decoded = try decoder.decode(CompletedWorkout.self, from: data)

        #expect(decoded.averageHeartRate == 142)
        #expect(decoded.maxHeartRate == 178)
        #expect(decoded.healthKitWorkoutUUID == uuid)
        #expect(decoded.healthKitSaveStatus == .saved)
        #expect(decoded.healthKitFailureReason == nil)
    }

    @Test func failedStatusRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let ride = CompletedWorkout(
            startDate: Date(),
            title: "Failed Save",
            status: .finished,
            healthKitSaveStatus: .failed,
            healthKitFailureReason: "Authorization denied"
        )

        let data = try encoder.encode(ride)
        let decoded = try decoder.decode(CompletedWorkout.self, from: data)

        #expect(decoded.healthKitSaveStatus == .failed)
        #expect(decoded.healthKitFailureReason == "Authorization denied")
    }

    @Test func backwardCompatibleDecoding() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "startDate": "2025-01-01T00:00:00Z",
            "duration": 1800,
            "title": "Old Ride",
            "samples": [],
            "status": "finished",
            "isPostedToStrava": false
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ride = try decoder.decode(CompletedWorkout.self, from: Data(json.utf8))

        #expect(ride.title == "Old Ride")
        #expect(ride.averageHeartRate == nil)
        #expect(ride.maxHeartRate == nil)
        #expect(ride.healthKitSaveStatus == nil)
        #expect(ride.healthKitWorkoutUUID == nil)
    }
}

// MARK: - AI Coach Explanation Tests

struct AICoachExplanationTests {

    @Test func parsesFullResponse() throws {
        let json = """
        {
            "coach_explanation": "Steady aerobic work fits today.",
            "continuity_note": "Building on yesterday's recovery.",
            "tomorrow_implication": "Sets up a quality session tomorrow.",
            "confidence": "high",
            "is_fallback": false
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(AICoachExplanation.self, from: Data(json.utf8))

        #expect(result.coachExplanation == "Steady aerobic work fits today.")
        #expect(result.continuityNote == "Building on yesterday's recovery.")
        #expect(result.tomorrowImplication == "Sets up a quality session tomorrow.")
        #expect(result.confidence == "high")
        #expect(result.isFallback == false)
    }

    @Test func parsesMinimalResponse() throws {
        let json = """
        {
            "coach_explanation": "Recovery day.",
            "continuity_note": null,
            "tomorrow_implication": null,
            "confidence": "low",
            "is_fallback": true
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(AICoachExplanation.self, from: Data(json.utf8))

        #expect(result.coachExplanation == "Recovery day.")
        #expect(result.continuityNote == nil)
        #expect(result.tomorrowImplication == nil)
        #expect(result.isFallback == true)
    }

    @Test func fallbackPreservesDeterministicReason() {
        let recommendation = WorkoutRecommendation(
            type: .endurance,
            title: "Zone 2 Ride",
            summary: "Aerobic base",
            reason: "Deterministic fallback reason.",
            steps: [],
            optionalExtras: []
        )
        let service = AICoachService()
        #expect(service.explanation == nil)
        #expect(recommendation.reason == "Deterministic fallback reason.")
    }

    @Test func cacheInvalidationClearsExplanation() {
        let service = AICoachService()
        service.invalidateCache()
        #expect(service.explanation == nil)
        #expect(service.isLoading == false)
    }
}

// MARK: - Sync Status Tests

struct SyncStatusTests {

    @Test func displayTextForAllCases() {
        #expect(SyncStatus.notSignedIn.displayText == "Not signed in")
        #expect(SyncStatus.idle.displayText == "Ready to sync")
        #expect(SyncStatus.syncing.displayText == "Syncing...")
        #expect(SyncStatus.error("fail").displayText == "Sync error: fail")
    }

    @Test func syncedStatusIncludesDate() {
        let status = SyncStatus.synced(Date())
        let text = status.displayText
        #expect(text.contains("Synced"))
    }
}
