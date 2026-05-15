import Foundation

@Observable
final class BackendSyncService {

    private(set) var status: SyncStatus = .notSignedIn
    private(set) var lastSyncedAt: Date?

    private let auth: BackendAuthService
    private let store: LocalStore

    private let defaults = UserDefaults.standard
    private static let lastSyncKey = "lastSyncedAt"

    init(auth: BackendAuthService, store: LocalStore) {
        self.auth = auth
        self.store = store
        if auth.isSignedIn {
            status = .idle
        }
        if let timestamp = defaults.object(forKey: Self.lastSyncKey) as? Date {
            lastSyncedAt = timestamp
        }
    }

    func sync() async {
        guard auth.isSignedIn, let jwt = auth.jwt else {
            status = .notSignedIn
            return
        }

        status = .syncing

        let pending = store.pendingSyncRecords()

        do {
            let response = try await performSync(jwt: jwt, records: pending, since: lastSyncedAt)

            for envelope in response.records {
                store.applyServerRecord(envelope)
            }

            for record in pending {
                store.markSynced(recordType: record.recordType, recordId: record.recordId)
            }

            let now = Date()
            lastSyncedAt = now
            defaults.set(now, forKey: Self.lastSyncKey)
            status = .synced(now)

        } catch {
            let reason = error.localizedDescription
            for record in pending {
                store.markSyncFailed(recordType: record.recordType, recordId: record.recordId, reason: reason)
            }
            status = .error(reason)
        }
    }

    func updateAuthStatus() {
        if auth.isSignedIn {
            if case .notSignedIn = status { status = .idle }
        } else {
            status = .notSignedIn
        }
    }

    private func performSync(jwt: String, records: [SyncRecordEnvelope], since: Date?) async throws -> SyncResponse {
        let formatter = ISO8601DateFormatter()

        let recordDicts: [[String: Any]] = records.compactMap { envelope in
            var dict: [String: Any] = [
                "record_type": envelope.recordType,
                "record_id": envelope.recordId.uuidString,
                "updated_at": formatter.string(from: envelope.updatedAt)
            ]
            if let payload = try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any] {
                dict["payload"] = payload
            }
            return dict
        }

        var body: [String: Any] = ["records": recordDicts]
        if let since {
            body["last_synced_at"] = formatter.string(from: since)
        }

        let url = URL(string: "\(BackendAuthService.baseURL)/v1/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw SyncError.unauthorized
            }
            throw SyncError.serverError(httpResponse.statusCode)
        }

        return try parseSyncResponse(data, formatter: formatter)
    }

    private func parseSyncResponse(_ data: Data, formatter: ISO8601DateFormatter) throws -> SyncResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordsArray = json["records"] as? [[String: Any]] else {
            throw SyncError.invalidResponse
        }

        let records: [SyncRecordEnvelope] = recordsArray.compactMap { dict in
            guard let type = dict["record_type"] as? String,
                  let idString = dict["record_id"] as? String,
                  let id = UUID(uuidString: idString),
                  let updatedString = dict["updated_at"] as? String,
                  let updated = formatter.date(from: updatedString),
                  let payload = dict["payload"] else { return nil }

            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return SyncRecordEnvelope(recordType: type, recordId: id, updatedAt: updated, payload: payloadData)
        }

        return SyncResponse(records: records)
    }

    struct SyncResponse {
        var records: [SyncRecordEnvelope]
    }

    enum SyncError: Error, LocalizedError {
        case networkError
        case unauthorized
        case serverError(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .networkError: "Network error"
            case .unauthorized: "Session expired"
            case .serverError(let code): "Server error (\(code))"
            case .invalidResponse: "Invalid server response"
            }
        }
    }

    #if DEBUG
    func debugClearSyncState() {
        store.clearSyncMetadata()
        lastSyncedAt = nil
        defaults.removeObject(forKey: Self.lastSyncKey)
        status = auth.isSignedIn ? .idle : .notSignedIn
    }
    #endif
}
