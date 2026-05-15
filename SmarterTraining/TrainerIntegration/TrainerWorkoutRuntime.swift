import Foundation
import Observation

enum WorkoutRuntimeState {
    case ready
    case running
    case paused
    case finished
}

@Observable
final class TrainerWorkoutRuntime {

    let steps: [TrainerWorkoutStep]
    private(set) var currentStepIndex: Int = 0
    private(set) var stepElapsed: TimeInterval = 0
    private(set) var totalElapsed: TimeInterval = 0
    private(set) var state: WorkoutRuntimeState = .ready
    private(set) var samples: [TrainerMetrics] = []
    private(set) var startDate: Date?

    // ERG
    var ergEnabled: Bool = false
    private(set) var ergState: ERGState = .off
    private var ergAttemptDate: Date?
    private static let ergTimeout: TimeInterval = 8

    private var timer: Timer?
    private weak var trainerManager: FTMSManager?
    private var lastTargetSent: Int?

    init(steps: [TrainerWorkoutStep], trainerManager: FTMSManager?) {
        self.steps = steps
        self.trainerManager = trainerManager
    }

    // MARK: - Computed

    var currentStep: TrainerWorkoutStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var nextStep: TrainerWorkoutStep? {
        let next = currentStepIndex + 1
        guard next < steps.count else { return nil }
        return steps[next]
    }

    var stepRemaining: TimeInterval {
        guard let step = currentStep else { return 0 }
        return max(0, step.duration - stepElapsed)
    }

    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }

    var targetPower: Int? {
        currentStep?.targetPower
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(1.0, totalElapsed / totalDuration)
    }

    // MARK: - Workout Control

    func start() {
        guard state == .ready || state == .paused else { return }
        if startDate == nil { startDate = Date() }
        state = .running
        attemptERGIfEnabled()
        trySendERGTarget()
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
        if ergState == .active {
            trainerManager?.send(.pause)
        }
    }

    func resume() {
        guard state == .paused else { return }
        start()
    }

    func finish() {
        state = .finished
        stopTimer()
        if ergState == .active {
            trainerManager?.send(.stop)
        }
        ergState = ergEnabled ? ergState : .off
        lastTargetSent = nil
    }

    // MARK: - ERG

    private func attemptERGIfEnabled() {
        guard ergEnabled else {
            ergState = .off
            return
        }
        guard let manager = trainerManager else {
            transitionERG(to: .failed("No trainer connection"))
            return
        }
        if !manager.hasControlPoint {
            transitionERG(to: .unsupported)
            return
        }
        if !manager.supportsERG {
            transitionERG(to: .unsupported)
            return
        }
        if manager.controlAcquired {
            transitionERG(to: .active)
            return
        }

        transitionERG(to: .enabling)
        ergAttemptDate = Date()
        manager.send(.requestControl)
    }

    private func updateERGState() {
        guard ergEnabled, ergState == .enabling else { return }
        guard let manager = trainerManager else {
            transitionERG(to: .failed("Trainer disconnected"))
            return
        }

        if manager.controlAcquired {
            transitionERG(to: .active)
            trySendERGTarget()
            return
        }

        if let attempt = ergAttemptDate, Date().timeIntervalSince(attempt) > Self.ergTimeout {
            transitionERG(to: .failed("Could not acquire trainer control"))
        }
    }

    private func trySendERGTarget() {
        guard ergEnabled, ergState == .active || ergState == .enabling else { return }
        guard let manager = trainerManager else { return }
        guard let watts = targetPower else { return }

        if ergState == .enabling && !manager.controlAcquired {
            return
        }

        guard watts != lastTargetSent else { return }
        let clamped = max(0, min(Int16.max, Int16(watts)))
        manager.send(.setTargetPower(watts: clamped))
        lastTargetSent = watts

        #if DEBUG
        print("[ERG] Target power set to \(watts)W")
        #endif
    }

    private func transitionERG(to newState: ERGState) {
        guard ergState != newState else { return }
        #if DEBUG
        print("[ERG] \(ergState.label) → \(newState.label)")
        #endif
        ergState = newState
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running else { return }

        stepElapsed += 1
        totalElapsed += 1
        captureSample()
        updateERGState()

        if let step = currentStep, stepElapsed >= step.duration {
            advanceStep()
        }
    }

    private func advanceStep() {
        let nextIndex = currentStepIndex + 1
        if nextIndex >= steps.count {
            finish()
            return
        }
        currentStepIndex = nextIndex
        stepElapsed = 0
        lastTargetSent = nil
        trySendERGTarget()
    }

    private func captureSample() {
        guard let manager = trainerManager else { return }
        let m = manager.metrics
        guard m.timestamp != .distantPast else { return }
        samples.append(m)
    }
}
