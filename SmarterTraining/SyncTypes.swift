import Foundation

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

struct SyncRecordEnvelope: Codable {
    var recordType: String
    var recordId: UUID
    var updatedAt: Date
    var payload: Data
}
