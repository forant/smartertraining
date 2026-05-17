import SwiftUI

// MARK: - TodayView Card

struct UpcomingContextCard: View {
    @Environment(AppState.self) private var appState
    let onAdd: () -> Void
    let onEdit: (UpcomingContextEvent) -> Void

    private var activeEvents: [UpcomingContextEvent] {
        appState.upcomingContextEvents
            .filter { !$0.isExpired }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activeEvents.isEmpty {
                emptyState
            } else {
                populatedState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        Button(action: onAdd) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Anything coming up we should plan around?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .buttonStyle(.plain)
    }

    private var populatedState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coming up")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            ForEach(activeEvents) { event in
                Button {
                    onEdit(event)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: event.type.icon)
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .frame(width: 18)

                        Text(event.narrativeLabel)
                            .font(.caption)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.accentColor)
        }
    }
}

// MARK: - Add / Edit Sheet

struct UpcomingContextSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var editingEvent: UpcomingContextEvent?

    @State private var selectedType: UpcomingContextEventType?
    @State private var selectedDuration: UpcomingContextDuration?
    @State private var selectedDayOffset: Int = 0
    @State private var selectedImpact: UpcomingContextImpact = .unknown
    @State private var note: String = ""

    private var isEditing: Bool { editingEvent != nil }
    private var isRange: Bool { selectedType?.isRangeContext == true }
    private var showsFollowUp: Bool { selectedType != nil }
    private var showsImpact: Bool { selectedType?.showsImpact == true }
    private var canSave: Bool {
        guard selectedType != nil else { return false }
        if isRange && selectedDuration == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    typeSection

                    if showsFollowUp {
                        if isRange {
                            durationSection
                        }

                        daySection

                        if showsImpact {
                            impactSection
                        }

                        noteSection
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: selectedType)
                .animation(.easeInOut(duration: 0.2), value: selectedDuration)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEditing ? "Edit" : "Heads up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { populateFromEditing() }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isEditing {
                Text("Give your coach a heads up about anything worth planning around.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(UpcomingContextEventType.allCases, id: \.self) { type in
                    chipButton(
                        label: type.displayText,
                        icon: type.icon,
                        isSelected: selectedType == type
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedType = type
                            if !type.isRangeContext {
                                selectedDuration = nil
                                if selectedDayOffset == 0 { selectedDayOffset = 1 }
                            } else {
                                selectedDayOffset = 0
                            }
                        }
                    }
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How long will this affect training?")
                .font(.subheadline)
                .fontWeight(.medium)

            FlowLayout(spacing: 8) {
                ForEach(UpcomingContextDuration.allCases, id: \.self) { dur in
                    chipButton(
                        label: dur.displayText,
                        isSelected: selectedDuration == dur
                    ) {
                        selectedDuration = dur
                    }
                }
            }
        }
    }

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isRange ? "Starting when?" : "When?")
                .font(.subheadline)
                .fontWeight(.medium)

            FlowLayout(spacing: 8) {
                ForEach(0...7, id: \.self) { offset in
                    chipButton(
                        label: dayLabel(for: offset),
                        isSelected: selectedDayOffset == offset
                    ) {
                        selectedDayOffset = offset
                    }
                }
            }
        }
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How much will this affect training?")
                .font(.subheadline)
                .fontWeight(.medium)

            FlowLayout(spacing: 8) {
                ForEach(UpcomingContextImpact.allCases, id: \.self) { impact in
                    chipButton(
                        label: impact.displayText,
                        isSelected: selectedImpact == impact
                    ) {
                        selectedImpact = impact
                    }
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything else? (optional)")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("Any details worth noting", text: $note, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if isEditing {
                Button("Delete", role: .destructive) {
                    delete()
                }
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Chips

    private func chipButton(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func dayLabel(for offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            return date.formatted(.dateTime.weekday(.wide))
        }
    }

    private func populateFromEditing() {
        guard let event = editingEvent else { return }
        selectedType = event.type
        selectedDayOffset = max(0, event.daysFromNow)
        selectedDuration = event.duration
        selectedImpact = event.impact
        note = event.note ?? ""
    }

    private func save() {
        guard let type = selectedType else { return }

        let date = Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Calendar.current.startOfDay(for: Date()))!
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let finalNote: String? = trimmedNote.isEmpty ? nil : trimmedNote
        let finalDuration: UpcomingContextDuration? = type.isRangeContext ? selectedDuration : nil

        var properties: [String: any Sendable] = [
            "event_type": type.rawValue,
            "days_until": AnalyticsProperties.countBucket(selectedDayOffset),
            "impact": selectedImpact.rawValue,
            "is_range": type.isRangeContext
        ]
        if let dur = finalDuration {
            properties["duration"] = dur.rawValue
        }

        if let existing = editingEvent {
            var updated = existing
            updated.type = type
            updated.date = date
            updated.impact = selectedImpact
            updated.duration = finalDuration
            updated.note = finalNote
            appState.updateUpcomingContext(updated)

            AnalyticsService.shared.track(.upcomingContextEdited, properties: properties)
        } else {
            let event = UpcomingContextEvent(
                date: date,
                type: type,
                impact: selectedImpact,
                duration: finalDuration,
                note: finalNote
            )
            appState.addUpcomingContext(event)

            AnalyticsService.shared.track(.upcomingContextAdded, properties: properties)
        }

        dismiss()
    }

    private func delete() {
        guard let event = editingEvent else { return }
        appState.deleteUpcomingContext(id: event.id)

        AnalyticsService.shared.track(.upcomingContextDeleted, properties: [
            "event_type": event.type.rawValue
        ])

        dismiss()
    }
}
