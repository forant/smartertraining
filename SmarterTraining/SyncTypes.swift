import Foundation

// MARK: - Service-Level Sync Status

enum SyncStatus: Equatable {
    case notSignedIn
    case idle
    case syncing
    case synced(Date)
    case error(String)

    var displayText: String {
        switch self {
        case .notSignedIn: "Not signed in"
        case .idle: "Ready to sync"
        case .syncing: "Syncing..."
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .error(let msg): "Sync error: \(msg)"
        }
    }
}

// MARK: - Sync Envelope

struct SyncRecordEnvelope: Codable {
    var recordType: String
    var recordId: UUID
    var updatedAt: Date
    var payload: Data
}

// MARK: - Per-Record Sync Metadata

enum RecordSyncStatus: String, Codable {
    case pendingUpload
    case synced
    case failed
}

struct SyncRecordMetadata: Codable {
    var recordType: String
    var recordId: UUID
    var status: RecordSyncStatus
    var lastAttemptedAt: Date?
    var lastSyncedAt: Date?
    var serverUpdatedAt: Date?
    var failedReason: String?
    var retryCount: Int
    var updatedAt: Date
}

struct SyncMetadataSummary {
    var pendingCount: Int
    var syncedCount: Int
    var failedCount: Int
    var lastAttempt: Date?
    var lastSuccess: Date?
    var recentFailures: [String]
}
