import Foundation

struct PowerSmoother {

    var windowSeconds: TimeInterval = 3.0

    private var samples: [(date: Date, watts: Int)] = []

    mutating func add(_ watts: Int, at date: Date = Date()) {
        samples.append((date, watts))
        pruneOldSamples(before: date)
    }

    func smoothed(at date: Date = Date()) -> Int? {
        let cutoff = date.addingTimeInterval(-windowSeconds)
        let recent = samples.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }
        let sum = recent.reduce(0) { $0 + $1.watts }
        return sum / recent.count
    }

    mutating func reset() {
        samples.removeAll()
    }

    private mutating func pruneOldSamples(before date: Date) {
        let cutoff = date.addingTimeInterval(-windowSeconds * 2)
        samples.removeAll { $0.date < cutoff }
    }
}
