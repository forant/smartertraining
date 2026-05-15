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

    // MARK: - Sync Support

    private var syncStatusURL: URL {
        baseURL.appendingPathComponent("sync_status.json")
    }

    func pendingSyncRecords() -> [SyncRecordEnvelope] {
        let synced = loadSyncedKeys()
        var records: [SyncRecordEnvelope] = []

        for workout in loadWorkouts() {
            let key = "workout:\(workout.id.uuidString)"
            if !synced.contains(key) {
                if let data = try? encoder.encode(workout) {
                    records.append(SyncRecordEnvelope(
                        recordType: "workout",
                        recordId: workout.id,
                        updatedAt: workout.feedbackAt ?? workout.date,
                        payload: data
                    ))
                }
            }
        }

        for ride in loadAllRides() {
            let key = "ride:\(ride.id.uuidString)"
            if !synced.contains(key) {
                if let data = try? encoder.encode(ride) {
                    records.append(SyncRecordEnvelope(
                        recordType: "ride",
                        recordId: ride.id,
                        updatedAt: ride.updatedAt ?? ride.startDate,
                        payload: data
                    ))
                }
            }
        }

        return records
    }

    func markSynced(recordType: String, recordId: UUID) {
        var synced = loadSyncedKeys()
        synced.insert("\(recordType):\(recordId.uuidString)")
        saveSyncedKeys(synced)
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
                markSynced(recordType: "workout", recordId: workout.id)
            }
        case "ride":
            if let ride = try? decoder.decode(CompletedWorkout.self, from: envelope.payload) {
                saveRide(ride)
                markSynced(recordType: "ride", recordId: ride.id)
            }
        default:
            break
        }
    }

    func clearSyncMetadata() {
        try? FileManager.default.removeItem(at: syncStatusURL)
    }

    func isSynced(recordType: String, recordId: UUID) -> Bool {
        loadSyncedKeys().contains("\(recordType):\(recordId.uuidString)")
    }

    private func loadSyncedKeys() -> Set<String> {
        guard let data = try? Data(contentsOf: syncStatusURL),
              let keys = try? decoder.decode(Set<String>.self, from: data) else { return [] }
        return keys
    }

    private func saveSyncedKeys(_ keys: Set<String>) {
        guard let data = try? encoder.encode(keys) else { return }
        try? data.write(to: syncStatusURL, options: .atomic)
    }

    // MARK: - Private

    private func rideURL(for id: UUID) -> URL {
        ridesURL.appendingPathComponent("\(id.uuidString).json")
    }
}
