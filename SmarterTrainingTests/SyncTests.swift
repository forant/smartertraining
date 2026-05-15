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

        // Clean up
        store.saveWorkouts(existingWorkouts)
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

        // Clean up
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

        // Clean up
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
