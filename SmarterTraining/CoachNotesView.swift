import SwiftUI

// MARK: - Entry Card (TodayView)

struct CoachNotesEntryCard: View {
    let notes: CoachNotes
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "person.text.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Brand.primary)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Coach context")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)

                    if notes.isEmpty {
                        Text("What should your coach know?")
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.75))
                    } else {
                        Text(notes.summaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notes.isEmpty ? "Add coach context" : "Edit coach context")
    }
}

// MARK: - Edit Sheet

struct CoachNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialNotes: CoachNotes
    let onSave: (CoachNotes) -> Void

    @State private var freeformNote: String = ""
    @State private var tags: Set<CoachNoteTag> = []

    private let examples: [String] = [
        "Cardio feels strong but my legs fatigue first.",
        "My knees sometimes flare up during low-cadence work.",
        "Work stress has been high lately.",
        "I usually have more time on weekends.",
        "I mentally struggle with VO2 intervals.",
        "Sleep has been inconsistent recently.",
        "Long steady rides feel easier than punchy efforts."
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    intro

                    notesField

                    if freeformNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        exampleList
                    }

                    tagsSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Surface.background)
            .navigationTitle("Coach context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(CoachNotes(
                            freeformNote: freeformNote.trimmingCharacters(in: .whitespacesAndNewlines),
                            tags: tags,
                            updatedAt: nil
                        ))
                        dismiss()
                    }
                }
            }
            .onAppear {
                freeformNote = initialNotes.freeformNote
                tags = initialNotes.tags
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("What should your coach know?")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Anything that helps shape your training over time. Add what's true, skip what isn't.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "",
                text: $freeformNote,
                prompt: Text("Type a note for your coach"),
                axis: .vertical
            )
            .lineLimit(4...10)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var exampleList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOR EXAMPLE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            ForEach(examples, id: \.self) { example in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2014}")
                        .foregroundStyle(.tertiary)
                    Text(example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("OPTIONAL TAGS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            FlowLayout(spacing: 8) {
                ForEach(CoachNoteTag.allCases, id: \.self) { tag in
                    ContextChip(
                        label: tag.label,
                        isSelected: tags.contains(tag)
                    ) {
                        if tags.contains(tag) { tags.remove(tag) }
                        else { tags.insert(tag) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
