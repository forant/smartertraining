import Foundation
import Observation
import UIKit

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

    @MainActor
    func upload(workout: CompletedWorkout) async {
        state = .uploading
        AnalyticsService.shared.track(.stravaUploadStarted, properties: [
            "duration": AnalyticsProperties.durationBucket(workout.duration)
        ])

        do {
            let token = try await auth.validAccessToken()
            let tcxData = TCXGenerator.generate(from: workout)
            let description = buildDescription(for: workout)
            let uploadId = try await postUpload(tcxData: tcxData, title: workout.title, description: description, token: token)
            state = .processing
            let activityId = try await pollUploadStatus(uploadId: uploadId, token: token)
            state = .success(activityId: activityId)
            AnalyticsService.shared.track(.stravaUploadSucceeded)

            if let cardImage = StravaCardRenderer.render(workout: workout) {
                await uploadPhoto(image: cardImage, activityId: activityId, token: token)
            }
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

    private func postUpload(tcxData: Data, title: String, description: String, token: String) async throws -> Int64 {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: StravaConfig.uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            tcxData: tcxData,
            title: title,
            description: description
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

    // MARK: - Photo Upload

    private func uploadPhoto(image: UIImage, activityId: Int64, token: String) async {
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else { return }

        let boundary = UUID().uuidString
        let url = URL(string: "https://www.strava.com/api/v3/activities/\(activityId)/photos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"workout_card.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                AnalyticsService.shared.track(.stravaUploadSucceeded, properties: ["photo": true])
            }
        } catch {
            // Photo upload is best-effort — don't affect the activity upload state
        }
    }

    // MARK: - Multipart Body

    private func buildMultipartBody(boundary: String, tcxData: Data, title: String, description: String) -> Data {
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
        appendField("description", value: description)
        appendField("trainer", value: "1")
        appendField("sport_type", value: "VirtualRide")

        body.append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Description

    private static let attribution = "Finished another workout designed by SmarterTraining"

    private func buildDescription(for workout: CompletedWorkout) -> String {
        let note = workout.postWorkoutNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if note.isEmpty {
            return Self.attribution
        }
        return "\(note)\n\n\(Self.attribution)"
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
