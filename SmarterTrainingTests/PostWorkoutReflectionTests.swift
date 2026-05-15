import Foundation
import Testing
@testable import SmarterTraining

// MARK: - PostWorkoutReflection Codable Tests

struct PostWorkoutReflectionCodableTests {

    @Test func decodesFullResponse() throws {
        let json = """
        {
            "session_evaluation": "Solid session.",
            "what_went_well": "Consistent pacing.",
            "watch_out": "Legs may be tired tomorrow.",
            "next_two_days": [
                {
                    "day_label": "Tomorrow",
                    "guidance": "Easy spin.",
                    "recommended_intensity": "recovery"
                },
                {
                    "day_label": "Day after tomorrow",
                    "guidance": "Structured work.",
                    "recommended_intensity": "quality"
                }
            ],
            "confidence": "high",
            "is_fallback": false,
            "generated_at": "2026-05-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let reflection = try decoder.decode(PostWorkoutReflection.self, from: json)

        #expect(reflection.sessionEvaluation == "Solid session.")
        #expect(reflection.whatWentWell == "Consistent pacing.")
        #expect(reflection.watchOut == "Legs may be tired tomorrow.")
        #expect(reflection.nextTwoDays.count == 2)
        #expect(reflection.nextTwoDays[0].dayLabel == "Tomorrow")
        #expect(reflection.nextTwoDays[0].recommendedIntensity == "recovery")
        #expect(reflection.nextTwoDays[1].dayLabel == "Day after tomorrow")
        #expect(reflection.confidence == "high")
        #expect(reflection.isFallback == false)
    }

    @Test func decodesMinimalResponse() throws {
        let json = """
        {
            "session_evaluation": "Workout complete.",
            "next_two_days": [],
            "confidence": "low",
            "is_fallback": true,
            "generated_at": "2026-05-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let reflection = try decoder.decode(PostWorkoutReflection.self, from: json)

        #expect(reflection.sessionEvaluation == "Workout complete.")
        #expect(reflection.whatWentWell == nil)
        #expect(reflection.watchOut == nil)
        #expect(reflection.nextTwoDays.isEmpty)
        #expect(reflection.isFallback == true)
    }
}

// MARK: - CompletedWorkout Reflection Fields Tests

struct CompletedWorkoutReflectionTests {

    @Test func encodesAndDecodesReflectionFields() throws {
        var workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Zone 2 Ride"
        )

        workout.workoutFeedback = .hard
        workout.perceivedEffort = 7
        workout.postWorkoutNote = "Legs were tired from tennis"
        workout.reflectionStatus = .generated
        workout.reflection = PostWorkoutReflection(
            sessionEvaluation: "Good session.",
            whatWentWell: "Pacing was solid.",
            watchOut: nil,
            nextTwoDays: [
                .init(dayLabel: "Tomorrow", guidance: "Rest.", recommendedIntensity: "rest"),
                .init(dayLabel: "Day after", guidance: "Easy spin.", recommendedIntensity: "recovery")
            ],
            confidence: "high",
            isFallback: false,
            generatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workout)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CompletedWorkout.self, from: data)

        #expect(decoded.workoutFeedback == .hard)
        #expect(decoded.perceivedEffort == 7)
        #expect(decoded.postWorkoutNote == "Legs were tired from tennis")
        #expect(decoded.reflectionStatus == .generated)
        #expect(decoded.reflection?.sessionEvaluation == "Good session.")
        #expect(decoded.reflection?.nextTwoDays.count == 2)
    }

    @Test func backwardsCompatibleWithoutReflectionFields() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "startDate": "2026-05-15T10:00:00Z",
            "duration": 1800,
            "title": "Easy Spin",
            "samples": [],
            "status": "finished",
            "isPostedToStrava": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workout = try decoder.decode(CompletedWorkout.self, from: json)

        #expect(workout.title == "Easy Spin")
        #expect(workout.workoutFeedback == nil)
        #expect(workout.perceivedEffort == nil)
        #expect(workout.reflection == nil)
        #expect(workout.reflectionStatus == nil)
    }

    @Test func computeStatsFromSamples() {
        var workout = CompletedWorkout(
            startDate: Date(),
            duration: 300,
            title: "Test"
        )

        let now = Date()
        let samples: [TrainerMetrics] = [
            TrainerMetrics(power: 150, cadence: 80, speed: nil, heartRate: nil, timestamp: now),
            TrainerMetrics(power: 200, cadence: 90, speed: nil, heartRate: nil, timestamp: now),
            TrainerMetrics(power: 250, cadence: 70, speed: nil, heartRate: nil, timestamp: now),
        ]

        workout.computeStats(from: samples, ergEnabled: true, workoutType: .endurance)

        #expect(workout.averagePower == 200)
        #expect(workout.maxPower == 250)
        #expect(workout.averageCadence == 80)
        #expect(workout.ergWasEnabled == true)
        #expect(workout.workoutType == .endurance)
    }
}

// MARK: - Fallback Reflection Tests

struct FallbackReflectionTests {

    @Test func fallbackIncludesSessionEvaluation() {
        let service = PostWorkoutReflectionService()
        let workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Zone 2 Ride",
            status: .finished,
            workoutFeedback: .right
        )
        let recommendation = WorkoutRecommendation(
            type: .endurance,
            title: "Zone 2 Ride",
            summary: "Aerobic base",
            reason: "test",
            steps: [],
            optionalExtras: []
        )

        let fallback = service.buildFallback(workout: workout, recommendation: recommendation)

        #expect(fallback.isFallback == true)
        #expect(fallback.sessionEvaluation.contains("endurance"))
        #expect(fallback.nextTwoDays.count == 2)
    }

    @Test func fallbackHardFeedbackRecommendsRecovery() {
        let service = PostWorkoutReflectionService()
        let workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Threshold Intervals",
            status: .finished,
            workoutFeedback: .hard
        )
        let recommendation = WorkoutRecommendation(
            type: .quality,
            title: "Threshold Intervals",
            summary: "Intervals",
            reason: "test",
            steps: [],
            optionalExtras: []
        )

        let fallback = service.buildFallback(workout: workout, recommendation: recommendation)

        #expect(fallback.nextTwoDays[0].recommendedIntensity == "recovery")
    }

    @Test func fallbackEasyFeedbackAllowsEndurance() {
        let service = PostWorkoutReflectionService()
        let workout = CompletedWorkout(
            startDate: Date(),
            duration: 1800,
            title: "Easy Spin",
            status: .finished,
            workoutFeedback: .easy,
            workoutType: .recovery
        )
        let recommendation = WorkoutRecommendation(
            type: .recovery,
            title: "Easy Spin",
            summary: "Recovery",
            reason: "test",
            steps: [],
            optionalExtras: []
        )

        let fallback = service.buildFallback(workout: workout, recommendation: recommendation)

        #expect(fallback.nextTwoDays[0].recommendedIntensity == "endurance")
    }

    @Test func fallbackHighEffortRecommendsRecovery() {
        let service = PostWorkoutReflectionService()
        let workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Endurance Ride",
            status: .finished,
            workoutFeedback: .right,
            perceivedEffort: 9,
            workoutType: .endurance
        )
        let recommendation = WorkoutRecommendation(
            type: .endurance,
            title: "Endurance Ride",
            summary: "Base work",
            reason: "test",
            steps: [],
            optionalExtras: []
        )

        let fallback = service.buildFallback(workout: workout, recommendation: recommendation)

        #expect(fallback.nextTwoDays[0].recommendedIntensity == "recovery")
    }
}
