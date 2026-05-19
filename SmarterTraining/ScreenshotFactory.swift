#if DEBUG
import Foundation

/// Deterministic factories for screenshot / demo state.
///
/// These build *real* production models — `CompletedWorkout`, `WorkoutHistoryEntry`,
/// `ProgressionState`, `CoachReflection` — so the real app UI renders naturally
/// without screenshot-specific view code.
///
/// All entry points are seeded with stable parameters so the same launch argument
/// reproduces the same visual state across runs.
enum ScreenshotFactory {

    // MARK: - Profile

    static func powerAthleteProfile(name: String = "Alex") -> UserProfile {
        UserProfile(
            name: name,
            currentState: .veryConsistent,
            goals: [.bikePerformance, .endurance],
            typicalAvailability: .long,
            trainingFrequency: .heavy,
            equipment: [.bikeTrainer, .dumbbells],
            ftp: 240
        )
    }

    static func consistentEnduranceProfile(name: String = "Sam") -> UserProfile {
        UserProfile(
            name: name,
            currentState: .consistent,
            goals: [.endurance, .healthier],
            typicalAvailability: .medium,
            trainingFrequency: .moderate,
            equipment: [.bikeTrainer],
            ftp: 215
        )
    }

    // MARK: - Check-ins

    static func freshCheckIn(timeAvailable: Int = 60) -> CheckIn {
        CheckIn(
            overallFeel: "Great",
            legs: "Fresh",
            motivation: "High",
            timeAvailable: timeAvailable,
            contextFlags: []
        )
    }

    static func moderateCheckIn(timeAvailable: Int = 45) -> CheckIn {
        CheckIn(
            overallFeel: "Good",
            legs: "Normal",
            motivation: "Medium",
            timeAvailable: timeAvailable,
            contextFlags: []
        )
    }

    static func lowReadinessCheckIn(timeAvailable: Int = 30) -> CheckIn {
        CheckIn(
            overallFeel: "Okay",
            legs: "Heavy",
            motivation: "Low",
            timeAvailable: timeAvailable,
            contextFlags: ["Poor sleep"]
        )
    }

    // MARK: - History

    /// A believable 7-day rolling window of completed workouts. Mix of endurance,
    /// recovery, and one prior quality session so engine + memory work as in prod.
    static func realisticRecentHistory(referenceDate: Date = Date()) -> [WorkoutHistoryEntry] {
        let cal = Calendar.current
        func date(daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
        }
        return [
            entry(daysAgo: 6, title: "Endurance Ride", type: .endurance, feedback: .right, referenceDate: referenceDate),
            entry(daysAgo: 5, title: "Recovery Day", type: .recovery, feedback: .easy, referenceDate: referenceDate),
            entry(daysAgo: 4, title: "Threshold Intervals", type: .quality, feedback: .right, subtype: .threshold, referenceDate: referenceDate),
            entry(daysAgo: 3, title: "Endurance Ride", type: .endurance, feedback: .right, referenceDate: referenceDate),
            entry(daysAgo: 2, title: "Recovery Day", type: .recovery, feedback: .easy, referenceDate: referenceDate),
            entry(daysAgo: 1, title: "Endurance Ride", type: .endurance, feedback: .right, referenceDate: referenceDate)
        ]
    }

    private static func entry(daysAgo: Int, title: String, type: WorkoutType, feedback: WorkoutFeedback, subtype: QualitySubtype? = nil, referenceDate: Date) -> WorkoutHistoryEntry {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
        return WorkoutHistoryEntry(
            date: date,
            title: title,
            type: type,
            feedback: feedback,
            feedbackAt: date,
            qualitySubtype: subtype
        )
    }

    // MARK: - Progression State

    /// A progression state where the athlete is stable in threshold and progressing in ME.
    /// Drives the engine into "extend the work" copy.
    static func stableProgression() -> ProgressionState {
        var state = ProgressionState.empty
        // Stable in threshold (4 confident successes)
        for _ in 0..<4 {
            state = state.applying(signal: .confidentSuccess, to: .threshold)
        }
        // Progressing in ME (2 successes)
        for _ in 0..<2 {
            state = state.applying(signal: .confidentSuccess, to: .muscularEndurance)
        }
        return state
    }

    static func advancedProgression() -> ProgressionState {
        var state = ProgressionState.empty
        for _ in 0..<8 {
            state = state.applying(signal: .confidentSuccess, to: .threshold)
        }
        for _ in 0..<4 {
            state = state.applying(signal: .confidentSuccess, to: .vo2)
        }
        return state
    }

    // MARK: - Coach Notes

    static func realisticCoachNotes() -> CoachNotes {
        CoachNotes(
            freeformNote: "Cardio feels strong but my legs fatigue first on long rides. More time on weekends.",
            tags: [.legsFatigueFirst, .moreWeekendAvailability],
            updatedAt: Date()
        )
    }

    // MARK: - Completed Ride

    /// A finished threshold ride from earlier today, with realistic samples and a
    /// saved coach reflection. Drives the post-workout / completed hero card path.
    static func completedThresholdRide(
        startedAt: Date,
        ftp: Int,
        title: String = "Threshold Intervals",
        subtype: QualitySubtype? = .threshold,
        reflection: CoachReflection? = nil
    ) -> CompletedWorkout {
        let duration: TimeInterval = 45 * 60
        let samples = SyntheticSamples.threshold(startedAt: startedAt, durationSeconds: duration, ftp: ftp)
        let powers = samples.compactMap(\.power).filter { $0 > 0 }
        let heartRates = samples.compactMap(\.heartRate).filter { $0 > 0 }
        let cadences = samples.compactMap(\.cadence).filter { $0 > 0 }
        return CompletedWorkout(
            startDate: startedAt,
            duration: duration,
            title: title,
            samples: samples,
            status: .finished,
            isPostedToStrava: false,
            updatedAt: startedAt.addingTimeInterval(duration + 60),
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count,
            maxHeartRate: heartRates.max(),
            workoutFeedback: .right,
            perceivedEffort: 7,
            postWorkoutNote: "Felt sustained throughout. Last interval was tough but stayed steady.",
            coachReflection: reflection,
            averagePower: powers.isEmpty ? nil : powers.reduce(0, +) / powers.count,
            maxPower: powers.max(),
            averageCadence: cadences.isEmpty ? nil : Int(Double(cadences.reduce(0, +)) / Double(cadences.count)),
            ergWasEnabled: true,
            workoutType: .quality
        )
    }

    /// A finished muscular endurance ride — slightly different shape, used by the
    /// adaptive-coaching scenario.
    static func completedMuscularEnduranceRide(
        startedAt: Date,
        ftp: Int
    ) -> CompletedWorkout {
        let duration: TimeInterval = 60 * 60
        let samples = SyntheticSamples.muscularEndurance(startedAt: startedAt, durationSeconds: duration, ftp: ftp)
        let powers = samples.compactMap(\.power).filter { $0 > 0 }
        let heartRates = samples.compactMap(\.heartRate).filter { $0 > 0 }
        return CompletedWorkout(
            startDate: startedAt,
            duration: duration,
            title: "Muscular Endurance",
            samples: samples,
            status: .finished,
            updatedAt: startedAt.addingTimeInterval(duration + 60),
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count,
            maxHeartRate: heartRates.max(),
            workoutFeedback: .right,
            perceivedEffort: 6,
            postWorkoutNote: "Sustained pressure landed well. Legs gave first as expected.",
            averagePower: powers.isEmpty ? nil : powers.reduce(0, +) / powers.count,
            maxPower: powers.max(),
            ergWasEnabled: true,
            workoutType: .quality
        )
    }

    // MARK: - Coach Reflection

    static func savedReflection(for workoutId: UUID) -> CoachReflection {
        CoachReflection(
            workoutId: workoutId,
            promptKind: .sustainability,
            question: "Did the effort feel sustainable through the set?",
            response: .yes,
            responseLabel: "Yes",
            note: nil,
            validation: "Sustainable effort at this intensity is exactly what builds the ceiling. That's a step forward compared to the last few sessions of this kind.",
            createdAt: Date()
        )
    }
}

// MARK: - Synthetic Samples

/// Generates realistic-looking telemetry. Deterministic given the start time and
/// FTP so screenshots reproduce identically across runs.
private enum SyntheticSamples {

    /// 1 Hz sampling.
    private static let sampleHz: TimeInterval = 1.0

    /// Threshold session: 10 min warmup -> 4x5 min @ 95–100% FTP / 3 min easy -> 10 min cooldown.
    static func threshold(startedAt: Date, durationSeconds: TimeInterval, ftp: Int) -> [TrainerMetrics] {
        let warmup: Range<TimeInterval> = 0..<600
        let cooldown: Range<TimeInterval> = (durationSeconds - 300)..<durationSeconds

        // Intervals: 4 x (5 min on, 3 min easy)
        var blocks: [(range: Range<TimeInterval>, kind: BlockKind)] = []
        blocks.append((warmup, .warmup))
        var t = warmup.upperBound
        for _ in 0..<4 {
            blocks.append((t..<(t + 300), .interval))
            t += 300
            blocks.append((t..<(t + 180), .recovery))
            t += 180
        }
        blocks.append((cooldown, .cooldown))

        return buildSamples(
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            ftp: ftp,
            intervalPercent: 0.975,  // mid of 95–100%
            recoveryPercent: 0.55,
            blocks: blocks
        )
    }

    /// ME session: 10 min warmup -> 3x12 min @ 88–95% FTP / 4 min easy -> 8 min cooldown.
    static func muscularEndurance(startedAt: Date, durationSeconds: TimeInterval, ftp: Int) -> [TrainerMetrics] {
        let warmup: Range<TimeInterval> = 0..<600
        let cooldown: Range<TimeInterval> = (durationSeconds - 480)..<durationSeconds

        var blocks: [(range: Range<TimeInterval>, kind: BlockKind)] = [(warmup, .warmup)]
        var t = warmup.upperBound
        for _ in 0..<3 {
            blocks.append((t..<(t + 720), .interval))
            t += 720
            blocks.append((t..<(t + 240), .recovery))
            t += 240
        }
        blocks.append((cooldown, .cooldown))

        return buildSamples(
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            ftp: ftp,
            intervalPercent: 0.915,
            recoveryPercent: 0.55,
            blocks: blocks
        )
    }

    private enum BlockKind { case warmup, interval, recovery, cooldown }

    private static func buildSamples(
        startedAt: Date,
        durationSeconds: TimeInterval,
        ftp: Int,
        intervalPercent: Double,
        recoveryPercent: Double,
        blocks: [(range: Range<TimeInterval>, kind: BlockKind)]
    ) -> [TrainerMetrics] {
        var samples: [TrainerMetrics] = []
        var hrFloor: Double = 110
        var hrCeil: Double = 168
        let intervalWatts = Int(Double(ftp) * intervalPercent)
        let recoveryWatts = Int(Double(ftp) * recoveryPercent)

        let totalSeconds = Int(durationSeconds)
        for second in 0..<totalSeconds {
            let t = TimeInterval(second)
            let kind: BlockKind = blocks.first(where: { $0.range.contains(t) })?.kind ?? .cooldown
            let timestamp = startedAt.addingTimeInterval(t)

            let power: Int
            let cadence: Double
            let heartRate: Int

            // Use a small deterministic wobble seeded by second.
            let wobble = Double(((second * 9301) + 49297) % 233) / 233.0  // 0..1
            let noise = (wobble - 0.5) * 2.0  // -1..1

            switch kind {
            case .warmup:
                let progress = t / 600.0
                power = Int(Double(ftp) * (0.40 + 0.30 * progress) + noise * 6)
                heartRate = Int(110 + 40 * progress + noise * 3)
                cadence = 84 + noise * 3
            case .interval:
                power = intervalWatts + Int(noise * 8)
                // Slight upward HR drift across the workout (3 bpm per interval roughly)
                hrCeil = min(180, hrCeil + 0.005)
                heartRate = Int(hrCeil + noise * 2)
                cadence = 90 + noise * 2
            case .recovery:
                power = recoveryWatts + Int(noise * 5)
                hrFloor = max(125, hrFloor - 0.01)
                heartRate = Int(hrFloor + 20 + noise * 3)
                cadence = 85 + noise * 3
            case .cooldown:
                let cooldownStart = blocks.last?.range.lowerBound ?? (durationSeconds - 300)
                let cooldownLen = max(60, durationSeconds - cooldownStart)
                let progress = (t - cooldownStart) / cooldownLen
                power = Int(Double(ftp) * (0.55 - 0.15 * progress) + noise * 4)
                heartRate = Int(150 - 30 * progress + noise * 3)
                cadence = 82 + noise * 3
            }

            samples.append(TrainerMetrics(
                power: max(0, power),
                cadence: max(0, cadence),
                speed: nil,
                heartRate: max(0, heartRate),
                timestamp: timestamp
            ))
        }
        return samples
    }
}
#endif
