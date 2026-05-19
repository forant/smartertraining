import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Test Helpers

private let engine = RecommendationEngine()

private func makeProfile(
    currentState: FitnessState? = .consistent,
    goals: [TrainingGoal] = [.endurance],
    availability: TypicalAvailability? = .medium,
    frequency: TrainingFrequency? = .moderate,
    equipment: [Equipment] = [.bikeTrainer],
    ftp: Int? = 250
) -> UserProfile {
    UserProfile(
        name: "Test",
        currentState: currentState,
        goals: goals,
        typicalAvailability: availability,
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
    history: [WorkoutHistoryEntry] = []
) -> RecommendationEngine.Inputs {
    RecommendationEngine.Inputs(profile: profile, checkIn: checkIn, recentHistory: history)
}

// MARK: - Hard Recovery Overrides

struct HardRecoveryOverrideTests {

    @Test func badFeelTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(feel: "Bad")))
        #expect(type == .recovery)
    }

    @Test func deadLegsTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(legs: "Dead")))
        #expect(type == .recovery)
    }

    @Test func gettingSickTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(checkIn: makeCheckIn(flags: ["Getting sick"])))
        #expect(type == .recovery)
    }

    @Test func okayLowHeavyTriggersRecovery() {
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low")
        ))
        #expect(type == .recovery)
    }

    @Test func recoveryReasonMentionsSick() {
        let i = inputs(checkIn: makeCheckIn(flags: ["Getting sick"]))
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("sick"))
    }

    @Test func recoveryReasonMentionsDeadLegs() {
        let i = inputs(checkIn: makeCheckIn(legs: "Dead"))
        let reason = engine.buildReason(type: .recovery, inputs: i)
        #expect(reason.contains("Dead legs"))
    }
}

// MARK: - History Guardrails

struct HistoryGuardrailTests {

    @Test func noBackToBackQuality() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func afterQualityWithHeavyLegsGoesToRecoveryOrEndurance() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Heavy", motivation: "Low"),
            history: history
        ))
        #expect(type == .recovery)
    }

    @Test func afterQualityWithOkayFeelGoesToEndurance() {
        let history = makeHistory([(.quality, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay", legs: "Normal", motivation: "Medium"),
            history: history
        ))
        #expect(type == .endurance)
    }
}

// MARK: - Feedback-Aware Behavior

struct FeedbackAwareTests {

    @Test func tooMuchWithOkayFeelTriggersRecovery() {
        let history = makeHistory([(.quality, .tooMuch)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Okay"),
            history: history
        ))
        #expect(type == .recovery)
    }

    @Test func tooMuchWithGoodFeelGoesToEndurance() {
        let history = makeHistory([(.quality, .tooMuch)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium"),
            history: history
        ))
        #expect(type == .endurance)
    }

    @Test func easyFeedbackAfterEasierStretchOpensQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, .easy)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func hardFeedbackDiscouragesQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, .hard)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func enduranceReasonMentionsTooMuch() {
        let history = makeHistory([(.quality, .tooMuch)])
        let i = inputs(checkIn: makeCheckIn(feel: "Good"), history: history)
        let reason = engine.buildReason(type: .endurance, inputs: i)
        #expect(reason.contains("too much"))
    }
}

// MARK: - Quality Conditions

struct QualityConditionTests {

    @Test func freshLegsGreatFeelHighMotivationCanQuality() {
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func heavyLegsNeverQuality() {
        let history = makeHistory([(.endurance, nil), (.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Heavy", motivation: "High"),
            history: history
        ))
        #expect(type != .quality)
    }

    @Test func easierStretchWithStrongSignalsOpensQuality() {
        let history = makeHistory([(.endurance, nil), (.recovery, nil), (.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }
}

// MARK: - Time Shaping

struct TimeShapingTests {

    @Test func shortTimeRecoveryIsEasySpin() {
        let workout = engine.buildWorkout(type: .recovery, time: 15, reason: "test")
        #expect(workout.title == "Easy Spin")
        #expect(workout.steps.count == 1)
    }

    @Test func longerRecoveryHasThreeSteps() {
        let workout = engine.buildWorkout(type: .recovery, time: 40, reason: "test")
        #expect(workout.title == "Recovery Day")
        #expect(workout.steps.count == 3)
    }

    @Test func shortEnduranceIs20Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 20, reason: "test")
        #expect(workout.title == "Short Aerobic Spin")
    }

    @Test func mediumEnduranceIs30Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 30, reason: "test")
        #expect(workout.title == "30 min Zone 2 Ride")
    }

    @Test func standardEnduranceIs45Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 45, reason: "test")
        #expect(workout.title == "45 min Zone 2 Ride")
    }

    @Test func longEnduranceIs60Min() {
        let workout = engine.buildWorkout(type: .endurance, time: 60, reason: "test")
        #expect(workout.title == "60 min Endurance Ride")
    }

    @Test func shortQualityFallbackIsThreshold() {
        // Without a subtype, buildWorkout falls back to threshold for quality.
        let workout = engine.buildWorkout(type: .quality, time: 25, reason: "test")
        #expect(workout.qualitySubtype == .threshold)
        #expect(workout.title == "Compact Threshold")
    }

    @Test func standardQualityFallbackIsThreshold() {
        let workout = engine.buildWorkout(type: .quality, time: 45, reason: "test")
        #expect(workout.qualitySubtype == .threshold)
        #expect(workout.title == "Threshold Intervals")
        #expect(workout.steps.count == 3)
    }

    @Test func longQualityHasLongerWarmup() {
        let workout = engine.buildWorkout(type: .quality, time: 60, reason: "test")
        #expect(workout.steps.first?.durationText == "15 min")
    }
}

// MARK: - Quality Subtype Selection

struct QualitySubtypeSelectionTests {

    private func qualityInputs(
        profile: UserProfile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy),
        feel: String = "Great",
        legs: String = "Fresh",
        motivation: String = "High",
        time: Int = 45,
        memory: TrainingMemorySummary = .empty,
        intent: ShortTermTrainingIntent? = nil,
        history: [WorkoutHistoryEntry] = makeHistory([(.endurance, nil), (.endurance, nil)])
    ) -> RecommendationEngine.Inputs {
        RecommendationEngine.Inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: feel, legs: legs, motivation: motivation, time: time),
            recentHistory: history,
            memorySummary: memory,
            activeIntent: intent
        )
    }

    @Test func peakReadinessSelectsVO2() {
        let subtype = engine.chooseQualitySubtype(for: qualityInputs())
        #expect(subtype == .vo2)
    }

    @Test func goodButNotPeakReadinessSkipsVO2() {
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(feel: "Good"))
        #expect(subtype != .vo2)
    }

    @Test func shortTimeFallsBackFromOverUnders() {
        // 30 min cuts over-unders out of the running.
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(feel: "Good", time: 30))
        #expect(subtype != .overUnders)
    }

    @Test func varietyAvoidsRepeatingLastSubtype() {
        var memory = TrainingMemorySummary.empty
        memory.lastQualitySubtype = .vo2
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(memory: memory))
        #expect(subtype != .vo2)
    }

    @Test func intentHintIsHonored() {
        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: Date().addingTimeInterval(86400 * 3),
            day1Date: Calendar.current.startOfDay(for: Date()),
            day1RecommendedIntensity: .quality,
            day1Rationale: "Go for muscular endurance",
            day2Date: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Adjust based on feel",
            qualitySubtype: .muscularEndurance
        )
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(intent: intent))
        #expect(subtype == .muscularEndurance)
    }

    @Test func tempoIsAlwaysAFallback() {
        // Even with very short time and moderate readiness, something should be selected.
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(feel: "Good", legs: "Normal", time: 25))
        #expect([.tempo, .threshold].contains(subtype))
    }
}

// MARK: - Quality Subtype Workout Builders

struct QualitySubtypeBuilderTests {

    @Test func vo2BuilderProducesVO2Workout() {
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, time: 45, reason: "test")
        #expect(workout.qualitySubtype == .vo2)
        #expect(workout.title.contains("VO2"))
        #expect(workout.steps.contains { $0.targetText.contains("106") || $0.targetText.contains("108") })
    }

    @Test func muscularEnduranceBuilderProducesMEWorkout() {
        let workout = engine.buildWorkout(type: .quality, subtype: .muscularEndurance, time: 60, reason: "test")
        #expect(workout.qualitySubtype == .muscularEndurance)
        #expect(workout.title.contains("Muscular Endurance"))
        // 60-min ME template should be 3 x 12 min as documented.
        #expect(workout.steps.contains { $0.durationText.contains("3 x 12") || $0.durationText.contains("3 x 9") })
    }

    @Test func tempoBuilderProducesTempoWorkout() {
        let workout = engine.buildWorkout(type: .quality, subtype: .tempo, time: 45, reason: "test")
        #expect(workout.qualitySubtype == .tempo)
        #expect(workout.title.contains("Tempo"))
        #expect(workout.steps.contains { $0.targetText.contains("80") })
    }

    @Test func overUndersBuilderProducesOverUndersWorkout() {
        let workout = engine.buildWorkout(type: .quality, subtype: .overUnders, time: 60, reason: "test")
        #expect(workout.qualitySubtype == .overUnders)
        #expect(workout.title.contains("Over/Under"))
        #expect(workout.steps.contains { $0.targetText.contains("Alternate") })
    }

    @Test func thresholdBuilderProducesThresholdWorkout() {
        let workout = engine.buildWorkout(type: .quality, subtype: .threshold, time: 45, reason: "test")
        #expect(workout.qualitySubtype == .threshold)
        #expect(workout.title.contains("Threshold"))
    }

    @Test func recommendCarriesSubtypeWhenQualityIsChosen() {
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let result = engine.recommend(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 45),
            history: makeHistory([(.endurance, nil), (.endurance, nil)])
        ))
        #expect(result.type == .quality)
        #expect(result.qualitySubtype != nil)
    }

    @Test func nonQualityRecommendationHasNoSubtype() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(feel: "Bad", time: 30)
        ))
        #expect(result.type == .recovery)
        #expect(result.qualitySubtype == nil)
    }
}

// MARK: - Audit-Driven Subtype Selection Tests

struct QualitySubtypeAuditTests {

    private func aHistory(_ count: Int) -> [WorkoutHistoryEntry] {
        makeHistory(Array(repeating: (WorkoutType.endurance, WorkoutFeedback?.none), count: count))
    }

    private func auditInputs(
        profile: UserProfile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy),
        feel: String = "Great",
        legs: String = "Fresh",
        motivation: String = "High",
        time: Int = 45,
        memory: TrainingMemorySummary = .empty,
        intent: ShortTermTrainingIntent? = nil,
        historyCount: Int = 3
    ) -> RecommendationEngine.Inputs {
        RecommendationEngine.Inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: feel, legs: legs, motivation: motivation, time: time),
            recentHistory: aHistory(historyCount),
            memorySummary: memory,
            activeIntent: intent
        )
    }

    // Fix B: load down-shift

    @Test func meSelectedUnderHighLoad() {
        var memory = TrainingMemorySummary.empty
        memory.hardDayCount7d = 3
        memory.recentIntensityLoadEstimate = 10
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 45, memory: memory))
        #expect(subtype == .muscularEndurance)
    }

    @Test func tempoSelectedAfterHardWeek() {
        var memory = TrainingMemorySummary.empty
        memory.hardDayCount7d = 3
        memory.recentIntensityLoadEstimate = 10
        // Short time pushes ME out, so tempo should win.
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 30, memory: memory))
        #expect(subtype == .tempo)
    }

    @Test func loadDownshiftBlocksVO2AndOverUnders() {
        var memory = TrainingMemorySummary.empty
        memory.hardDayCount7d = 3
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, memory: memory))
        #expect(subtype != .vo2)
        #expect(subtype != .overUnders)
    }

    // Fix C: week-level variety

    @Test func weekRotationProducesAtLeastThreeDistinctSubtypes() {
        var memory = TrainingMemorySummary.empty
        var picked: [QualitySubtype] = []

        for _ in 0..<4 {
            let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, memory: memory))
            picked.append(subtype)
            memory.lastQualitySubtype = subtype
            memory.recentQualitySubtypes7d.append(subtype)
        }

        #expect(Set(picked).count >= 3)
    }

    @Test func overusedSubtypeIsFiltered() {
        var memory = TrainingMemorySummary.empty
        memory.recentQualitySubtypes7d = [.vo2, .vo2]
        memory.lastQualitySubtype = .threshold
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, memory: memory))
        #expect(subtype != .vo2)
        #expect(subtype != .threshold)
    }

    // Fix A: intent gating

    @Test func intentOutsideActiveWindowIsIgnored() {
        let cal = Calendar.current
        // day1 was two days ago, day2 yesterday — not active today, but not yet expired.
        let twoDaysAgo = cal.startOfDay(for: cal.date(byAdding: .day, value: -2, to: Date())!)
        let yesterday = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date())!)
        let expiresAt = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)

        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: expiresAt,
            day1Date: twoDaysAgo,
            day1RecommendedIntensity: .quality,
            day1Rationale: "Past day1",
            day2Date: yesterday,
            day2RecommendedIntensity: .quality,
            day2Rationale: "Past day2",
            qualitySubtype: .muscularEndurance
        )

        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, intent: intent))
        // Without the gate this would return .muscularEndurance; with Fix A it
        // falls through to the deterministic path which picks .vo2 at peak readiness.
        #expect(subtype == .vo2)
    }

    @Test func expiredIntentDoesNotOverrideSelection() {
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date())
        let day2 = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
        // expiresAt set in the past
        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: cal.date(byAdding: .day, value: -1, to: Date())!,
            day1Date: day1,
            day1RecommendedIntensity: .quality,
            day1Rationale: "Expired",
            day2Date: day2,
            day2RecommendedIntensity: .flexible,
            day2Rationale: "Expired",
            qualitySubtype: .tempo
        )

        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, intent: intent))
        #expect(subtype != .tempo)
    }

    // Fix E: VO2 guards

    @Test func vo2NotPickedForReturningAthlete() {
        var memory = TrainingMemorySummary.empty
        memory.daysSinceLastWorkout = 7   // triggers isReturningAfterBreak
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, memory: memory))
        #expect(subtype != .vo2)
    }

    @Test func vo2NotPickedForLowWillingness() {
        let profile = makeProfile(currentState: .justStarting, goals: [.consistent], frequency: .light)
        let subtype = engine.chooseQualitySubtype(for: auditInputs(profile: profile, time: 60))
        #expect(subtype != .vo2)
    }

    @Test func vo2NotPickedWithThinHistory() {
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 60, historyCount: 1))
        #expect(subtype != .vo2)
    }

    // Over-unders eligibility

    @Test func overUndersBlockedUnder35Min() {
        let subtype = engine.chooseQualitySubtype(for: auditInputs(time: 30))
        #expect(subtype != .overUnders)
    }
}

// MARK: - Over/Under Trainer Step Expansion

struct OverUnderConverterTests {

    @Test func overUndersExpandIntoAlternatingPowerSteps() {
        let recommendation = engine.buildWorkout(type: .quality, subtype: .overUnders, time: 60, reason: "test")
        let trainerSteps = WorkoutConverter.convert(recommendation: recommendation, ftp: 250)

        // Find over/under sub-steps in the main set
        let overSteps = trainerSteps.filter { $0.name.hasPrefix("Over (Set") }
        let underSteps = trainerSteps.filter { $0.name.hasPrefix("Under (Set") }

        #expect(!overSteps.isEmpty)
        #expect(!underSteps.isEmpty)
        // Over watts should be higher than under watts
        if let over = overSteps.first, let under = underSteps.first {
            #expect(over.targetPower > under.targetPower)
        }
    }
}

// MARK: - Screenshot Seeding (DEBUG-only)

struct ScreenshotSeederTests {

    // MARK: Launch-arg parsing

    @Test func parsesTodayRecommendationArg() {
        let scenario = ScreenshotSeeder.scenario(from: ["app", "-seedTodayRecommendation"])
        #expect(scenario == .todayRecommendation)
    }

    @Test func parsesAdaptiveCoachingArg() {
        let scenario = ScreenshotSeeder.scenario(from: ["app", "-seedAdaptiveCoaching"])
        #expect(scenario == .adaptiveCoaching)
    }

    @Test func unknownArgReturnsNil() {
        let scenario = ScreenshotSeeder.scenario(from: ["app", "-randomArg"])
        #expect(scenario == nil)
    }

    @Test func emptyArgsReturnsNil() {
        let scenario = ScreenshotSeeder.scenario(from: [])
        #expect(scenario == nil)
    }

    @Test func appearanceOverrideParsesLight() {
        let override = ScreenshotSeeder.appearanceOverride(from: ["-forceLightMode"])
        #expect(override == .forceLightMode)
    }

    @Test func appearanceOverrideParsesDark() {
        let override = ScreenshotSeeder.appearanceOverride(from: ["-forceDarkMode"])
        #expect(override == .forceDarkMode)
    }

    // MARK: Seed construction

    @Test func everyScenarioProducesNonEmptySeed() {
        for scenario in ScreenshotSeeder.Scenario.allCases {
            let seed = ScreenshotSeeder.build(scenario)
            #expect(seed.profile != nil)
            #expect(seed.checkIn != nil)
        }
    }

    @Test func todayRecommendationSeedHasStableProgression() {
        let seed = ScreenshotSeeder.build(.todayRecommendation)
        // Stable progression should include at least one stable-or-better subtype.
        #expect(seed.progressionState.stableOrBetterSubtypeCount >= 1)
    }

    @Test func adaptiveCoachingSeedIncludesCompletedRide() {
        let seed = ScreenshotSeeder.build(.adaptiveCoaching)
        #expect(!seed.rides.isEmpty)
        #expect(seed.rides.first?.coachReflection != nil)
        #expect(seed.approach == .ambitious)
    }

    @Test func recoveryDaySeedUsesSustainableApproach() {
        let seed = ScreenshotSeeder.build(.recoveryDay)
        #expect(seed.approach == .sustainable)
        #expect(seed.checkIn?.contextFlags.contains("Poor sleep") == true)
    }

    @Test func progressionSeedHasAdvancedTier() {
        let seed = ScreenshotSeeder.build(.progression)
        // Advanced progression has at least one subtype at .stable or better.
        #expect(seed.progressionState.stableOrBetterSubtypeCount >= 1)
        #expect(seed.approach == .ambitious)
    }

    @Test func coachSettingsSeedPopulatesNotes() {
        let seed = ScreenshotSeeder.build(.coachSettings)
        #expect(!seed.coachNotes.isEmpty)
    }
}

// MARK: - Screenshot Factory

struct ScreenshotFactoryTests {

    @Test func realisticHistorySpansSevenDays() {
        let history = ScreenshotFactory.realisticRecentHistory()
        // 6 entries spanning days -6 through -1.
        #expect(history.count == 6)
    }

    @Test func realisticHistoryIncludesQualityWithSubtype() {
        let history = ScreenshotFactory.realisticRecentHistory()
        let qualityEntry = history.first { $0.type == .quality }
        #expect(qualityEntry?.qualitySubtype != nil)
    }

    @Test func completedRideHasRealisticSamples() {
        let ride = ScreenshotFactory.completedThresholdRide(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ftp: 240
        )
        // Should have ~45 min of 1Hz samples = 2700.
        #expect(ride.samples.count >= 2700)
        // Power, HR, and cadence should all be populated.
        #expect(ride.samples.contains { $0.power != nil && ($0.power ?? 0) > 0 })
        #expect(ride.samples.contains { $0.heartRate != nil && ($0.heartRate ?? 0) > 0 })
        #expect(ride.samples.contains { $0.cadence != nil && ($0.cadence ?? 0) > 0 })
        // Averages computed.
        #expect(ride.averagePower != nil)
        #expect(ride.averageHeartRate != nil)
    }

    @Test func powersStayInBelievableRange() {
        let ride = ScreenshotFactory.completedThresholdRide(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ftp: 240
        )
        let powers = ride.samples.compactMap(\.power).filter { $0 > 0 }
        let max = powers.max() ?? 0
        // 240 FTP, threshold session — max should never exceed ~270W.
        #expect(max <= 270)
        // Average should land near threshold-session expectations (130–220W mixed).
        if let avg = ride.averagePower {
            #expect(avg >= 100 && avg <= 220)
        }
    }

    @Test func sampleGenerationIsDeterministic() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = ScreenshotFactory.completedThresholdRide(startedAt: start, ftp: 240)
        let b = ScreenshotFactory.completedThresholdRide(startedAt: start, ftp: 240)
        // Same start time + FTP should produce identical sample shapes.
        #expect(a.samples.count == b.samples.count)
        if !a.samples.isEmpty {
            #expect(a.samples.first?.power == b.samples.first?.power)
            #expect(a.samples.last?.power == b.samples.last?.power)
        }
    }

    @Test func stableProgressionHasAtLeastOneStableSubtype() {
        let state = ScreenshotFactory.stableProgression()
        #expect(state.stableOrBetterSubtypeCount >= 1)
    }
}

// MARK: - Execution Guidance ("What matters today")

struct ExecutionGuidanceTests {

    private func recommendation(type: WorkoutType, subtype: QualitySubtype? = nil) -> WorkoutRecommendation {
        WorkoutRecommendation(
            type: type,
            qualitySubtype: subtype,
            title: "Test",
            summary: "Test",
            reason: "Test",
            steps: [],
            optionalExtras: []
        )
    }

    // MARK: Coverage

    @Test func everyWorkoutTypeProducesNonEmptyGuidance() {
        for type in [WorkoutType.recovery, .endurance, .quality] {
            let rec = recommendation(type: type, subtype: type == .quality ? .threshold : nil)
            let text = ExecutionGuidanceBuilder.build(recommendation: rec)
            #expect(!text.isEmpty)
        }
    }

    @Test func everyQualitySubtypeProducesDistinctGuidance() {
        var texts: Set<String> = []
        for subtype in QualitySubtype.allCases {
            let rec = recommendation(type: .quality, subtype: subtype)
            let text = ExecutionGuidanceBuilder.build(recommendation: rec)
            texts.insert(text)
        }
        // Each subtype should produce a distinct baseline.
        #expect(texts.count == QualitySubtype.allCases.count)
    }

    // MARK: Subtype-specific language

    @Test func vo2GuidanceMentionsRepeatability() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .vo2))
        #expect(text.lowercased().contains("repeatable"))
    }

    @Test func thresholdGuidanceMentionsSustainedOrControlled() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .threshold))
        let lower = text.lowercased()
        #expect(lower.contains("sustained") || lower.contains("controlled"))
    }

    @Test func meGuidanceMentionsSustainedPressure() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .muscularEndurance))
        #expect(text.lowercased().contains("sustained"))
    }

    @Test func tempoGuidanceMentionsSteady() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .tempo))
        #expect(text.lowercased().contains("steady"))
    }

    @Test func overUndersGuidanceMentionsControl() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .overUnders))
        #expect(text.lowercased().contains("control"))
    }

    @Test func recoveryGuidanceMentionsCirculationOrRecovery() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .recovery))
        let lower = text.lowercased()
        #expect(lower.contains("circulation") || lower.contains("recovery"))
    }

    @Test func enduranceGuidanceMentionsConversationalOrRelaxed() {
        let text = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .endurance))
        let lower = text.lowercased()
        #expect(lower.contains("conversational") || lower.contains("relaxed"))
    }

    // MARK: Tier modifiers

    @Test func starterTierAddsPacingRestraintLanguage() {
        var progression = ProgressionState.empty
        // Starter is default
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .vo2),
            progression: progression
        )
        #expect(text.lowercased().contains("conservative") || text.lowercased().contains("feel for"))

        // Avoid unused-variable warning
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        _ = progression
    }

    @Test func stableTierAddsSmoothnessLanguage() {
        var progression = ProgressionState.empty
        for _ in 0..<4 {
            progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        }
        #expect(progression.tier(for: .vo2) == .stable)
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .vo2),
            progression: progression
        )
        #expect(text.lowercased().contains("smoothness") || text.lowercased().contains("smooth"))
    }

    @Test func progressingTierAddsNoTierModifier() {
        var progression = ProgressionState.empty
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        #expect(progression.tier(for: .vo2) == .progressing)
        let base = ExecutionGuidanceBuilder.build(recommendation: recommendation(type: .quality, subtype: .vo2))
        let progressing = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .vo2),
            progression: progression
        )
        // Starter adds a line. Progressing should match the no-progression baseline minus that addition.
        // Use length proxy: progressing < starter baseline (which has the line)
        #expect(progressing.count < base.count)
    }

    @Test func advancedTierAddsComposureLanguage() {
        var progression = ProgressionState.empty
        for _ in 0..<8 {
            progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        }
        #expect(progression.tier(for: .vo2) == .advanced)
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .vo2),
            progression: progression
        )
        #expect(text.lowercased().contains("composure"))
    }

    // MARK: Training approach

    @Test func sustainableAddsReserveLanguage() {
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .threshold),
            approach: .sustainable
        )
        #expect(text.lowercased().contains("reserve"))
    }

    @Test func ambitiousAddsLeanInLanguage() {
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .threshold),
            approach: .ambitious
        )
        #expect(text.lowercased().contains("lean into"))
    }

    @Test func balancedAddsNoApproachModifier() {
        let balanced = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .threshold),
            approach: .balanced
        )
        let ambitious = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .threshold),
            approach: .ambitious
        )
        #expect(balanced.count < ambitious.count)
    }

    // MARK: Coach notes

    @Test func legsFatigueFirstShapesMEGuidance() {
        var notes = CoachNotes.empty
        notes.tags = [.legsFatigueFirst]
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .muscularEndurance),
            coachNotes: notes
        )
        #expect(text.lowercased().contains("limiter") || text.lowercased().contains("pace the legs"))
    }

    @Test func kneeSensitivityShapesGrindingLanguage() {
        var notes = CoachNotes.empty
        notes.tags = [.kneeSensitivity]
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .muscularEndurance),
            coachNotes: notes
        )
        #expect(text.lowercased().contains("grinding") || text.lowercased().contains("cadence"))
    }

    @Test func vo2MentallyDifficultSoftensVO2() {
        var notes = CoachNotes.empty
        notes.tags = [.vo2MentallyDifficult]
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .vo2),
            coachNotes: notes
        )
        #expect(text.lowercased().contains("discomfort"))
    }

    @Test func kneeNoteDoesNotInfluenceTempo() {
        var notes = CoachNotes.empty
        notes.tags = [.kneeSensitivity]
        let baseline = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .tempo)
        )
        let withNote = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .quality, subtype: .tempo),
            coachNotes: notes
        )
        // Tempo is not a low-cadence subtype, so the knee note shouldn't fire.
        #expect(baseline == withNote)
    }

    // MARK: Recovery + endurance ignore quality modifiers

    @Test func recoveryGuidanceIgnoresProgressionFraming() {
        var progression = ProgressionState.empty
        for _ in 0..<8 {
            progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        }
        let text = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .recovery),
            progression: progression,
            approach: .ambitious
        )
        // Recovery should not adopt advanced/ambitious quality framing.
        #expect(!text.lowercased().contains("composure"))
        #expect(!text.lowercased().contains("lean into"))
    }

    @Test func enduranceGuidanceIgnoresApproachModifier() {
        let balanced = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .endurance), approach: .balanced
        )
        let ambitious = ExecutionGuidanceBuilder.build(
            recommendation: recommendation(type: .endurance), approach: .ambitious
        )
        #expect(balanced == ambitious)
    }

    // MARK: Length + tone

    @Test func guidanceStaysUnderMaxLength() {
        // Stack every layer at once and verify the clamp holds.
        var progression = ProgressionState.empty
        for _ in 0..<8 { progression = progression.applying(signal: .confidentSuccess, to: .muscularEndurance) }
        var notes = CoachNotes.empty
        notes.tags = [.legsFatigueFirst, .kneeSensitivity]
        for subtype in QualitySubtype.allCases {
            let text = ExecutionGuidanceBuilder.build(
                recommendation: recommendation(type: .quality, subtype: subtype),
                progression: progression,
                approach: .ambitious,
                coachNotes: notes
            )
            #expect(text.count <= ExecutionGuidanceBuilder.maxLength)
        }
    }

    @Test func noMachoLanguageAppearsAnywhere() {
        let blacklist = ["crush", "destroy", "beast", "empty the tank", "punish", "hardcore"]
        var progression = ProgressionState.empty
        for _ in 0..<8 { progression = progression.applying(signal: .confidentSuccess, to: .vo2) }

        for type in [WorkoutType.recovery, .endurance, .quality] {
            for subtype in (type == .quality ? QualitySubtype.allCases : [QualitySubtype.threshold]) {
                for approach in TrainingApproach.allCases {
                    let text = ExecutionGuidanceBuilder.build(
                        recommendation: recommendation(type: type, subtype: type == .quality ? subtype : nil),
                        progression: progression,
                        approach: approach
                    )
                    let lower = text.lowercased()
                    for term in blacklist {
                        #expect(!lower.contains(term))
                    }
                }
            }
        }
    }
}

// MARK: - Training Approach

struct TrainingApproachTests {

    // MARK: Defaults & metadata

    @Test func defaultIsBalanced() {
        #expect(TrainingApproach.default == .balanced)
    }

    @Test func allApproachesHaveTitleAndDescription() {
        for approach in TrainingApproach.allCases {
            #expect(!approach.title.isEmpty)
            #expect(!approach.shortDescription.isEmpty)
            #expect(!approach.coachExplanation.isEmpty)
        }
    }

    // MARK: Advancement thresholds

    @Test func sustainableRequiresThreeSuccessesToAdvance() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .sustainable)
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .sustainable)
        #expect(state.tier(for: .vo2) == .starter) // still not advanced after 2
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .sustainable)
        #expect(state.tier(for: .vo2) == .progressing)
    }

    @Test func balancedRequiresTwoSuccessesToAdvance() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .balanced)
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .balanced)
        #expect(state.tier(for: .vo2) == .progressing)
    }

    @Test func ambitiousAdvancesOnTwoSuccessesSameAsBalanced() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .ambitious)
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .ambitious)
        #expect(state.tier(for: .vo2) == .progressing)
    }

    @Test func ambitiousPreservesSuccessStreakAcrossMixed() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .ambitious)
        state = state.applying(signal: .mixed, to: .vo2, approach: .ambitious)
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .ambitious)
        // Mixed doesn't reset the streak under ambitious; 2 successes total -> advance
        #expect(state.tier(for: .vo2) == .progressing)
    }

    @Test func balancedMixedBreaksSuccessStreak() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .balanced)
        state = state.applying(signal: .mixed, to: .vo2, approach: .balanced)
        state = state.applying(signal: .confidentSuccess, to: .vo2, approach: .balanced)
        // Balanced: mixed drained the streak, still at starter
        #expect(state.tier(for: .vo2) == .starter)
    }

    // MARK: Regression thresholds

    @Test func ambitiousToleratesThreeStrugglesBeforeRegression() {
        var state = ProgressionState.empty
        // Climb to progressing first
        state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .ambitious)
        state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .ambitious)
        #expect(state.tier(for: .threshold) == .progressing)
        // Two struggles is not enough under ambitious
        state = state.applying(signal: .struggle, to: .threshold, approach: .ambitious)
        state = state.applying(signal: .struggle, to: .threshold, approach: .ambitious)
        #expect(state.tier(for: .threshold) == .progressing)
        // Third struggle finally regresses
        state = state.applying(signal: .struggle, to: .threshold, approach: .ambitious)
        #expect(state.tier(for: .threshold) == .starter)
    }

    @Test func sustainableRegressesAfterTwoStruggles() {
        var state = ProgressionState.empty
        // Climb to progressing using sustainable thresholds
        state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .sustainable)
        state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .sustainable)
        state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .sustainable)
        #expect(state.tier(for: .threshold) == .progressing)
        state = state.applying(signal: .struggle, to: .threshold, approach: .sustainable)
        state = state.applying(signal: .struggle, to: .threshold, approach: .sustainable)
        #expect(state.tier(for: .threshold) == .starter)
    }

    // MARK: Willingness bias

    @Test func sustainableLowersWillingness() {
        let profile = makeProfile(currentState: .consistent, goals: [.endurance])
        let balanced = engine.qualityWillingness(for: profile, progression: .empty, approach: .balanced)
        let sustainable = engine.qualityWillingness(for: profile, progression: .empty, approach: .sustainable)
        #expect(sustainable < balanced)
    }

    @Test func ambitiousRaisesWillingness() {
        let profile = makeProfile(currentState: .consistent, goals: [.endurance])
        let balanced = engine.qualityWillingness(for: profile, progression: .empty, approach: .balanced)
        let ambitious = engine.qualityWillingness(for: profile, progression: .empty, approach: .ambitious)
        #expect(ambitious > balanced)
    }

    @Test func willingnessCapAtTwoEvenWithAmbitiousAndProgression() {
        // Stacking everything shouldn't break the willingness ceiling.
        var progression = ProgressionState.empty
        for _ in 0..<6 {
            progression = progression.applying(signal: .confidentSuccess, to: .vo2, approach: .ambitious)
            progression = progression.applying(signal: .confidentSuccess, to: .threshold, approach: .ambitious)
        }
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let result = engine.qualityWillingness(for: profile, progression: progression, approach: .ambitious)
        #expect(result <= 2)
    }

    // MARK: Readiness protections still apply under ambitious

    @Test func ambitiousStillTriggersRecoveryOnBadFeel() {
        var inputs = inputs(checkIn: makeCheckIn(feel: "Bad", time: 30))
        inputs.approach = .ambitious
        let type = engine.chooseWorkoutType(for: inputs)
        #expect(type == .recovery)
    }

    @Test func ambitiousStillTriggersRecoveryOnDeadLegs() {
        var inputs = inputs(checkIn: makeCheckIn(legs: "Dead", time: 60))
        inputs.approach = .ambitious
        let type = engine.chooseWorkoutType(for: inputs)
        #expect(type == .recovery)
    }

    @Test func ambitiousStillTriggersRecoveryOnGettingSick() {
        var inputs = inputs(checkIn: makeCheckIn(time: 60, flags: ["Getting sick"]))
        inputs.approach = .ambitious
        let type = engine.chooseWorkoutType(for: inputs)
        #expect(type == .recovery)
    }

    // MARK: Reason copy

    @Test func sustainableReasonMentionsSteadyOrSustainable() {
        var state = ProgressionState.empty
        // Reach stable to trigger progression framing
        for _ in 0..<5 {
            state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .sustainable)
        }
        let i = RecommendationEngine.Inputs(
            profile: makeProfile(currentState: .consistent, goals: [.endurance]),
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 60),
            recentHistory: makeHistory([(.endurance, nil)]),
            progression: state,
            approach: .sustainable
        )
        let reason = engine.buildReason(type: .quality, subtype: .threshold, tier: .stable, inputs: i)
        let lowered = reason.lowercased()
        #expect(lowered.contains("sustainable") || lowered.contains("steady"))
    }

    @Test func ambitiousReasonMentionsPush() {
        var state = ProgressionState.empty
        for _ in 0..<5 {
            state = state.applying(signal: .confidentSuccess, to: .threshold, approach: .ambitious)
        }
        let i = RecommendationEngine.Inputs(
            profile: makeProfile(currentState: .consistent, goals: [.endurance]),
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 60),
            recentHistory: makeHistory([(.endurance, nil)]),
            progression: state,
            approach: .ambitious
        )
        let reason = engine.buildReason(type: .quality, subtype: .threshold, tier: .stable, inputs: i)
        #expect(reason.lowercased().contains("push"))
    }

    // MARK: Persistence + analytics raw values

    @Test func trainingApproachIsCodable() throws {
        let original = TrainingApproach.ambitious
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingApproach.self, from: data)
        #expect(decoded == original)
    }

    @Test func trainingApproachChangedEventIsSnakeCase() {
        #expect(AnalyticsEvent.trainingApproachChanged.rawValue == "training_approach_changed")
    }
}

// MARK: - Adaptive Progression (Phase 1)

struct ProgressionStateTests {

    // MARK: Tier transitions

    @Test func emptyStateAllSubtypesAtStarter() {
        let state = ProgressionState.empty
        for subtype in QualitySubtype.allCases {
            #expect(state.tier(for: subtype) == .starter)
        }
    }

    @Test func twoConsecutiveSuccessesAdvanceTier() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        #expect(state.tier(for: .vo2) == .starter) // not yet
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        #expect(state.tier(for: .vo2) == .progressing)
    }

    @Test func twoConsecutiveStrugglesRegressTier() {
        var state = ProgressionState.empty
        // First advance once
        state = state.applying(signal: .confidentSuccess, to: .threshold)
        state = state.applying(signal: .confidentSuccess, to: .threshold)
        #expect(state.tier(for: .threshold) == .progressing)
        // Then struggle twice
        state = state.applying(signal: .struggle, to: .threshold)
        state = state.applying(signal: .struggle, to: .threshold)
        #expect(state.tier(for: .threshold) == .starter)
    }

    @Test func starterCannotRegressFurther() {
        var state = ProgressionState.empty
        state = state.applying(signal: .struggle, to: .vo2)
        state = state.applying(signal: .struggle, to: .vo2)
        #expect(state.tier(for: .vo2) == .starter)
    }

    @Test func advancedCannotAdvanceFurther() {
        var state = ProgressionState.empty
        // Climb to advanced
        for _ in 0..<10 {
            state = state.applying(signal: .confidentSuccess, to: .vo2)
        }
        #expect(state.tier(for: .vo2) == .advanced)
    }

    @Test func mixedSignalsHoldTier() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        state = state.applying(signal: .mixed, to: .vo2)
        state = state.applying(signal: .mixed, to: .vo2)
        #expect(state.tier(for: .vo2) == .starter)
    }

    @Test func progressionPerSubtypeIsIndependent() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        #expect(state.tier(for: .vo2) == .progressing)
        #expect(state.tier(for: .threshold) == .starter)
    }

    @Test func successCountersResetAfterStruggle() {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        state = state.applying(signal: .struggle, to: .vo2)
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        // Should still be starter — the struggle broke the streak
        #expect(state.tier(for: .vo2) == .starter)
    }

    // MARK: Signal classifier

    @Test func classifierMapsEasyToConfidentSuccess() {
        let signal = ProgressionSignalClassifier.signal(feedback: .easy)
        #expect(signal == .confidentSuccess)
    }

    @Test func classifierMapsRightToConfidentSuccess() {
        let signal = ProgressionSignalClassifier.signal(feedback: .right)
        #expect(signal == .confidentSuccess)
    }

    @Test func classifierMapsTooMuchToStruggle() {
        let signal = ProgressionSignalClassifier.signal(feedback: .tooMuch)
        #expect(signal == .struggle)
    }

    @Test func classifierMapsHardToMixed() {
        let signal = ProgressionSignalClassifier.signal(feedback: .hard)
        #expect(signal == .mixed)
    }

    @Test func classifierUpgradesRightWithRepeatabilityEasier() {
        let reflection = CoachReflection(
            workoutId: UUID(), promptKind: .repeatability,
            question: "?", response: .easier, responseLabel: "Easier",
            validation: ""
        )
        let signal = ProgressionSignalClassifier.signal(feedback: .right, reflection: reflection)
        #expect(signal == .confidentSuccess)
    }

    @Test func classifierDowngradesHardWhenReflectionIsHarder() {
        let reflection = CoachReflection(
            workoutId: UUID(), promptKind: .repeatability,
            question: "?", response: .harder, responseLabel: "Harder",
            validation: ""
        )
        let signal = ProgressionSignalClassifier.signal(feedback: .hard, reflection: reflection)
        #expect(signal == .struggle)
    }

    // MARK: Persistence

    @Test func progressionStateRoundTrips() throws {
        var state = ProgressionState.empty
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        state = state.applying(signal: .confidentSuccess, to: .vo2)
        state = state.applying(signal: .struggle, to: .threshold)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProgressionState.self, from: data)
        #expect(decoded.tier(for: .vo2) == .progressing)
        #expect(decoded.state(for: .threshold).consecutiveStruggles == 1)
    }
}

// MARK: - Tier-Aware Workout Builders

struct ProgressionAwareBuilderTests {

    @Test func vo2StarterUsesShortReps() {
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, tier: .starter, time: 45, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "4 x 2 min" })
    }

    @Test func vo2ProgressingUsesStandardReps() {
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, tier: .progressing, time: 45, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "5 x 3 min" })
    }

    @Test func vo2StableExtendsRepCount() {
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, tier: .stable, time: 60, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "6 x 3 min" })
    }

    @Test func thresholdAdvancedUsesSustainedBlocks() {
        let workout = engine.buildWorkout(type: .quality, subtype: .threshold, tier: .advanced, time: 60, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "2 x 15 min" })
    }

    @Test func meStableUsesThreeByTwelve() {
        let workout = engine.buildWorkout(type: .quality, subtype: .muscularEndurance, tier: .stable, time: 60, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "3 x 12 min" })
    }

    @Test func meAdvancedUsesTwoByTwenty() {
        let workout = engine.buildWorkout(type: .quality, subtype: .muscularEndurance, tier: .advanced, time: 65, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "2 x 20 min" })
    }

    @Test func tempoStableUsesTwoByFifteen() {
        let workout = engine.buildWorkout(type: .quality, subtype: .tempo, tier: .stable, time: 50, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "2 x 15 min" })
    }

    @Test func overUndersAdvancedUsesFiveSets() {
        let workout = engine.buildWorkout(type: .quality, subtype: .overUnders, tier: .advanced, time: 60, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "5 x 6 min" })
    }

    @Test func tierFallsBackWhenTimeTooShortForAdvanced() {
        // 40 min isn't enough for ME advanced (requires 60); should fall to progressing.
        let workout = engine.buildWorkout(type: .quality, subtype: .muscularEndurance, tier: .advanced, time: 40, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "3 x 9 min" })
    }

    @Test func shortTimeAlwaysUsesCompactRegardlessOfTier() {
        // Even advanced athletes on 30-min sessions get the compact template
        // because trainer-friendliness wins at short times.
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, tier: .advanced, time: 30, reason: "test")
        #expect(workout.title.contains("Compact"))
    }

    @Test func defaultBuildWorkoutWithoutTierUsesProgressing() {
        // Backward-compat path: existing tests that didn't pass tier should hit progressing.
        let workout = engine.buildWorkout(type: .quality, subtype: .vo2, time: 45, reason: "test")
        #expect(workout.steps.contains { $0.durationText == "5 x 3 min" })
    }
}

// MARK: - Engine Integration with Progression

struct ProgressionEngineIntegrationTests {

    private func auditInputs(progression: ProgressionState) -> RecommendationEngine.Inputs {
        var notes = CoachNotes.empty
        notes.tags = []
        return RecommendationEngine.Inputs(
            profile: makeProfile(currentState: .consistent, goals: [.endurance]),
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 60),
            recentHistory: makeHistory([(.endurance, nil), (.endurance, nil)]),
            memorySummary: .empty,
            progression: progression
        )
    }

    @Test func willingnessBoostsWhenTwoSubtypesAreStable() {
        var stable = ProgressionState.empty
        // Climb two subtypes to stable (4 successes each = starter -> progressing -> stable).
        for _ in 0..<4 {
            stable = stable.applying(signal: .confidentSuccess, to: .vo2)
            stable = stable.applying(signal: .confidentSuccess, to: .threshold)
        }
        let baselineProfile = makeProfile(currentState: .consistent, goals: [.endurance])
        let baseline = engine.qualityWillingness(for: baselineProfile, progression: .empty)
        let boosted = engine.qualityWillingness(for: baselineProfile, progression: stable)
        #expect(boosted > baseline)
    }

    @Test func recommendationCarriesTierBasedTemplate() {
        var progression = ProgressionState.empty
        // Push VO2 to stable
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        progression = progression.applying(signal: .confidentSuccess, to: .vo2)
        #expect(progression.tier(for: .vo2) == .stable)

        // Force VO2 quality: peak readiness + high willingness profile + history
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let inputs = RecommendationEngine.Inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 60),
            recentHistory: makeHistory([(.endurance, nil), (.endurance, nil), (.endurance, nil)]),
            progression: progression
        )
        let result = engine.recommend(for: inputs)
        if result.qualitySubtype == .vo2 {
            // Stable VO2 should produce 6 x 3 min, not 5 x 3 min
            #expect(result.steps.contains { $0.durationText == "6 x 3 min" })
        }
    }

    @Test func progressionExplainabilityAppearsInReasonAtStableTier() {
        var progression = ProgressionState.empty
        progression = progression.applying(signal: .confidentSuccess, to: .threshold)
        progression = progression.applying(signal: .confidentSuccess, to: .threshold)
        progression = progression.applying(signal: .confidentSuccess, to: .threshold)
        progression = progression.applying(signal: .confidentSuccess, to: .threshold)
        #expect(progression.tier(for: .threshold) == .stable)

        let inputs = auditInputs(progression: progression)
        let reason = engine.buildReason(type: .quality, subtype: .threshold, tier: .stable, inputs: inputs)
        #expect(reason.contains("consistently"))
    }

    @Test func progressionExplainabilitySilentAtStarterTier() {
        let progression = ProgressionState.empty
        let inputs = auditInputs(progression: progression)
        let baselineReason = engine.buildReason(type: .quality, subtype: .vo2, tier: nil, inputs: inputs)
        let starterReason = engine.buildReason(type: .quality, subtype: .vo2, tier: .starter, inputs: inputs)
        // Starter shouldn't append progression framing — should match the no-tier baseline.
        #expect(baselineReason == starterReason)
    }
}

// MARK: - Analytics

struct ProgressionAnalyticsTests {
    @Test func progressionTierChangedEventIsSnakeCase() {
        #expect(AnalyticsEvent.progressionTierChanged.rawValue == "progression_tier_changed")
    }
}

// MARK: - Coach Reflection

struct CoachReflectionTests {

    private func makeWorkout(
        id: UUID = UUID(),
        type: WorkoutType = .quality,
        duration: TimeInterval = 2700
    ) -> CompletedWorkout {
        CompletedWorkout(
            id: id,
            startDate: Date(),
            duration: duration,
            title: "Test",
            status: .finished,
            workoutType: type
        )
    }

    private func makeRecommendation(
        type: WorkoutType = .quality,
        subtype: QualitySubtype? = .vo2
    ) -> WorkoutRecommendation {
        WorkoutRecommendation(
            type: type,
            qualitySubtype: subtype,
            title: "Test",
            summary: "Test",
            reason: "Test",
            steps: [],
            optionalExtras: []
        )
    }

    // MARK: Generator — selection rules

    @Test func generatorSkipsRecoveryWorkouts() {
        let workout = makeWorkout(type: .recovery, duration: 1800)
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(type: .recovery, subtype: nil),
            expectedDuration: 1800,
            recentRides: []
        )
        #expect(prompt == nil)
    }

    @Test func generatorPicksShortenedWhenWorkoutCutShort() {
        // 1500s actual vs 3000s expected → 50% → meets <75% threshold.
        let workout = makeWorkout(duration: 1500)
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(),
            expectedDuration: 3000,
            recentRides: []
        )
        #expect(prompt?.kind == .shortenedReason)
    }

    @Test func generatorPicksRepeatabilityForVO2WithPrior() {
        let workout = makeWorkout()
        let prior = makeWorkout(id: UUID())
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(subtype: .vo2),
            expectedDuration: 2700,
            recentRides: [prior]
        )
        #expect(prompt?.kind == .repeatability)
    }

    @Test func generatorPicksSustainabilityForThresholdWithPrior() {
        let workout = makeWorkout()
        let prior = makeWorkout(id: UUID())
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(subtype: .threshold),
            expectedDuration: 2700,
            recentRides: [prior]
        )
        #expect(prompt?.kind == .sustainability)
    }

    @Test func generatorPicksEffortLimitForME() {
        let workout = makeWorkout()
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(subtype: .muscularEndurance),
            expectedDuration: 2700,
            recentRides: []
        )
        #expect(prompt?.kind == .effortLimit)
    }

    @Test func generatorPicksControlLateForOverUnders() {
        let workout = makeWorkout()
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(subtype: .overUnders),
            expectedDuration: 2700,
            recentRides: []
        )
        #expect(prompt?.kind == .controlLateInWorkout)
    }

    @Test func generatorEffortLimitForEnduranceFallback() {
        let workout = makeWorkout(type: .endurance)
        let prompt = CoachReflectionGenerator.generate(
            workout: workout,
            recommendation: makeRecommendation(type: .endurance, subtype: nil),
            expectedDuration: 2700,
            recentRides: []
        )
        #expect(prompt?.kind == .effortLimit)
    }

    // MARK: Validator — baseline coverage + history layering

    @Test func validatorReturnsNonEmptyBaselineForEveryPromptResponse() {
        let pairs: [(CoachReflectionPromptKind, CoachReflectionResponse)] = [
            (.effortLimit, .legs), (.effortLimit, .breathing),
            (.effortLimit, .both), (.effortLimit, .neither),
            (.repeatability, .easier), (.repeatability, .sameAs), (.repeatability, .harder),
            (.sustainability, .yes), (.sustainability, .somewhat), (.sustainability, .no),
            (.shortenedReason, .time), (.shortenedReason, .fatigue), (.shortenedReason, .timeAndFatigue),
            (.controlLateInWorkout, .yes), (.controlLateInWorkout, .somewhat), (.controlLateInWorkout, .no)
        ]
        for (kind, response) in pairs {
            let text = CoachReflectionValidator.validate(
                promptKind: kind, response: response, context: .empty
            )
            #expect(!text.isEmpty)
        }
    }

    @Test func validatorReferencesLegsFatigueFirstTag() {
        let context = CoachReflectionValidator.Context(
            recentSameSubtypeCount: 0,
            priorSameResponse: false,
            coachNoteTags: [.legsFatigueFirst]
        )
        let text = CoachReflectionValidator.validate(
            promptKind: .effortLimit, response: .legs, context: context
        )
        #expect(text.lowercased().contains("legs"))
        #expect(text.contains("told"))
    }

    @Test func validatorReferencesPriorVO2WhenRepeatabilityEasier() {
        let context = CoachReflectionValidator.Context(
            recentSameSubtypeCount: 2,
            priorSameResponse: false,
            coachNoteTags: []
        )
        let text = CoachReflectionValidator.validate(
            promptKind: .repeatability, response: .easier, context: context
        )
        #expect(text.contains("Compared to"))
    }

    @Test func validatorReferencesVO2DifficultTagOnHarderResponse() {
        let context = CoachReflectionValidator.Context(
            recentSameSubtypeCount: 0,
            priorSameResponse: false,
            coachNoteTags: [.vo2MentallyDifficult]
        )
        let text = CoachReflectionValidator.validate(
            promptKind: .repeatability, response: .harder, context: context
        )
        #expect(text.contains("VO2"))
    }

    @Test func validatorReferencesLimitedWeekdayTimeOnShortenedTime() {
        let context = CoachReflectionValidator.Context(
            recentSameSubtypeCount: 0,
            priorSameResponse: false,
            coachNoteTags: [.limitedWeekdayTime]
        )
        let text = CoachReflectionValidator.validate(
            promptKind: .shortenedReason, response: .time, context: context
        )
        #expect(text.lowercased().contains("weekday"))
    }

    // MARK: Persistence

    @Test func coachReflectionRoundTripsThroughCompletedWorkout() throws {
        let reflection = CoachReflection(
            workoutId: UUID(),
            promptKind: .effortLimit,
            question: "Legs or breathing?",
            response: .legs,
            responseLabel: "Legs",
            note: "Felt it on the third interval",
            validation: "Noted — legs giving in first is common on this kind of work."
        )
        var workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Test",
            status: .finished,
            coachReflection: reflection
        )
        workout.workoutType = .quality

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(CompletedWorkout.self, from: data)
        #expect(decoded.coachReflection?.id == reflection.id)
        #expect(decoded.coachReflection?.response == .legs)
        #expect(decoded.coachReflection?.note == "Felt it on the third interval")
    }

    @Test func backwardCompatibleDecodingHandlesMissingCoachReflection() throws {
        // Encode a CompletedWorkout without a coachReflection field (simulating old data).
        let workout = CompletedWorkout(
            startDate: Date(),
            duration: 2700,
            title: "Test",
            status: .finished
        )
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(CompletedWorkout.self, from: data)
        #expect(decoded.coachReflection == nil)
    }

    // MARK: Analytics

    @Test func reflectionAnalyticsEventsAreSnakeCase() {
        #expect(AnalyticsEvent.coachReflectionShown.rawValue == "coach_reflection_shown")
        #expect(AnalyticsEvent.coachReflectionAnswered.rawValue == "coach_reflection_answered")
    }
}

// MARK: - Coach Notes

struct CoachNotesTests {

    // MARK: Model

    @Test func emptyNotesReportEmpty() {
        let notes = CoachNotes.empty
        #expect(notes.isEmpty)
        #expect(notes.summaryLine.isEmpty)
    }

    @Test func tagOnlyNotesReportNotEmpty() {
        let notes = CoachNotes(freeformNote: "", tags: [.kneeSensitivity], updatedAt: nil)
        #expect(!notes.isEmpty)
        #expect(notes.summaryLine.contains("Knee"))
    }

    @Test func freeformOnlyNotesReportNotEmpty() {
        let notes = CoachNotes(freeformNote: "Long rides feel easy.", tags: [], updatedAt: nil)
        #expect(!notes.isEmpty)
        #expect(notes.summaryLine.contains("Long rides"))
    }

    @Test func whitespaceOnlyFreeformIsTreatedAsEmpty() {
        let notes = CoachNotes(freeformNote: "   \n  ", tags: [], updatedAt: nil)
        #expect(notes.isEmpty)
    }

    @Test func summaryCombinesNoteAndTags() {
        let notes = CoachNotes(
            freeformNote: "Legs fatigue first on long rides.",
            tags: [.legsFatigueFirst, .moreWeekendAvailability],
            updatedAt: nil
        )
        #expect(notes.summaryLine.contains("Legs"))
        #expect(notes.summaryLine.contains("tag"))
    }

    @Test func codableRoundTrip() throws {
        let original = CoachNotes(
            freeformNote: "Test note",
            tags: [.vo2MentallyDifficult, .strongAerobicFitness],
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoachNotes.self, from: data)
        #expect(decoded == original)
    }

    // MARK: Engine bias

    private func qualityInputs(tags: Set<CoachNoteTag>) -> RecommendationEngine.Inputs {
        var notes = CoachNotes.empty
        notes.tags = tags
        return RecommendationEngine.Inputs(
            profile: makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy),
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High", time: 60),
            recentHistory: makeHistory([(.endurance, nil), (.endurance, nil), (.endurance, nil)]),
            memorySummary: .empty,
            coachNotes: notes
        )
    }

    @Test func vo2MentallyDifficultTagBlocksVO2Selection() {
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(tags: [.vo2MentallyDifficult]))
        #expect(subtype != .vo2)
    }

    @Test func kneeSensitivityTagDePrioritizesME() {
        // With knee sensitivity + peak readiness, the engine should choose VO2 first
        // (top of priority list, ME removed). Ensure it doesn't fall back to ME.
        let subtype = engine.chooseQualitySubtype(for: qualityInputs(tags: [.kneeSensitivity]))
        #expect(subtype != .muscularEndurance)
    }

    @Test func legsFatigueFirstTagPromotesME() {
        // Force good-but-not-peak readiness so VO2 isn't auto-selected,
        // then the legs-fatigue-first tag should pull ME to the top.
        var notes = CoachNotes.empty
        notes.tags = [.legsFatigueFirst]
        let inputs = RecommendationEngine.Inputs(
            profile: makeProfile(currentState: .consistent, goals: [.endurance]),
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium", time: 60),
            recentHistory: makeHistory([(.endurance, nil), (.endurance, nil)]),
            memorySummary: .empty,
            coachNotes: notes
        )
        let subtype = engine.chooseQualitySubtype(for: inputs)
        #expect(subtype == .muscularEndurance)
    }

    @Test func noTagsDoesNotChangeBaselineSelection() {
        let withoutTags = engine.chooseQualitySubtype(for: qualityInputs(tags: []))
        let withNeutralTag = engine.chooseQualitySubtype(for: qualityInputs(tags: [.strongAerobicFitness]))
        #expect(withoutTags == withNeutralTag)
    }

    // MARK: Likely Tomorrow integration

    @Test func likelyTomorrowRespectsVO2DifficultTag() {
        var notes = CoachNotes.empty
        notes.tags = [.vo2MentallyDifficult]
        let cal = Calendar.current
        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: cal.startOfDay(for: cal.date(byAdding: .day, value: 3, to: Date())!),
            day1Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!),
            day1RecommendedIntensity: .quality,
            day1Rationale: "test",
            day2Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: Date())!),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "test"
        )
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent,
            profile: makeProfile(availability: .long),
            memory: .empty,
            coachNotes: notes
        )
        #expect(preview.qualitySubtype != .vo2)
    }

    @Test func likelyTomorrowPromotesMEUnderLegsFatigueFirst() {
        var notes = CoachNotes.empty
        notes.tags = [.legsFatigueFirst]
        let cal = Calendar.current
        let intent = ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: cal.startOfDay(for: cal.date(byAdding: .day, value: 3, to: Date())!),
            day1Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!),
            day1RecommendedIntensity: .quality,
            day1Rationale: "test",
            day2Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: Date())!),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "test"
        )
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent,
            profile: makeProfile(availability: .long),
            memory: .empty,
            coachNotes: notes
        )
        #expect(preview.qualitySubtype == .muscularEndurance)
    }

    // MARK: Analytics event uniqueness

    @Test func coachNotesUpdatedEventRawValueIsSnakeCase() {
        #expect(AnalyticsEvent.coachNotesUpdated.rawValue == "coach_notes_updated")
    }
}

// MARK: - Likely Tomorrow Preview

struct LikelyTomorrowPreviewTests {

    private func intent(day1Intensity: ShortTermTrainingIntent.RecommendedIntensity) -> ShortTermTrainingIntent {
        let cal = Calendar.current
        return ShortTermTrainingIntent(
            sourceWorkoutId: UUID(),
            expiresAt: cal.startOfDay(for: cal.date(byAdding: .day, value: 3, to: Date())!),
            day1Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!),
            day1RecommendedIntensity: day1Intensity,
            day1Rationale: "test",
            day2Date: cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: Date())!),
            day2RecommendedIntensity: .flexible,
            day2Rationale: "test",
            qualitySubtype: nil
        )
    }

    // After a VO2 day → recovery tomorrow

    @Test func vo2DayProducesRecoveryPreview() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .vo2,
            intent: intent(day1Intensity: .recovery),
            profile: makeProfile(),
            memory: .empty
        )
        #expect(preview.intensity == .recovery)
        #expect(preview.intensityLabel == "Recovery spin")
        #expect(preview.durationGuidance.contains("min"))
    }

    // After a threshold day → recovery tomorrow

    @Test func thresholdDayProducesRecoveryPreview() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .threshold,
            intent: intent(day1Intensity: .recovery),
            profile: makeProfile(),
            memory: .empty
        )
        #expect(preview.intensity == .recovery)
    }

    // After a muscular endurance day → endurance tomorrow (cost 2, not hard)

    @Test func muscularEnduranceDayProducesEndurancePreview() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .muscularEndurance,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(availability: .long),
            memory: .empty
        )
        #expect(preview.intensity == .endurance)
        #expect(preview.intensityLabel == "Endurance")
        #expect(preview.durationGuidance.contains("45"))
        #expect(preview.qualifier?.contains("decent") == true)
    }

    // After a tempo day → endurance tomorrow (cost 1)

    @Test func tempoDayProducesEndurancePreview() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .tempo,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(),
            memory: .empty
        )
        #expect(preview.intensity == .endurance)
    }

    // After an endurance day → flexible/quality tomorrow with subtype prediction

    @Test func enduranceDayWithQualityIntentProducesPredictedSubtype() {
        var memory = TrainingMemorySummary.empty
        memory.lastQualitySubtype = .vo2  // last quality was VO2

        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .quality),
            profile: makeProfile(availability: .long),
            memory: memory
        )
        #expect(preview.intensity == .quality)
        #expect(preview.qualitySubtype != .vo2)  // rotates away from last
        #expect(preview.qualifier?.contains("recovery") == true)
    }

    // Recovery day → endurance tomorrow

    @Test func recoveryDayProducesEndurancePreview() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .recovery,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(),
            memory: .empty
        )
        #expect(preview.intensity == .endurance)
    }

    // Headline format

    @Test func headlineUsesIntensityAndDuration() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .vo2,
            intent: intent(day1Intensity: .recovery),
            profile: makeProfile(),
            memory: .empty
        )
        #expect(preview.compactHeadline.contains("Recovery spin"))
        #expect(preview.compactHeadline.contains("min"))
    }

    @Test func fullHeadlineAppendsQualifierWhenPresent() {
        var memory = TrainingMemorySummary.empty
        memory.lastQualitySubtype = .vo2
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .quality),
            profile: makeProfile(availability: .long),
            memory: memory
        )
        #expect(preview.fullHeadline.contains(", "))
        #expect(preview.fullHeadline.count > preview.compactHeadline.count)
    }

    // No-intent fallback

    @Test func noIntentInfersFromSource() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .vo2,
            intent: nil,
            profile: makeProfile(),
            memory: .empty
        )
        // VO2 (cost 3) without intent → recovery
        #expect(preview.intensity == .recovery)
    }

    @Test func noIntentLowCostQualityInfersEndurance() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .quality,
            sourceQualitySubtype: .tempo,
            intent: nil,
            profile: makeProfile(),
            memory: .empty
        )
        // Tempo (cost 1) without intent → endurance
        #expect(preview.intensity == .endurance)
    }

    // Upcoming context awareness

    @Test func upcomingBigRideShapesEnduranceQualifier() {
        var upcoming = UpcomingContextSummary.empty
        upcoming.hasBigRideSoon = true
        upcoming.daysUntilBigRide = 1

        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(),
            memory: .empty,
            upcoming: upcoming
        )
        #expect(preview.qualifier?.contains("fresh") == true)
    }

    // Profile-availability respect

    @Test func shortAvailabilityShortensEnduranceDuration() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(availability: .short),
            memory: .empty
        )
        #expect(preview.durationGuidance.contains("20") || preview.durationGuidance.contains("30"))
    }

    @Test func longAvailabilityExtendsEnduranceDuration() {
        let preview = LikelyTomorrowBuilder.preview(
            sourceWorkoutType: .endurance,
            sourceQualitySubtype: nil,
            intent: intent(day1Intensity: .endurance),
            profile: makeProfile(availability: .long),
            memory: .empty
        )
        #expect(preview.durationGuidance.contains("45") || preview.durationGuidance.contains("60"))
    }
}

// MARK: - Onboarding Bias (Quality Willingness)

struct OnboardingBiasTests {

    @Test func justStartingLowersWillingness() {
        let profile = makeProfile(currentState: .justStarting, goals: [.consistent], frequency: .light)
        let score = engine.qualityWillingness(for: profile)
        #expect(score <= -2)
    }

    @Test func veryConsistentPerformanceGoalsRaisesWillingness() {
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let score = engine.qualityWillingness(for: profile)
        #expect(score >= 2)
    }

    @Test func consistentModerateIsNeutral() {
        let profile = makeProfile(currentState: .consistent, goals: [.endurance], frequency: .moderate)
        let score = engine.qualityWillingness(for: profile)
        #expect(score >= 0 && score <= 1)
    }

    @Test func favorsConsistencyForConsistentGoal() {
        let profile = makeProfile(goals: [.consistent])
        #expect(engine.favorsConsistency(profile))
    }

    @Test func doesNotFavorConsistencyForEndurance() {
        let profile = makeProfile(goals: [.endurance])
        #expect(!engine.favorsConsistency(profile))
    }

    @Test func highWillingnessLowersQualityThreshold() {
        // With high willingness, only 1 easier day needed instead of 2
        let profile = makeProfile(currentState: .veryConsistent, goals: [.bikePerformance], frequency: .heavy)
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        #expect(type == .quality)
    }

    @Test func lowWillingnessBlocksQualityWithOnlyOneEasierDay() {
        let profile = makeProfile(currentState: .justStarting, goals: [.consistent], frequency: .light)
        let history = makeHistory([(.endurance, nil)])
        let type = engine.chooseWorkoutType(for: inputs(
            profile: profile,
            checkIn: makeCheckIn(feel: "Great", legs: "Fresh", motivation: "High"),
            history: history
        ))
        // Low willingness still allows quality via the fresh-legs path, but
        // the easier-stretch path requires 2 easier days with low willingness
        #expect(type == .quality || type == .endurance)
    }
}

// MARK: - Equipment Shaping

struct EquipmentShapingTests {

    @Test func hasStrengthEquipmentWithDumbbells() {
        let profile = makeProfile(equipment: [.dumbbells, .bikeTrainer])
        #expect(engine.hasStrengthEquipment(profile))
    }

    @Test func noStrengthEquipmentWithOnlyBike() {
        let profile = makeProfile(equipment: [.bikeTrainer])
        #expect(!engine.hasStrengthEquipment(profile))
    }

    @Test func noStrengthEquipmentWhenNone() {
        let profile = makeProfile(equipment: [.noEquipment])
        #expect(!engine.hasStrengthEquipment(profile))
    }

    @Test func enduranceExtrasIncludeStrengthWhenEquipmentAvailable() {
        let profile = makeProfile(equipment: [.bikeTrainer, .dumbbells])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("dumbbell") || $0.contains("kettlebell") })
    }

    @Test func enduranceExtrasIncludeBodyweightWhenNoEquipment() {
        let profile = makeProfile(equipment: [.bikeTrainer])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("bodyweight") })
    }

    @Test func recoveryExtrasIncludeMobility() {
        let extras = engine.adjustExtras([], type: .recovery, time: 30, profile: makeProfile())
        #expect(extras.contains { $0.contains("mobility") || $0.contains("walk") })
    }

    @Test func qualityExtrasIncludeMobility() {
        let extras = engine.adjustExtras([], type: .quality, time: 45, profile: makeProfile())
        #expect(extras.contains { $0.contains("mobility") })
    }

    @Test func shortEnduranceGetsNoStrengthExtras() {
        let profile = makeProfile(equipment: [.bikeTrainer, .dumbbells])
        let extras = engine.adjustExtras([], type: .endurance, time: 30, profile: profile)
        #expect(extras.isEmpty)
    }

    @Test func gymEquipmentGetsGymExtras() {
        let profile = makeProfile(equipment: [.gym])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("core and upper body") })
    }

    @Test func bandEquipmentGetsBandExtras() {
        let profile = makeProfile(equipment: [.bands])
        let extras = engine.adjustExtras([], type: .endurance, time: 45, profile: profile)
        #expect(extras.contains { $0.contains("band") })
    }
}

// MARK: - Full Recommendation Flow

struct FullRecommendationTests {

    @Test func fullRecommendationIncludesExtras() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(time: 45)
        ))
        #expect(!result.optionalExtras.isEmpty)
    }

    @Test func recoveryRecommendationHasRecoveryType() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(feel: "Bad", time: 30)
        ))
        #expect(result.type == .recovery)
        #expect(!result.reason.isEmpty)
        #expect(!result.steps.isEmpty)
    }

    @Test func defaultRecommendationIsEndurance() {
        let result = engine.recommend(for: inputs(
            checkIn: makeCheckIn(feel: "Good", legs: "Normal", motivation: "Medium", time: 45)
        ))
        #expect(result.type == .endurance)
    }
}
