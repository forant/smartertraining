import Foundation

struct ERGRampController {

    var rampDuration: TimeInterval = 8.0
    var commandInterval: TimeInterval = 2.0

    private(set) var startWatts: Int?
    private(set) var endWatts: Int?
    private(set) var rampStartTime: Date?

    var isRamping: Bool {
        guard let start = rampStartTime else { return false }
        return Date().timeIntervalSince(start) < rampDuration
    }

    mutating func beginRamp(from current: Int, to target: Int, at time: Date = Date()) {
        let delta = abs(target - current)
        if delta <= 5 {
            startWatts = nil
            endWatts = nil
            rampStartTime = nil
            return
        }
        startWatts = current
        endWatts = target
        rampStartTime = time
    }

    func currentTarget(at time: Date = Date()) -> Int? {
        guard let start = startWatts,
              let end = endWatts,
              let rampStart = rampStartTime else { return nil }

        let elapsed = time.timeIntervalSince(rampStart)
        if elapsed >= rampDuration {
            return end
        }

        let fraction = min(1.0, max(0.0, elapsed / rampDuration))
        let smoothed = smoothstep(fraction)
        return start + Int(Double(end - start) * smoothed)
    }

    func intermediateTargets(at time: Date = Date()) -> [Int] {
        guard let start = startWatts,
              let end = endWatts,
              let rampStart = rampStartTime else { return [] }

        let elapsed = time.timeIntervalSince(rampStart)
        guard elapsed < rampDuration else { return [] }

        var targets: [Int] = []
        var t = elapsed + commandInterval
        while t < rampDuration {
            let fraction = smoothstep(min(1.0, t / rampDuration))
            targets.append(start + Int(Double(end - start) * fraction))
            t += commandInterval
        }
        targets.append(end)
        return targets
    }

    mutating func completeRamp() {
        startWatts = nil
        endWatts = nil
        rampStartTime = nil
    }

    private func smoothstep(_ t: Double) -> Double {
        t * t * (3.0 - 2.0 * t)
    }
}
