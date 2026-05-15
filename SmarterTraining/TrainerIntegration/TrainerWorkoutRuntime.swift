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
    var ergEnabled: Bool = false {
        didSet {
            if ergEnabled && state == .running {
                attemptERGIfEnabled()
                trySendERGTarget(force: true)
            } else if !ergEnabled {
                if ergState == .active {
                    trainerManager?.send(.stop)
                }
                transitionERG(to: .off)
                rampController.completeRamp()
                lastTargetSent = nil
            }
        }
    }
    private(set) var ergState: ERGState = .off
    private var ergAttemptDate: Date?
    private static let ergTimeout: TimeInterval = 8

    // Ramp
    private(set) var rampController = ERGRampController()
    private var lastRampCommandDate: Date?

    // Display
    private(set) var powerSmoother = PowerSmoother()
    private(set) var cadenceGuidance = CadenceGuidance()
    private(set) var cadenceStatus: CadenceGuidance.Status = .ok

    var smoothedPower: Int? {
        powerSmoother.smoothed()
    }

    var displayTargetPower: Int? {
        if rampController.isRamping, let ramped = rampController.currentTarget() {
            return ramped
        }
        return targetPower
    }

    private var timer: Timer?
    private weak var trainerManager: FTMSManager?
    private weak var hrmManager: HRMManager?
    private var lastTargetSent: Int?

    init(steps: [TrainerWorkoutStep], trainerManager: FTMSManager?, hrmManager: HRMManager? = nil) {
        self.steps = steps
        self.trainerManager = trainerManager
        self.hrmManager = hrmManager
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
        trySendERGTarget(force: true)
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
        rampController.completeRamp()
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
            trySendERGTarget(force: true)
            return
        }

        if let attempt = ergAttemptDate, Date().timeIntervalSince(attempt) > Self.ergTimeout {
            transitionERG(to: .failed("Could not acquire trainer control"))
        }
    }

    private func trySendERGTarget(force: Bool = false) {
        guard ergEnabled, ergState == .active || ergState == .enabling else { return }
        guard let manager = trainerManager else { return }
        guard let watts = targetPower else { return }

        if ergState == .enabling && !manager.controlAcquired {
            return
        }

        if !force && watts == lastTargetSent && !rampController.isRamping {
            return
        }

        let commandWatts: Int
        if rampController.isRamping, let ramped = rampController.currentTarget() {
            commandWatts = ramped
        } else {
            commandWatts = watts
        }

        let clamped = max(0, min(Int16.max, Int16(commandWatts)))
        manager.send(.setTargetPower(watts: clamped))
        lastTargetSent = rampController.isRamping ? nil : watts

        #if DEBUG
        if rampController.isRamping {
            print("[ERG] Ramp target: \(commandWatts)W (final: \(watts)W)")
        } else {
            print("[ERG] Target power set to \(watts)W")
        }
        #endif
    }

    private func transitionERG(to newState: ERGState) {
        guard ergState != newState else { return }
        #if DEBUG
        print("[ERG] \(ergState.label) \u{2192} \(newState.label)")
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
        updateRamp()
        updateCadence()

        if let step = currentStep, stepElapsed >= step.duration {
            advanceStep()
        }
    }

    private func advanceStep() {
        let previousTarget = currentStep?.targetPower
        let nextIndex = currentStepIndex + 1
        if nextIndex >= steps.count {
            finish()
            return
        }
        currentStepIndex = nextIndex
        stepElapsed = 0
        cadenceGuidance.reset()
        cadenceStatus = .ok

        if let prev = previousTarget, let next = currentStep?.targetPower {
            rampController.beginRamp(from: prev, to: next)
            lastRampCommandDate = nil
        }
        lastTargetSent = nil
        trySendERGTarget(force: true)
    }

    // MARK: - Ramp

    private func updateRamp() {
        guard rampController.isRamping else { return }
        guard ergEnabled, ergState == .active else {
            rampController.completeRamp()
            return
        }

        let now = Date()
        let shouldSend = lastRampCommandDate == nil ||
            now.timeIntervalSince(lastRampCommandDate!) >= rampController.commandInterval

        if shouldSend {
            trySendERGTarget(force: true)
            lastRampCommandDate = now
        }

        if !rampController.isRamping {
            rampController.completeRamp()
            lastRampCommandDate = nil
        }
    }

    // MARK: - Display Helpers

    private func updateCadence() {
        guard let step = currentStep else { return }
        cadenceStatus = cadenceGuidance.update(
            cadence: trainerManager?.metrics.cadence,
            stepRole: step.role,
            stepElapsed: stepElapsed
        )
    }

    private func captureSample() {
        guard let manager = trainerManager else { return }
        var m = manager.metrics
        guard m.timestamp != .distantPast else { return }

        if (m.heartRate == nil || m.heartRate == 0), let hrmHR = hrmManager?.heartRate, hrmHR > 0 {
            m.heartRate = hrmHR
        }
        samples.append(m)

        if let watts = m.power {
            powerSmoother.add(watts, at: m.timestamp)
        }
    }
}
