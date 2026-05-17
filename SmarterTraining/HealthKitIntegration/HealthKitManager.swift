import Foundation
import HealthKit

@Observable
final class HealthKitManager {

    private(set) var currentHeartRate: Int?
    private(set) var collectedBPMs: [Int] = []

    private let healthStore: HKHealthStore?
    private var observationTask: Task<Void, Never>?

    private let heartRateType = HKQuantityType(.heartRate)
    private let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
    }

    var isAvailable: Bool {
        healthStore != nil
    }

    func requestAuthorization() async {
        guard let healthStore else { return }

        AnalyticsService.shared.track(.healthkitPermissionRequested)

        let typesToShare: Set<HKSampleType> = [
            .workoutType(),
            heartRateType
        ]
        let typesToRead: Set<HKObjectType> = [
            heartRateType
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            ErrorLogger.log(.healthkit, message: error.localizedDescription)
        }
    }

    // MARK: - Live Heart Rate

    func startHeartRateObservation() {
        guard let healthStore else { return }
        stopHeartRateObservation()
        collectedBPMs = []

        let observationStart = Date()

        observationTask = Task {
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.quantitySample(type: heartRateType)],
                anchor: nil
            )
            let results = descriptor.results(for: healthStore)

            do {
                for try await result in results {
                    guard !Task.isCancelled else { break }
                    let recent = result.addedSamples
                        .filter { $0.endDate >= observationStart }
                        .sorted { $0.endDate > $1.endDate }

                    for sample in recent {
                        collectedBPMs.append(Int(sample.quantity.doubleValue(for: heartRateUnit)))
                    }
                    if let latest = recent.first {
                        currentHeartRate = Int(latest.quantity.doubleValue(for: heartRateUnit))
                    }
                }
            } catch {
                // Query cancelled or permission denied
            }
        }
    }

    func stopHeartRateObservation() {
        observationTask?.cancel()
        observationTask = nil
        currentHeartRate = nil
    }

    // MARK: - Save Workout

    func saveWorkout(
        startDate: Date,
        endDate: Date,
        trainerSamples: [TrainerMetrics]
    ) async -> (savedUUID: UUID?, failureReason: String?) {
        guard let healthStore else {
            return (nil, "HealthKit not available on this device")
        }

        AnalyticsService.shared.track(.healthkitWorkoutSaveStarted)

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: config,
            device: nil
        )

        do {
            try await builder.beginCollection(at: startDate)

            let hrSamples: [HKQuantitySample] = trainerSamples.compactMap { sample in
                guard let hr = sample.heartRate, hr > 0 else { return nil }
                let quantity = HKQuantity(unit: heartRateUnit, doubleValue: Double(hr))
                return HKQuantitySample(
                    type: heartRateType,
                    quantity: quantity,
                    start: sample.timestamp,
                    end: sample.timestamp
                )
            }

            if !hrSamples.isEmpty {
                try await builder.addSamples(hrSamples)
            }

            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()

            AnalyticsService.shared.track(.healthkitWorkoutSaveSucceeded, properties: [
                "hr_sample_count": AnalyticsProperties.countBucket(hrSamples.count)
            ])
            return (workout?.uuid, nil)
        } catch {
            AnalyticsService.shared.track(.healthkitWorkoutSaveFailed, properties: [
                "error": AnalyticsProperties.sanitizeMessage(error.localizedDescription)
            ])
            ErrorLogger.log(.healthkit, message: error.localizedDescription)
            return (nil, error.localizedDescription)
        }
    }
}
