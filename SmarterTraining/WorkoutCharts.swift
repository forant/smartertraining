import SwiftUI

// MARK: - Charts Section

struct WorkoutChartsSection: View {
    let workout: CompletedWorkout

    private var powerValues: [Int] {
        workout.samples.compactMap(\.power).filter { $0 > 0 }
    }

    private var hrValues: [Int] {
        workout.samples.compactMap(\.heartRate).filter { $0 > 0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !powerValues.isEmpty {
                WorkoutMetricChart(
                    values: powerValues,
                    color: Theme.Brand.primary,
                    label: "POWER",
                    average: workout.averagePower,
                    maximum: workout.maxPower,
                    unit: "W"
                )
            }
            if !hrValues.isEmpty {
                WorkoutMetricChart(
                    values: hrValues,
                    color: Color(red: 0.84, green: 0.30, blue: 0.34),
                    label: "HEART RATE",
                    average: workout.averageHeartRate,
                    maximum: workout.maxHeartRate,
                    unit: "bpm"
                )
            }
        }
    }
}

// MARK: - Metric Chart Card

struct WorkoutMetricChart: View {
    let values: [Int]
    let color: Color
    let label: String
    let average: Int?
    let maximum: Int?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                Spacer()

                HStack(spacing: 10) {
                    if let avg = average {
                        Text("Avg \(avg)\(unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let max = maximum {
                        Text("Max \(max)\(unit)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }

            FilledLineChart(values: values, color: color, average: average)
                .frame(height: 100)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Filled Line Chart (Canvas)

private struct FilledLineChart: View {
    let values: [Int]
    let color: Color
    let average: Int?

    var body: some View {
        GeometryReader { geo in
            let points = downsample(targetCount: max(Int(geo.size.width / 2.5), 40))
            let maxVal = CGFloat(points.max() ?? 1)

            Canvas { context, size in
                guard points.count > 1 else { return }

                let linePath = buildLinePath(points: points, maxVal: maxVal, size: size)

                var fillPath = linePath
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()

                context.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.22), color.opacity(0.03)]),
                    startPoint: .init(x: 0, y: 0),
                    endPoint: .init(x: 0, y: size.height)
                ))

                context.stroke(linePath, with: .color(color.opacity(0.75)), lineWidth: 1.5)

                if let avg = average, maxVal > 0 {
                    let avgY = size.height - (CGFloat(avg) / maxVal) * size.height
                    let clampedY = max(4, min(size.height - 4, avgY))
                    var avgPath = Path()
                    avgPath.move(to: CGPoint(x: 0, y: clampedY))
                    avgPath.addLine(to: CGPoint(x: size.width, y: clampedY))
                    context.stroke(avgPath, with: .color(color.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
        }
    }

    private func buildLinePath(points: [Int], maxVal: CGFloat, size: CGSize) -> Path {
        var path = Path()
        for (i, val) in points.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(points.count - 1)
            let y = size.height - (CGFloat(val) / maxVal) * size.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func downsample(targetCount: Int) -> [Int] {
        guard !values.isEmpty else { return [] }
        guard values.count > targetCount else { return values }
        let bucketSize = max(values.count / targetCount, 1)
        return stride(from: 0, to: values.count, by: bucketSize).map { start in
            let end = min(start + bucketSize, values.count)
            let slice = values[start..<end]
            return slice.reduce(0, +) / slice.count
        }
    }
}
