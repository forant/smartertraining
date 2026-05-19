import Foundation
import Observation

@Observable
final class PostWorkoutReflectionService {

    private(set) var reflection: PostWorkoutReflection?
    private(set) var isLoading = false

    #if DEBUG
    /// Pre-seeds a reflection for SwiftUI previews. Production code never calls this.
    func _previewSetReflection(_ value: PostWorkoutReflection) {
        reflection = value
    }
    #endif

    func fetchReflection(
        workout: CompletedWorkout,
        recommendation: WorkoutRecommendation,
        steps: [TrainerWorkoutStep],
        checkIn: CheckIn?,
        memorySummary: TrainingMemorySummary,
        upcomingContext: UpcomingContextSummary = .empty,
        auth: BackendAuthService
    ) async {
        guard auth.isSignedIn, let jwt = auth.jwt else {
            reflection = buildFallback(workout: workout, recommendation: recommendation)
            return
        }

        isLoading = true
        defer { isLoading = false }

        AnalyticsService.shared.track(.postWorkoutReflectionRequested)

        let body = buildRequestBody(
            workout: workout,
            recommendation: recommendation,
            steps: steps,
            checkIn: checkIn,
            memorySummary: memorySummary,
            upcomingContext: upcomingContext
        )

        do {
            let url = URL(string: "\(BackendAuthService.baseURL)/v1/coach/post-workout-reflection")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                reflection = buildFallback(workout: workout, recommendation: recommendation)
                AnalyticsService.shared.track(.postWorkoutReflectionFailed, properties: [
                    "reason": "non_200_response"
                ])
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(PostWorkoutReflection.self, from: data)
            reflection = result

            AnalyticsService.shared.track(.postWorkoutReflectionSucceeded, properties: [
                "is_fallback": result.isFallback
            ])
        } catch {
            reflection = buildFallback(workout: workout, recommendation: recommendation)
            AnalyticsService.shared.track(.postWorkoutReflectionFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.aiCoach, message: error.localizedDescription, subsystem: "reflection")
        }
    }

    // MARK: - Fallback

    func buildFallback(workout: CompletedWorkout, recommendation: WorkoutRecommendation) -> PostWorkoutReflection {
        let eval = buildFallbackEvaluation(workout: workout, recommendation: recommendation)
        let nextDays = buildFallbackGuidance(workout: workout)

        return PostWorkoutReflection(
            sessionEvaluation: eval,
            whatWentWell: nil,
            watchOut: nil,
            nextTwoDays: nextDays,
            confidence: "low",
            isFallback: true,
            generatedAt: Date()
        )
    }

    private func buildFallbackEvaluation(workout: CompletedWorkout, recommendation: WorkoutRecommendation) -> String {
        let durationMin = Int(workout.duration / 60)
        var parts = ["Workout complete \u{2014} \(durationMin) minutes of \(recommendation.type.label.lowercased()) work."]

        if let feedback = workout.workoutFeedback {
            switch feedback {
            case .easy:
                parts.append("You rated this as easy, which is a good sign for building consistency.")
            case .right:
                parts.append("Felt right \u{2014} exactly where you want to be.")
            case .hard:
                parts.append("This landed on the hard side. Recovery matters tomorrow.")
            case .tooMuch:
                parts.append("You flagged this as too much. Take it easy the next couple of days.")
            }
        }

        return parts.joined(separator: " ")
    }

    private func buildFallbackGuidance(workout: CompletedWorkout) -> [PostWorkoutReflection.DayGuidance] {
        let isHard = workout.workoutFeedback == .hard || workout.workoutFeedback == .tooMuch
            || (workout.perceivedEffort ?? 0) >= 8
        let isQuality = workout.workoutType == .quality

        let tomorrow: PostWorkoutReflection.DayGuidance
        let dayAfter: PostWorkoutReflection.DayGuidance

        if isHard || isQuality {
            tomorrow = .init(
                dayLabel: "Tomorrow",
                guidance: "Keep it easy. Recovery or light endurance if you feel like moving.",
                recommendedIntensity: "recovery"
            )
            dayAfter = .init(
                dayLabel: "Day after tomorrow",
                guidance: "If your legs feel good, you can pick up intensity again.",
                recommendedIntensity: "flexible"
            )
        } else {
            tomorrow = .init(
                dayLabel: "Tomorrow",
                guidance: "You have room for another session if you want it.",
                recommendedIntensity: "endurance"
            )
            dayAfter = .init(
                dayLabel: "Day after tomorrow",
                guidance: "A good opportunity for structured work if you're feeling fresh.",
                recommendedIntensity: "flexible"
            )
        }

        return [tomorrow, dayAfter]
    }

    // MARK: - Request Body

    private func buildRequestBody(
        workout: CompletedWorkout,
        recommendation: WorkoutRecommendation,
        steps: [TrainerWorkoutStep],
        checkIn: CheckIn?,
        memorySummary: TrainingMemorySummary,
        upcomingContext: UpcomingContextSummary
    ) -> [String: Any] {
        var body: [String: Any] = [:]

        // Workout summary
        var workoutDict: [String: Any] = [
            "title": workout.title,
            "duration_seconds": Int(workout.duration),
            "workout_type": recommendation.type.rawValue
        ]
        if let avg = workout.averagePower { workoutDict["average_power"] = avg }
        if let max = workout.maxPower { workoutDict["max_power"] = max }
        if let avgCad = workout.averageCadence { workoutDict["average_cadence"] = avgCad }
        if let avgHR = workout.averageHeartRate { workoutDict["average_heart_rate"] = avgHR }
        if let maxHR = workout.maxHeartRate { workoutDict["max_heart_rate"] = maxHR }
        if let erg = workout.ergWasEnabled { workoutDict["erg_enabled"] = erg }
        body["workout_summary"] = workoutDict

        // Original recommendation
        body["recommendation"] = [
            "type": recommendation.type.rawValue,
            "title": recommendation.title,
            "summary": recommendation.summary
        ]

        // Executed steps summary
        let stepSummaries = steps.prefix(10).map { step -> [String: Any] in
            [
                "name": step.name,
                "duration_seconds": Int(step.duration),
                "target_power": step.targetPower,
                "role": step.role.rawValue
            ]
        }
        body["executed_steps"] = stepSummaries

        // User feedback
        if let feedback = workout.workoutFeedback {
            body["feedback"] = feedback.rawValue
        }
        if let effort = workout.perceivedEffort {
            body["perceived_effort"] = effort
        }
        if let note = workout.postWorkoutNote, !note.isEmpty {
            body["user_note"] = String(note.prefix(200))
        }

        // Check-in context
        if let ci = checkIn {
            body["check_in"] = [
                "feel": ci.overallFeel,
                "legs": ci.legs,
                "motivation": ci.motivation,
                "time": ci.timeAvailable
            ]
            if !ci.contextFlags.isEmpty {
                body["life_context"] = ci.contextFlags
            }
        }

        // Training memory
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

        if !upcomingContext.isEmpty {
            body["upcoming_context"] = upcomingContext.events.map { event -> [String: Any] in
                var dict: [String: Any] = [
                    "type": event.type.rawValue,
                    "days_until": event.daysFromNow,
                    "impact": event.impact.rawValue
                ]
                if let dur = event.duration { dict["duration"] = dur.rawValue }
                if let note = event.note { dict["note"] = String(note.prefix(200)) }
                return dict
            }
        }

        return body
    }
}
