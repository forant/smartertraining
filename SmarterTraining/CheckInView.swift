import SwiftUI

// MARK: - Check-In Flow

struct CheckInView: View {
    var context: CheckInPresentationContext = .updatingTodayPlan

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var overallFeel = ""
    @State private var legs = ""
    @State private var motivation = ""
    @State private var timeAvailable = 0
    @State private var selectedContextFlags: Set<String> = []
    @State private var notes = ""

    private let totalSteps = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TabView(selection: $step) {
                    feelCard.tag(0)
                    legsCard.tag(1)
                    motivationCard.tag(2)
                    timeCard.tag(3)
                    contextCard.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if context == .updatingTodayPlan {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if step > 0 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards

    private var feelCard: some View {
        CheckInCard(
            heading: context.title,
            subheading: context.subtitle,
            question: "How do you feel today?"
        ) {
            OptionGrid {
                OptionButton(emoji: "😄", label: "Great", isSelected: overallFeel == "Great") {
                    overallFeel = "Great"
                    advance()
                }
                OptionButton(emoji: "🙂", label: "Good", isSelected: overallFeel == "Good") {
                    overallFeel = "Good"
                    advance()
                }
                OptionButton(emoji: "😐", label: "Okay", isSelected: overallFeel == "Okay") {
                    overallFeel = "Okay"
                    advance()
                }
                OptionButton(emoji: "😞", label: "Bad", isSelected: overallFeel == "Bad") {
                    overallFeel = "Bad"
                    advance()
                }
            }
        }
    }

    private var legsCard: some View {
        CheckInCard(question: "How do your legs feel?") {
            OptionGrid {
                OptionButton(emoji: "⚡", label: "Fresh", isSelected: legs == "Fresh") {
                    legs = "Fresh"
                    advance()
                }
                OptionButton(emoji: "👍", label: "Normal", isSelected: legs == "Normal") {
                    legs = "Normal"
                    advance()
                }
                OptionButton(emoji: "🪨", label: "Heavy", isSelected: legs == "Heavy") {
                    legs = "Heavy"
                    advance()
                }
                OptionButton(emoji: "🧱", label: "Dead", isSelected: legs == "Dead") {
                    legs = "Dead"
                    advance()
                }
            }
        }
    }

    private var motivationCard: some View {
        CheckInCard(question: "How motivated are you?") {
            OptionGrid(columns: 3) {
                OptionButton(emoji: "🔥", label: "High", isSelected: motivation == "High") {
                    motivation = "High"
                    advance()
                }
                OptionButton(emoji: "👍", label: "Medium", isSelected: motivation == "Medium") {
                    motivation = "Medium"
                    advance()
                }
                OptionButton(emoji: "😴", label: "Low", isSelected: motivation == "Low") {
                    motivation = "Low"
                    advance()
                }
            }
        }
    }

    private var timeCard: some View {
        CheckInCard(question: "How much time do you have?") {
            OptionGrid {
                OptionButton(emoji: "⏱", label: "20 min", isSelected: timeAvailable == 20) {
                    timeAvailable = 20
                    advance()
                }
                OptionButton(emoji: "⏱", label: "30 min", isSelected: timeAvailable == 30) {
                    timeAvailable = 30
                    advance()
                }
                OptionButton(emoji: "⏱", label: "45 min", isSelected: timeAvailable == 45) {
                    timeAvailable = 45
                    advance()
                }
                OptionButton(emoji: "⏱", label: "60+ min", isSelected: timeAvailable == 60) {
                    timeAvailable = 60
                    advance()
                }
            }
        }
    }

    private var contextCard: some View {
        CheckInCard(question: "Anything else worth noting?") {
            VStack(spacing: 20) {
                let contextOptions: [(String, String)] = [
                    ("😴", "Slept poorly"),
                    ("🤒", "Getting sick"),
                    ("👶", "Toddler kept me up"),
                    ("😵", "High stress"),
                    ("🦵", "Sore legs"),
                    ("💪", "Feel strong"),
                    ("⏱", "Crunched for time")
                ]

                FlowLayout(spacing: 10) {
                    ForEach(contextOptions, id: \.1) { emoji, label in
                        ContextChip(
                            emoji: emoji,
                            label: label,
                            isSelected: selectedContextFlags.contains(label)
                        ) {
                            if selectedContextFlags.contains(label) {
                                selectedContextFlags.remove(label)
                            } else {
                                selectedContextFlags.insert(label)
                            }
                        }
                    }
                }

                TextField("Any notes? (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    let checkIn = CheckIn(
                        overallFeel: overallFeel,
                        legs: legs,
                        motivation: motivation,
                        timeAvailable: timeAvailable,
                        contextFlags: Array(selectedContextFlags),
                        notes: notes.isEmpty ? nil : notes
                    )
                    appState.submit(checkIn: checkIn)
                    if context == .updatingTodayPlan { dismiss() }
                } label: {
                    Text("Submit")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            step = min(step + 1, totalSteps - 1)
        }
    }
}

// MARK: - Reusable Card Components

struct CheckInCard<Content: View>: View {
    var heading: String? = nil
    var subheading: String? = nil
    let question: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                if let heading {
                    Text(heading)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                if let subheading {
                    Text(subheading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Text(question)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            content

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }
}

struct OptionGrid<Content: View>: View {
    var columns: Int = 2
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
            spacing: 16
        ) {
            content
        }
    }
}

struct OptionButton: View {
    let emoji: String
    let label: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 36))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct ContextChip: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.body)
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Preview

#Preview {
    CheckInView()
        .environment(AppState())
}
