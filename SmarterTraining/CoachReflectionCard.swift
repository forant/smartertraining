import SwiftUI

// MARK: - Card

/// Self-contained reflective coaching card.
///
/// Lifecycle:
///   prompt -> validation -> collapsed
/// The interaction ends after one response. No threading, no chat history.
struct CoachReflectionCard: View {
    let prompt: CoachReflectionPrompt
    let workoutId: UUID
    let context: CoachReflectionValidator.Context
    let onSave: (CoachReflection) -> Void

    @State private var phase: Phase = .prompt
    @State private var selectedChoice: CoachReflectionChoice?
    @State private var validationText: String = ""
    @State private var note: String = ""
    @State private var savedReflection: CoachReflection?

    private enum Phase {
        case prompt, validation, collapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            switch phase {
            case .prompt:
                promptBody
            case .validation:
                validationBody
            case .collapsed:
                collapsedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
        .animation(.easeInOut(duration: 0.25), value: phase)
        .onAppear {
            AnalyticsService.shared.track(.coachReflectionShown, properties: [
                "prompt_kind": prompt.kind.rawValue
            ])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .font(.subheadline)
                .foregroundStyle(Theme.Brand.primary)
            Text(phase == .collapsed ? "Reflection saved" : "Coach check-in")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer()
            if phase == .collapsed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Semantic.recovery)
            }
        }
    }

    // MARK: - Prompt phase

    private var promptBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(prompt.question)
                .font(.subheadline)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(prompt.choices, id: \.label) { choice in
                    ContextChip(label: choice.label, isSelected: false) {
                        respond(with: choice)
                    }
                }
            }
        }
    }

    // MARK: - Validation phase

    private var validationBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let selected = selectedChoice {
                HStack(spacing: 8) {
                    Image(systemName: "quote.bubble")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(selected.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            Text(validationText)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "",
                text: $note,
                prompt: Text("Anything to add? (optional)"),
                axis: .vertical
            )
            .lineLimit(1...3)
            .font(.caption)
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Save") { commit() }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Collapsed phase

    private var collapsedBody: some View {
        Group {
            if let saved = savedReflection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(saved.responseLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(saved.validation)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    private func respond(with choice: CoachReflectionChoice) {
        selectedChoice = choice
        validationText = CoachReflectionValidator.validate(
            promptKind: prompt.kind,
            response: choice.response,
            context: context
        )
        phase = .validation

        AnalyticsService.shared.track(.coachReflectionAnswered, properties: [
            "prompt_kind": prompt.kind.rawValue,
            "response": choice.response.rawValue
        ])
    }

    private func commit() {
        guard let choice = selectedChoice else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let reflection = CoachReflection(
            workoutId: workoutId,
            promptKind: prompt.kind,
            question: prompt.question,
            response: choice.response,
            responseLabel: choice.label,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            validation: validationText
        )
        savedReflection = reflection
        onSave(reflection)
        phase = .collapsed
    }
}

// MARK: - Saved Card (for WorkoutDetailView)

/// Compact, always-collapsed display of a saved reflection. Read-only.
struct SavedCoachReflectionCard: View {
    let reflection: CoachReflection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Brand.primary)
                Text("Coach check-in")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .tracking(0.3)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Semantic.recovery)
            }

            Text(reflection.question)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(reflection.responseLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.Surface.unselectedControl)
                    .clipShape(Capsule())
            }

            Text(reflection.validation)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let note = reflection.note, !note.isEmpty {
                Text("\u{201C}\(note)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Border.subtle, lineWidth: Theme.Border.width)
        )
    }
}
