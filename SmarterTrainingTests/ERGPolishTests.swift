import Foundation
import Testing
@testable import SmarterTraining

// MARK: - ERGRampController Tests

struct ERGRampControllerTests {

    @Test func smallDeltaSkipsRamp() {
        var ramp = ERGRampController()
        ramp.beginRamp(from: 150, to: 153)
        #expect(!ramp.isRamping)
        #expect(ramp.currentTarget() == nil)
    }

    @Test func largeDeltaStartsRamp() {
        var ramp = ERGRampController()
        let now = Date()
        ramp.beginRamp(from: 100, to: 200, at: now)
        #expect(ramp.startWatts == 100)
        #expect(ramp.endWatts == 200)
        #expect(ramp.isRamping)
    }

    @Test func rampProducesMonotonicIncreasingTargets() {
        var ramp = ERGRampController()
        let start = Date()
        ramp.beginRamp(from: 100, to: 200, at: start)

        var previous = 100
        for second in 1...8 {
            let time = start.addingTimeInterval(Double(second))
            if let target = ramp.currentTarget(at: time) {
                #expect(target >= previous, "Target at \(second)s (\(target)W) should be >= previous (\(previous)W)")
                previous = target
            }
        }
        #expect(previous == 200)
    }

    @Test func rampProducesMonotonicDecreasingTargets() {
        var ramp = ERGRampController()
        let start = Date()
        ramp.beginRamp(from: 200, to: 100, at: start)

        var previous = 200
        for second in 1...8 {
            let time = start.addingTimeInterval(Double(second))
            if let target = ramp.currentTarget(at: time) {
                #expect(target <= previous, "Target at \(second)s (\(target)W) should be <= previous (\(previous)W)")
                previous = target
            }
        }
        #expect(previous == 100)
    }

    @Test func rampReturnsEndValueAfterDuration() {
        var ramp = ERGRampController()
        let start = Date()
        ramp.beginRamp(from: 100, to: 250, at: start)

        let afterRamp = start.addingTimeInterval(10)
        let target = ramp.currentTarget(at: afterRamp)
        #expect(target == 250)
    }

    @Test func intermediateTargetsEndWithFinalValue() {
        var ramp = ERGRampController()
        let start = Date()
        ramp.beginRamp(from: 100, to: 200, at: start)

        let targets = ramp.intermediateTargets(at: start)
        #expect(!targets.isEmpty)
        #expect(targets.last == 200)
    }

    @Test func completeRampClearsState() {
        var ramp = ERGRampController()
        ramp.beginRamp(from: 100, to: 200)
        ramp.completeRamp()
        #expect(!ramp.isRamping)
        #expect(ramp.startWatts == nil)
        #expect(ramp.endWatts == nil)
    }

    @Test func smoothstepStartsAndEndsSmoothly() {
        var ramp = ERGRampController()
        let start = Date()
        ramp.beginRamp(from: 0, to: 1000, at: start)

        let earlyTarget = ramp.currentTarget(at: start.addingTimeInterval(0.1))!
        let lateTarget = ramp.currentTarget(at: start.addingTimeInterval(7.9))!

        #expect(earlyTarget < 50, "Early ramp should produce small change")
        #expect(lateTarget > 950, "Late ramp should be near final value")
    }
}

// MARK: - PowerSmoother Tests

struct PowerSmootherTests {

    @Test func noSamplesReturnsNil() {
        let smoother = PowerSmoother()
        #expect(smoother.smoothed() == nil)
    }

    @Test func singleSampleReturnsThatValue() {
        var smoother = PowerSmoother()
        let now = Date()
        smoother.add(200, at: now)
        #expect(smoother.smoothed(at: now) == 200)
    }

    @Test func averagesMultipleSamples() {
        var smoother = PowerSmoother()
        let now = Date()
        smoother.add(100, at: now.addingTimeInterval(-2))
        smoother.add(200, at: now.addingTimeInterval(-1))
        smoother.add(300, at: now)
        #expect(smoother.smoothed(at: now) == 200)
    }

    @Test func excludesOldSamples() {
        var smoother = PowerSmoother()
        let now = Date()
        smoother.add(100, at: now.addingTimeInterval(-5))
        smoother.add(200, at: now.addingTimeInterval(-1))
        smoother.add(300, at: now)
        #expect(smoother.smoothed(at: now) == 250)
    }

    @Test func resetClearsAllSamples() {
        var smoother = PowerSmoother()
        smoother.add(200)
        smoother.reset()
        #expect(smoother.smoothed() == nil)
    }

    @Test func customWindowSeconds() {
        var smoother = PowerSmoother()
        smoother.windowSeconds = 1.0
        let now = Date()
        smoother.add(100, at: now.addingTimeInterval(-2))
        smoother.add(300, at: now)
        #expect(smoother.smoothed(at: now) == 300)
    }
}

// MARK: - CadenceGuidance Tests

struct CadenceGuidanceTests {

    @Test func okDuringWarmup() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: 60, stepRole: .warmup, stepElapsed: 20)
        #expect(status == .ok)
    }

    @Test func okDuringCooldown() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: 50, stepRole: .cooldown, stepElapsed: 20)
        #expect(status == .ok)
    }

    @Test func noWarningEarlyInStep() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 5)
        #expect(status == .ok)
    }

    @Test func noDataWhenCadenceNil() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: nil, stepRole: .primary, stepElapsed: 20)
        #expect(status == .noData)
    }

    @Test func noDataWhenCadenceZero() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: 0, stepRole: .primary, stepElapsed: 20)
        #expect(status == .noData)
    }

    @Test func okWhenAboveThreshold() {
        var guidance = CadenceGuidance()
        let status = guidance.update(cadence: 80, stepRole: .primary, stepElapsed: 20)
        #expect(status == .ok)
    }

    @Test func lowAfterSustainedPeriod() {
        var guidance = CadenceGuidance()
        _ = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 15)

        Thread.sleep(forTimeInterval: 3.1)

        let status = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 18)
        #expect(status == .low(current: 60))
    }

    @Test func resetsWhenCadenceRecovers() {
        var guidance = CadenceGuidance()
        _ = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 15)

        Thread.sleep(forTimeInterval: 3.1)

        _ = guidance.update(cadence: 80, stepRole: .primary, stepElapsed: 18)
        let status = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 19)
        #expect(status == .ok)
    }

    @Test func resetClearsState() {
        var guidance = CadenceGuidance()
        _ = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 15)
        guidance.reset()
        let status = guidance.update(cadence: 60, stepRole: .primary, stepElapsed: 20)
        #expect(status == .ok)
    }
}
