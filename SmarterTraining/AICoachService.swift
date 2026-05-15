import Foundation

struct AICoachExplanation: Codable {
    var coachExplanation: String
    var continuityNote: String?
    var tomorrowImplication: String?
    var confidence: String
    var isFallback: Bool
}

@Observable
final class AICoachService {

    private(set) var explanation: AICoachExplanation?
    private(set) var isLoading = false

    private var cachedHash: Int?

    func fetchExplanation(
        recommendation: WorkoutRecommendation,
        checkIn: CheckIn?,
        memorySummary: TrainingMemorySummary,
        lastFeedback: WorkoutFeedback?,
        editedWorkout: Bool,
        auth: BackendAuthService
    ) async {
        let hash = computeHash(recommendation: recommendation, checkIn: checkIn)
        if hash == cachedHash && explanation != nil { return }

        guard auth.isSignedIn, let jwt = auth.jwt else { return }

        isLoading = true
        defer { isLoading = false }

        let body = buildRequestBody(
            recommendation: recommendation,
            checkIn: checkIn,
            memorySummary: memorySummary,
            lastFeedback: lastFeedback,
            editedWorkout: editedWorkout
        )

        do {
            let url = URL(string: "\(BackendAuthService.baseURL)/v1/coach/explanation")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(AICoachExplanation.self, from: data)

            explanation = result
            cachedHash = hash
        } catch {
            // Deterministic reason remains visible
        }
    }

    func invalidateCache() {
        cachedHash = nil
        explanation = nil
    }

    // MARK: - Private

    private func computeHash(recommendation: WorkoutRecommendation, checkIn: CheckIn?) -> Int {
        var hasher = Hasher()
        hasher.combine(recommendation.type.rawValue)
        hasher.combine(recommendation.title)
        hasher.combine(checkIn?.overallFeel)
        hasher.combine(checkIn?.legs)
        hasher.combine(checkIn?.motivation)
        hasher.combine(checkIn?.timeAvailable)
        return hasher.finalize()
    }

    private func buildRequestBody(
        recommendation: WorkoutRecommendation,
        checkIn: CheckIn?,
        memorySummary: TrainingMemorySummary,
        lastFeedback: WorkoutFeedback?,
        editedWorkout: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "recommendation": [
                "type": recommendation.type.rawValue,
                "title": recommendation.title,
                "summary": recommendation.summary,
                "reason": recommendation.reason
            ],
            "edited_workout": editedWorkout
        ]

        if let ci = checkIn {
            body["check_in"] = [
                "feel": ci.overallFeel,
                "legs": ci.legs,
                "motivation": ci.motivation,
                "time": ci.timeAvailable
            ]

            if !ci.recentActivities.isEmpty {
                body["recent_activities"] = ci.recentActivities.map { a in
                    var dict: [String: String] = ["type": a.type]
                    if let t = a.timing { dict["timing"] = t }
                    if let i = a.intensity { dict["intensity"] = i }
                    return dict
                }
            }

            if !ci.contextFlags.isEmpty {
                body["life_context"] = ci.contextFlags
            }
        }

        var memory: [String: Any] = [
            "workouts_7d": memorySummary.completedWorkoutCount7d,
            "hard_days_7d": memorySummary.hardDayCount7d,
            "recovery_days_7d": memorySummary.recoveryDayCount7d,
            "intensity_load": memorySummary.recentIntensityLoadEstimate,
            "returning_after_break": memorySummary.isReturningAfterBreak,
            "high_recent_load": memorySummary.hasHighRecentLoad
        ]
        if let days = memorySummary.daysSinceLastWorkout {
            memory["days_since_last"] = days
        }
        if let fb = memorySummary.lastWorkoutFeedback {
            memory["last_feedback"] = fb.rawValue
        }
        body["training_memory"] = memory

        if let fb = lastFeedback {
            body["last_feedback"] = fb.rawValue
        }

        return body
    }
}
