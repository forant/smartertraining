import SwiftUI

struct StravaWorkoutCardView: View {
    let workout: CompletedWorkout

    private let cardWidth: CGFloat = 360
    private let cardHeight: CGFloat = 450

    var body: some View {
        VStack(spacing: 0) {
            heroSection
            statsSection
            if !powerSamples.isEmpty {
                powerChartSection
            }
            Spacer(minLength: 0)
            footerSection
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color(red: 0.06, green: 0.07, blue: 0.11))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 6) {
            Text(workout.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(formattedDate)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.208, green: 0.286, blue: 0.659),
                    Color(red: 0.184, green: 0.247, blue: 0.569)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Stats

    private var statsSection: some View {
        let stats = availableStats
        let columns = min(stats.count, 3)
        let rows = stats.chunked(into: columns)

        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, stat in
                        statCell(stat)
                            .frame(maxWidth: .infinity)
                        if index < row.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 1, height: 36)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func statCell(_ stat: StatItem) -> some View {
        VStack(spacing: 2) {
            Text(stat.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(stat.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
        }
    }

    // MARK: - Power Chart

    private var powerChartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POWER")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 20)

            PowerProfileChart(samples: powerSamples, maxPower: workout.maxPower ?? 1)
                .frame(height: 80)
                .padding(.horizontal, 20)
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()
            Text("SmarterTraining")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1.5)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.bottom, 16)
    }

    // MARK: - Data

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return formatter.string(from: workout.startDate)
    }

    private var powerSamples: [Int] {
        workout.samples.compactMap(\.power).filter { $0 > 0 }
    }

    private var availableStats: [StatItem] {
        var stats: [StatItem] = []

        let minutes = Int(workout.duration) / 60
        let seconds = Int(workout.duration) % 60
        stats.append(StatItem(
            value: seconds > 0 ? "\(minutes):\(String(format: "%02d", seconds))" : "\(minutes)",
            label: "Minutes"
        ))

        if let avg = workout.averagePower {
            stats.append(StatItem(value: "\(avg)", label: "Avg Power"))
        }
        if let max = workout.maxPower {
            stats.append(StatItem(value: "\(max)", label: "Max Power"))
        }
        if let hr = workout.averageHeartRate {
            stats.append(StatItem(value: "\(hr)", label: "Avg HR"))
        }
        if let maxHR = workout.maxHeartRate {
            stats.append(StatItem(value: "\(maxHR)", label: "Max HR"))
        }
        if let cadence = workout.averageCadence {
            stats.append(StatItem(value: "\(cadence)", label: "Cadence"))
        }

        return stats
    }
}

// MARK: - Supporting Types

private struct StatItem {
    let value: String
    let label: String
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [Array(self)] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Power Profile Chart

private struct PowerProfileChart: View {
    let samples: [Int]
    let maxPower: Int

    var body: some View {
        GeometryReader { geo in
            let buckets = downsample(width: geo.size.width)
            let maxVal = CGFloat(max(maxPower, 1))

            Canvas { context, size in
                let barCount = buckets.count
                guard barCount > 0 else { return }
                let barWidth = size.width / CGFloat(barCount)

                for (index, value) in buckets.enumerated() {
                    let height = (CGFloat(value) / maxVal) * size.height
                    let rect = CGRect(
                        x: CGFloat(index) * barWidth,
                        y: size.height - height,
                        width: max(barWidth - 0.5, 0.5),
                        height: height
                    )
                    let intensity = CGFloat(value) / maxVal
                    let color = barColor(intensity: intensity)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private func downsample(width: CGFloat) -> [Int] {
        guard !samples.isEmpty else { return [] }
        let targetBars = max(Int(width / 2.5), 20)
        let bucketSize = max(samples.count / targetBars, 1)
        return stride(from: 0, to: samples.count, by: bucketSize).map { start in
            let end = min(start + bucketSize, samples.count)
            let slice = samples[start..<end]
            return slice.reduce(0, +) / slice.count
        }
    }

    private func barColor(intensity: CGFloat) -> Color {
        if intensity > 0.85 {
            return Color(red: 0.937, green: 0.267, blue: 0.267)
        } else if intensity > 0.65 {
            return Color(red: 1.0, green: 0.6, blue: 0.2)
        } else {
            return Color(red: 0.208, green: 0.286, blue: 0.659).opacity(0.6 + intensity * 0.4)
        }
    }
}
