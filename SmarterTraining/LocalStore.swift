import Foundation

final class LocalStore {

    private let baseURL: URL
    private let ridesURL: URL
    private let workoutsURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("SmarterTraining", isDirectory: true)
        ridesURL = baseURL.appendingPathComponent("rides", isDirectory: true)
        workoutsURL = baseURL.appendingPathComponent("workouts.json")

        try? FileManager.default.createDirectory(at: ridesURL, withIntermediateDirectories: true)
    }

    // MARK: - Workout History

    func loadWorkouts() -> [WorkoutHistoryEntry] {
        guard let data = try? Data(contentsOf: workoutsURL) else { return [] }
        return (try? decoder.decode([WorkoutHistoryEntry].self, from: data)) ?? []
    }

    func saveWorkouts(_ workouts: [WorkoutHistoryEntry]) {
        guard let data = try? encoder.encode(workouts) else { return }
        try? data.write(to: workoutsURL, options: .atomic)
    }

    // MARK: - Rides

    func saveRide(_ ride: CompletedWorkout) {
        let url = rideURL(for: ride.id)
        guard let data = try? encoder.encode(ride) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadRide(id: UUID) -> CompletedWorkout? {
        let url = rideURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CompletedWorkout.self, from: data)
    }

    func loadAllRides() -> [CompletedWorkout] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: ridesURL, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CompletedWorkout.self, from: data)
        }
    }

    func inProgressRides() -> [CompletedWorkout] {
        loadAllRides().filter { $0.status == .inProgress }
    }

    func finishedRides() -> [CompletedWorkout] {
        loadAllRides()
            .filter { $0.status == .finished }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Training Intent

    private var intentURL: URL {
        baseURL.appendingPathComponent("training_intent.json")
    }

    func saveIntent(_ intent: ShortTermTrainingIntent) {
        guard let data = try? encoder.encode(intent) else { return }
        try? data.write(to: intentURL, options: .atomic)
    }

    func loadIntent() -> ShortTermTrainingIntent? {
        guard let data = try? Data(contentsOf: intentURL) else { return nil }
        return try? decoder.decode(ShortTermTrainingIntent.self, from: data)
    }

    func clearIntent() {
        try? FileManager.default.removeItem(at: intentURL)
    }

    func activeIntent(on date: Date = Date()) -> ShortTermTrainingIntent? {
        guard let intent = loadIntent() else { return nil }
        if intent.isExpired { return nil }
        if intent.activeDay(on: date) != nil { return intent }
        return nil
    }

    // MARK: - Upcoming Context

    private var upcomingContextURL: URL {
        baseURL.appendingPathComponent("upcoming_context.json")
    }

    func loadUpcomingContext() -> [UpcomingContextEvent] {
        guard let data = try? Data(contentsOf: upcomingContextURL) else { return [] }
        return (try? decoder.decode([UpcomingContextEvent].self, from: data)) ?? []
    }

    func saveUpcomingContext(_ events: [UpcomingContextEvent]) {
        let cleaned = events.filter { $0.daysFromNow >= -14 }
        guard let data = try? encoder.encode(cleaned) else { return }
        try? data.write(to: upcomingContextURL, options: .atomic)
    }

    // MARK: - Sync Support

    private var syncStatusURL: URL {
        baseURL.appendingPathComponent("sync_status.json")
    }

    func pendingSyncRecords() -> [SyncRecordEnvelope] {
        let metadata = loadSyncMetadata()
        var records: [SyncRecordEnvelope] = []

        for workout in loadWorkouts() {
            let key = syncKey(recordType: "workout", recordId: workout.id)
            let recordUpdatedAt = workout.feedbackAt ?? workout.date
            if needsSync(key: key, recordUpdatedAt: recordUpdatedAt, metadata: metadata) {
                if let data = try? encoder.encode(workout) {
                    records.append(SyncRecordEnvelope(
                        recordType: "workout",
                        recordId: workout.id,
                        updatedAt: recordUpdatedAt,
                        payload: data
                    ))
                }
            }
        }

        for ride in loadAllRides() {
            let key = syncKey(recordType: "ride", recordId: ride.id)
            let recordUpdatedAt = ride.updatedAt ?? ride.startDate
            if needsSync(key: key, recordUpdatedAt: recordUpdatedAt, metadata: metadata) {
                if let data = try? encoder.encode(ride) {
                    records.append(SyncRecordEnvelope(
                        recordType: "ride",
                        recordId: ride.id,
                        updatedAt: recordUpdatedAt,
                        payload: data
                    ))
                }
            }
        }

        for event in loadUpcomingContext() {
            let key = syncKey(recordType: "upcoming_context", recordId: event.id)
            if needsSync(key: key, recordUpdatedAt: event.updatedAt, metadata: metadata) {
                if let data = try? encoder.encode(event) {
                    records.append(SyncRecordEnvelope(
                        recordType: "upcoming_context",
                        recordId: event.id,
                        updatedAt: event.updatedAt,
                        payload: data
                    ))
                }
            }
        }

        return records
    }

    func markSynced(recordType: String, recordId: UUID, serverUpdatedAt: Date? = nil) {
        var metadata = loadSyncMetadata()
        let key = syncKey(recordType: recordType, recordId: recordId)
        let now = Date()
        metadata[key] = SyncRecordMetadata(
            recordType: recordType,
            recordId: recordId,
            status: .synced,
            lastAttemptedAt: now,
            lastSyncedAt: now,
            serverUpdatedAt: serverUpdatedAt,
            failedReason: nil,
            retryCount: 0,
            updatedAt: now
        )
        saveSyncMetadata(metadata)
    }

    func markSyncFailed(recordType: String, recordId: UUID, reason: String) {
        var metadata = loadSyncMetadata()
        let key = syncKey(recordType: recordType, recordId: recordId)
        let now = Date()
        var existing = metadata[key] ?? SyncRecordMetadata(
            recordType: recordType,
            recordId: recordId,
            status: .failed,
            retryCount: 0,
            updatedAt: now
        )
        existing.status = .failed
        existing.lastAttemptedAt = now
        existing.failedReason = reason
        existing.retryCount += 1
        existing.updatedAt = now
        metadata[key] = existing
        saveSyncMetadata(metadata)
    }

    func applyServerRecord(_ envelope: SyncRecordEnvelope) {
        switch envelope.recordType {
        case "workout":
            if let workout = try? decoder.decode(WorkoutHistoryEntry.self, from: envelope.payload) {
                var workouts = loadWorkouts()
                if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
                    workouts[index] = workout
                } else {
                    workouts.append(workout)
                }
                workouts.sort { $0.date < $1.date }
                saveWorkouts(workouts)
                markSynced(recordType: "workout", recordId: workout.id, serverUpdatedAt: envelope.updatedAt)
            }
        case "ride":
            if let ride = try? decoder.decode(CompletedWorkout.self, from: envelope.payload) {
                saveRide(ride)
                markSynced(recordType: "ride", recordId: ride.id, serverUpdatedAt: envelope.updatedAt)
            }
        case "upcoming_context":
            if let event = try? decoder.decode(UpcomingContextEvent.self, from: envelope.payload) {
                var events = loadUpcomingContext()
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    events[index] = event
                } else {
                    events.append(event)
                }
                saveUpcomingContext(events)
                markSynced(recordType: "upcoming_context", recordId: event.id, serverUpdatedAt: envelope.updatedAt)
            }
        default:
            break
        }
    }

    func clearSyncMetadata() {
        try? FileManager.default.removeItem(at: syncStatusURL)
    }

    func isSynced(recordType: String, recordId: UUID) -> Bool {
        let metadata = loadSyncMetadata()
        let key = syncKey(recordType: recordType, recordId: recordId)
        return metadata[key]?.status == .synced
    }

    func syncMetadataSummary() -> SyncMetadataSummary {
        let metadata = loadSyncMetadata()
        let values = Array(metadata.values)
        return SyncMetadataSummary(
            pendingCount: pendingSyncRecords().count,
            syncedCount: values.filter { $0.status == .synced }.count,
            failedCount: values.filter { $0.status == .failed }.count,
            lastAttempt: values.compactMap(\.lastAttemptedAt).max(),
            lastSuccess: values.compactMap(\.lastSyncedAt).max(),
            recentFailures: values.filter { $0.status == .failed }.compactMap(\.failedReason)
        )
    }

    func syncMetadata(for recordType: String, recordId: UUID) -> SyncRecordMetadata? {
        loadSyncMetadata()[syncKey(recordType: recordType, recordId: recordId)]
    }

    private func syncKey(recordType: String, recordId: UUID) -> String {
        "\(recordType):\(recordId.uuidString)"
    }

    private func needsSync(key: String, recordUpdatedAt: Date, metadata: [String: SyncRecordMetadata]) -> Bool {
        guard let meta = metadata[key] else { return true }
        switch meta.status {
        case .pendingUpload, .failed:
            return true
        case .synced:
            guard let syncedAt = meta.lastSyncedAt else { return true }
            return recordUpdatedAt > syncedAt
        }
    }

    private func loadSyncMetadata() -> [String: SyncRecordMetadata] {
        guard let data = try? Data(contentsOf: syncStatusURL) else { return [:] }

        if let metadata = try? decoder.decode([String: SyncRecordMetadata].self, from: data) {
            return metadata
        }

        // Migrate from old Set<String> format
        if let keys = try? decoder.decode(Set<String>.self, from: data) {
            let now = Date()
            var metadata: [String: SyncRecordMetadata] = [:]
            for key in keys {
                let parts = key.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      let recordId = UUID(uuidString: String(parts[1])) else { continue }
                metadata[key] = SyncRecordMetadata(
                    recordType: String(parts[0]),
                    recordId: recordId,
                    status: .synced,
                    lastSyncedAt: now,
                    retryCount: 0,
                    updatedAt: now
                )
            }
            saveSyncMetadata(metadata)
            return metadata
        }

        return [:]
    }

    private func saveSyncMetadata(_ metadata: [String: SyncRecordMetadata]) {
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: syncStatusURL, options: .atomic)
    }

    // MARK: - Private

    private func rideURL(for id: UUID) -> URL {
        ridesURL.appendingPathComponent("\(id.uuidString).json")
    }
}
