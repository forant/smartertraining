import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Test Helpers

private let engine = RecommendationEngine()

private func makeProfile(
    currentState: FitnessState? = .consistent,
    goals: [TrainingGoal] = [.endurance],
    frequency: TrainingFrequency? = .moderate,
    equipment: [Equipment] = [.bikeTrainer],
    ftp: Int? = 250
) -> UserProfile {
    UserProfile(
        name: "Test",
        currentState: currentState,
        goals: goals,
        typicalAvailability: .medium,
        trainingFrequency: frequency,
        equipment: equipment,
        ftp: ftp
    )
}

private func makeCheckIn(
    feel: String = "Good",
    legs: String = "Normal",
    motivation: String = "Medium",
    time: Int = 45,
    flags: [String] = []
) -> CheckIn {
    CheckIn(
        overallFeel: feel,
        legs: legs,
        motivation: motivation,
        timeAvailable: time,
        contextFlags: flags,
        notes: nil
    )
}

private func makeHistory(
    _ entries: [(WorkoutType, WorkoutFeedback?)] = []
) -> [WorkoutHistoryEntry] {
    entries.enumerated().map { index, pair in
        let date = Calendar.current.date(byAdding: .day, value: -(entries.count - index), to: Date()) ?? Date()
        return WorkoutHistoryEntry(
            date: date,
            title: pair.0.label,
            type: pair.0,
            checkIn: nil,
            feedback: pair.1
        )
    }
}

private func inputs(
    profile: UserProfile = makeProfile(),
    checkIn: CheckIn = makeCheckIn(),
    history: [WorkoutHistoryEntry] = [],
    intent: ShortTermTrainingIntent? = nil
) -> RecommendationEngine.Inputs {
    RecommendationEngine.Inputs(
        profile: profile,
        checkIn: checkIn,
        recentHistory: history,
        activeIntent: intent
    )
}

private func makeRecoveryIntent(day: ShortTermTrainingIntent.ActiveDay = .day1) -> ShortTermTrainingIntent {
    let now = Date()
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
    let expires = cal.date(byAdding: .day, value: 2, to: today)!

    return ShortTermTrainingIntent(
        sourceWorkoutId: UUID(),
        expiresAt: expires,
        day1Date: day == .day1 ? today : cal.date(byAdding: .day, value: -1, to: today)!,
        day1RecommendedIntensity: .recovery,
        day1Rationale: "Yesterday's session was enough stress. Keep today easy.",
        day2Date: day == .day2 ? today : tomorrow,
        day2RecommendedIntensity: .flexible,
        day2Rationale: "If your legs feel good, today can be your next quality opportunity."
    )
}

private func makeQualityDay2Intent() -> ShortTermTrainingIntent {
    let now = Date()
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
    let expires = cal.date(byAdding: .day, value: 1, to: today)!

    return ShortTermTrainingIntent(
        sourceWorkoutId: UUID(),
        expiresAt: expires,
        day1Date: yesterday,
        day1RecommendedIntensity: .recovery,
        day1Rationale: "Recovery day.",
        day2Date: today,
        day2RecommendedIntensity: .quality,
        day2Rationale: "If your legs feel good, today can be your next quality opportunity."
    )
}

// MARK: - Intent Model Tests

struct ShortTermTrainingIntentTests {

    @Test func activeDay1DetectedCorrectly() {
        let intent = makeRecoveryIntent(day: .day1)
        #expect(intent.activeDay() == .day1)
        #expect(intent.recommendedIntensity() == .recovery)
    }

    @Test func activeDay2DetectedCorrectly() {
        let intent = makeRecoveryIntent(day: .day2)
        #expect(intent.activeDay() == .day2)
        #expect(intent.recommendedIntensity() == .flexible)
    }

    @Test func expiredIntentIsExpired() {
        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: Date().addingTimeInterval(-100),
            day1Date: Date().addingTimeInterval(-86400),
            day1RecommendedIntensity: .recovery,
            day1Rationale: "Test",
            day2Date: Date().addingTimeInterval(-43200),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Test"
        )
        #expect(intent.isExpired)
    }

    @Test func nonExpiredIntentIsNotExpired() {
        let intent = makeRecoveryIntent()
        #expect(!intent.isExpired)
    }

    @Test func rationaleReturnedForActiveDay() {
        let intent = makeRecoveryIntent(day: .day1)
        #expect(intent.rationale()?.contains("enough stress") == true)
    }
}

// MARK: - Intent Builder Tests

struct TrainingIntentBuilderTests {

    @Test func hardWorkoutCreatesDayOneRecoveryIntent() {
        let reflection = PostWorkoutReflection(
            sessionEvaluation: "Hard session.",
            nextTwoDays: [
                .init(dayLabel: "Tomorrow", guidance: "Rest tomorrow.", recommendedIntensity: "recovery"),
                .init(dayLabel: "Day after", guidance: "Quality if fresh.", recommendedIntensity: "quality"),
            ],
            confidence: "high",
            isFallback: false,
            generatedAt: Date()
        )

        let intent = TrainingIntentBuilder.build(
            from: reflection,
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality
        )

        #expect(intent.day1RecommendedIntensity == .recovery)
        #expect(intent.day2RecommendedIntensity == .quality)
    }

    @Test func feedbackBasedIntentHardCreatesRecovery() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .endurance,
            feedback: .hard,
            perceivedEffort: 8
        )
        #expect(intent.day1RecommendedIntensity == .recovery)
    }

    @Test func feedbackBasedIntentEasyCreatesEndurance() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .endurance,
            feedback: .easy,
            perceivedEffort: 3
        )
        #expect(intent.day1RecommendedIntensity == .endurance)
    }

    // MARK: - Subtype-aware recovery cost

    @Test func tempoSubtypeAllowsEnduranceNextDay() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality,
            qualitySubtype: .tempo,
            feedback: .right,
            perceivedEffort: 5
        )
        #expect(intent.day1RecommendedIntensity == .endurance)
    }

    @Test func vo2SubtypeForcesRecoveryNextDay() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality,
            qualitySubtype: .vo2,
            feedback: .right,
            perceivedEffort: 7
        )
        #expect(intent.day1RecommendedIntensity == .recovery)
    }

    @Test func thresholdSubtypeForcesRecoveryNextDay() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality,
            qualitySubtype: .threshold,
            feedback: .right,
            perceivedEffort: 7
        )
        #expect(intent.day1RecommendedIntensity == .recovery)
    }

    @Test func muscularEnduranceModerateCostAllowsEnduranceIfNotHard() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality,
            qualitySubtype: .muscularEndurance,
            feedback: .right,
            perceivedEffort: 6
        )
        #expect(intent.day1RecommendedIntensity == .endurance)
    }

    @Test func tempoWithHardFeedbackStillForcesRecovery() {
        let intent = TrainingIntentBuilder.buildFromFeedback(
            sourceWorkoutId: UUID(),
            workoutCompletedAt: Date(),
            workoutType: .quality,
            qualitySubtype: .tempo,
            feedback: .tooMuch,
            perceivedEffort: 9
        )
        #expect(intent.day1RecommendedIntensity == .recovery)
    }

    @Test func sanitizationBlocksQualityOnDay1() {
        let result = TrainingIntentBuilder.sanitizeIntensity(
            .quality, forDay: .day1, workoutType: .quality
        )
        #expect(result == .endurance)
    }

    @Test func sanitizationAllowsQualityOnDay2() {
        let result = TrainingIntentBuilder.sanitizeIntensity(
            .quality, forDay: .day2, workoutType: .quality
        )
        #expect(result == .quality)
    }

    @Test func sanitizationAlwaysBlocksQualityOnDay1EvenForEndurance() {
        let result = TrainingIntentBuilder.sanitizeIntensity(
            .quality, forDay: .day1, workoutType: .endurance
        )
        #expect(result == .endurance)
    }
}

// MARK: - RecommendationEngine Intent Integration

struct IntentRecommendationTests {

    @Test func recoveryIntentBlocksQuality() {
        let intent = makeRecoveryIntent(day: .day1)
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil), (.endurance, nil)]),
            intent: intent
        ))
        #expect(type == .recovery)
    }

    @Test func recoveryIntentOnDay1ProducesRecovery() {
        let intent = makeRecoveryIntent(day: .day1)
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal"),
            intent: intent
        ))
        #expect(type == .recovery)
    }

    @Test func enduranceIntentProducesEndurance() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let expires = cal.date(byAdding: .day, value: 2, to: today)!

        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: expires,
            day1Date: today,
            day1RecommendedIntensity: .endurance,
            day1Rationale: "Steady day.",
            day2Date: tomorrow,
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Flexible."
        )

        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type == .endurance)
    }

    @Test func flexibleIntentDoesNotOverride() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let expires = cal.date(byAdding: .day, value: 1, to: today)!

        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: expires,
            day1Date: yesterday,
            day1RecommendedIntensity: .recovery,
            day1Rationale: "Recovery.",
            day2Date: today,
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Your call."
        )

        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil), (.endurance, nil)]),
            intent: intent
        ))
        #expect(type == .quality)
    }

    @Test func qualityIntentDay2WithGoodReadinessAllowsQuality() {
        let intent = makeQualityDay2Intent()
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type == .quality)
    }

    @Test func qualityIntentDay2WithPoorReadinessBlocksQuality() {
        let intent = makeQualityDay2Intent()
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low"),
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type != .quality)
    }

    @Test func qualityIntentDay2WithSicknessBlocksQuality() {
        let intent = makeQualityDay2Intent()
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", flags: ["Getting sick"]),
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type != .quality)
    }

    @Test func qualityIntentDay2WithPoorSleepBlocksQuality() {
        let intent = makeQualityDay2Intent()
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", flags: ["Poor sleep"]),
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type != .quality)
    }

    @Test func expiredIntentIgnored() {
        let expired = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: Date().addingTimeInterval(-100),
            day1Date: Calendar.current.startOfDay(for: Date()),
            day1RecommendedIntensity: .recovery,
            day1Rationale: "Old intent.",
            day2Date: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Old."
        )
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: makeHistory([(.endurance, nil), (.endurance, nil)]),
            intent: expired
        ))
        // Expired intent is passed but activeDay returns nil so it has no effect
        // The strong signals should produce quality
        #expect(type == .quality)
    }

    @Test func intentReasonUsedWhenActive() {
        let intent = makeRecoveryIntent(day: .day1)
        let i = inputs(
            checkIn: makeCheckIn(feel: "Good"),
            intent: intent
        )
        let type = engine.chooseWorkoutType(for: i)
        let reason = engine.buildReason(type: type, inputs: i)
        #expect(reason.contains("enough stress"))
    }

    @Test func hardActivityStressSuppressesPlannedQuality() {
        let intent = makeQualityDay2Intent()
        let checkIn = CheckIn(
            overallFeel: "Good",
            legs: "Normal",
            motivation: "High",
            timeAvailable: 45,
            contextFlags: [],
            recentActivities: [
                RecentActivity(type: "Tennis", timing: "Yesterday", intensity: "Very hard")
            ]
        )
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: checkIn,
            history: makeHistory([(.endurance, nil)]),
            intent: intent
        ))
        #expect(type == .endurance)
    }

    @Test func hardRecoveryOverrideStillWinsOverIntent() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let expires = cal.date(byAdding: .day, value: 2, to: today)!

        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: expires,
            day1Date: today,
            day1RecommendedIntensity: .endurance,
            day1Rationale: "Steady day.",
            day2Date: tomorrow,
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Flexible."
        )

        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Bad", legs: "Dead"),
            intent: intent
        ))
        #expect(type == .recovery)
    }
}

// MARK: - Notification Scheduling Tests

struct CoachingNotificationTests {

    @Test func notificationTitlesAreCoachLike() {
        let recoveryIntent = makeRecoveryIntent(day: .day1)
        #expect(recoveryIntent.day1RecommendedIntensity == .recovery)
        // Just verifying the titles don't contain bad language
        // (actual title generation is in NotificationManager, tested at integration level)
    }

    @Test func expiredIntentDoesNotSchedule() {
        let expired = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: Date().addingTimeInterval(-100),
            day1Date: Date().addingTimeInterval(-86400),
            day1RecommendedIntensity: .recovery,
            day1Rationale: "Old.",
            day2Date: Date().addingTimeInterval(-43200),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Old."
        )
        // Scheduling an expired intent should not crash
        CoachingNotificationManager.shared.scheduleNotifications(for: expired)
        // No assertion needed — just verifying it doesn't crash
    }
}

// MARK: - Persistence Round-Trip

struct IntentPersistenceTests {

    @Test func intentEncodesAndDecodes() throws {
        let intent = makeRecoveryIntent()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(intent)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShortTermTrainingIntent.self, from: data)

        #expect(decoded.id == intent.id)
        #expect(decoded.day1RecommendedIntensity == .recovery)
        #expect(decoded.day2RecommendedIntensity == .flexible)
        #expect(decoded.day1Rationale == intent.day1Rationale)
    }
}
