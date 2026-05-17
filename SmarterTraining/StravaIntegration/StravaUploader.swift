import Foundation
import Observation

enum UploadState: Equatable {
    case idle
    case uploading
    case processing
    case success(activityId: Int64)
    case failed(String)
}

@Observable
final class StravaUploader {

    var state: UploadState = .idle

    private let auth: StravaAuth

    init(auth: StravaAuth) {
        self.auth = auth
    }

    func upload(workout: CompletedWorkout) async {
        state = .uploading
        AnalyticsService.shared.track(.stravaUploadStarted, properties: [
            "duration": AnalyticsProperties.durationBucket(workout.duration)
        ])

        do {
            let token = try await auth.validAccessToken()
            let tcxData = TCXGenerator.generate(from: workout)
            let uploadId = try await postUpload(tcxData: tcxData, title: workout.title, token: token)
            state = .processing
            let activityId = try await pollUploadStatus(uploadId: uploadId, token: token)
            state = .success(activityId: activityId)
            AnalyticsService.shared.track(.stravaUploadSucceeded)
        } catch {
            state = .failed(error.localizedDescription)
            AnalyticsService.shared.track(.stravaUploadFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.strava, message: error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }

    // MARK: - Upload

    private func postUpload(tcxData: Data, title: String, token: String) async throws -> Int64 {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: StravaConfig.uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            tcxData: tcxData,
            title: title
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        if http.statusCode == 401 {
            throw StravaError.notConnected
        }

        guard (200...299).contains(http.statusCode) || http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw UploadError.httpError(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int64 else {
            throw UploadError.invalidResponse
        }

        return id
    }

    // MARK: - Poll

    private func pollUploadStatus(uploadId: Int64, token: String, maxAttempts: Int = 15) async throws -> Int64 {
        let url = URL(string: "\(StravaConfig.uploadURL)/\(uploadId)")!

        for _ in 0..<maxAttempts {
            try await Task.sleep(for: .seconds(2))

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let errorMsg = json["error"] as? String, !errorMsg.isEmpty {
                throw UploadError.stravaError(errorMsg)
            }

            if let activityId = json["activity_id"] as? Int64 {
                return activityId
            }
        }

        throw UploadError.timeout
    }

    // MARK: - Multipart Body

    private func buildMultipartBody(boundary: String, tcxData: Data, title: String) -> Data {
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // File field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"workout.tcx\"\r\n")
        body.append("Content-Type: application/xml\r\n\r\n")
        body.append(tcxData)
        body.append("\r\n")

        appendField("data_type", value: "tcx")
        appendField("name", value: title)
        appendField("trainer", value: "1")
        appendField("sport_type", value: "VirtualRide")

        body.append("--\(boundary)--\r\n")
        return body
    }
}

private enum UploadError: LocalizedError {
    case invalidResponse
    case httpError(String)
    case stravaError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Strava."
        case .httpError(let msg): "Upload failed: \(msg)"
        case .stravaError(let msg): msg
        case .timeout: "Upload timed out. Try again?"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
