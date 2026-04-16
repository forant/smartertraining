import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState

    @State private var step = 0
    @State private var name = ""
    @State private var currentState: FitnessState?
    @State private var goals: Set<TrainingGoal> = []
    @State private var availability: TypicalAvailability?
    @State private var frequency: TrainingFrequency?
    @State private var equipment: Set<Equipment> = []
    @State private var knowsFTP = false
    @State private var ftpText = ""
    @FocusState private var nameFieldFocused: Bool

    private let totalSteps = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay {
                if step > 0 {
                    ProgressView(value: Double(step), total: Double(totalSteps - 1))
                        .tint(.accentColor)
                        .padding(.horizontal, 56)
                }
            }

            TabView(selection: $step) {
                welcomeScreen.tag(0)
                nameScreen.tag(1)
                stateScreen.tag(2)
                goalsScreen.tag(3)
                availabilityScreen.tag(4)
                frequencyScreen.tag(5)
                equipmentScreen.tag(6)
                ftpScreen.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: step)
        }
    }

    // MARK: - Screens

    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 8) {
                Text("Welcome")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Let's get you set up in under a minute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                advance()
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var nameScreen: some View {
        OnboardingCard(question: "What should we call you?") {
            VStack(spacing: 20) {
                TextField("Your name (optional)", text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($nameFieldFocused)
                    .submitLabel(.continue)
                    .onSubmit { advanceFromName() }

                Button {
                    advanceFromName()
                } label: {
                    Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var stateScreen: some View {
        OnboardingCard(question: "How would you describe your current training consistency?") {
            OptionGrid(columns: 1) {
                ForEach(FitnessState.allCases, id: \.self) { state in
                    OnboardingPill(
                        label: state.rawValue,
                        isSelected: currentState == state
                    ) {
                        currentState = state
                        advance()
                    }
                }
            }
        }
    }

    private var goalsScreen: some View {
        OnboardingCard(question: "What are your fitness goals right now?") {
            VStack(spacing: 16) {
                OptionGrid(columns: 1) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        OnboardingPill(
                            label: goal.rawValue,
                            isSelected: goals.contains(goal)
                        ) {
                            if goals.contains(goal) {
                                goals.remove(goal)
                            } else {
                                goals.insert(goal)
                            }
                        }
                    }
                }

                Button {
                    advance()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(goals.isEmpty)
            }
        }
    }

    private var availabilityScreen: some View {
        OnboardingCard(question: "How much time do you usually have for workouts?") {
            OptionGrid(columns: 1) {
                ForEach(TypicalAvailability.allCases, id: \.self) { option in
                    OnboardingPill(
                        label: option.rawValue,
                        isSelected: availability == option
                    ) {
                        availability = option
                        advance()
                    }
                }
            }
        }
    }

    private var frequencyScreen: some View {
        OnboardingCard(question: "How many days per week do you want to train?") {
            OptionGrid(columns: 1) {
                ForEach(TrainingFrequency.allCases, id: \.self) { option in
                    OnboardingPill(
                        label: option.rawValue,
                        isSelected: frequency == option
                    ) {
                        frequency = option
                        advance()
                    }
                }
            }
        }
    }

    private var equipmentScreen: some View {
        OnboardingCard(question: "What exercise equipment do you have access to?") {
            VStack(spacing: 16) {
                OptionGrid(columns: 1) {
                    let noEquipmentSelected = equipment.contains(.noEquipment)
                    ForEach(Equipment.allCases, id: \.self) { item in
                        OnboardingPill(
                            label: item.rawValue,
                            isSelected: equipment.contains(item),
                            dimmed: noEquipmentSelected && item != .noEquipment
                        ) {
                            toggleEquipment(item)
                        }
                    }
                }

                Button {
                    advance()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(equipment.isEmpty)
            }
        }
    }

    private var ftpScreen: some View {
        OnboardingCard(question: "Do you know your cycling FTP?") {
            VStack(spacing: 20) {
                if !knowsFTP {
                    HStack(spacing: 12) {
                        Button {
                            knowsFTP = true
                        } label: {
                            Text("Yes")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            finish()
                        } label: {
                            Text("No / Skip")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                } else {
                    TextField("FTP in watts", text: $ftpText)
                        .font(.title3)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        finish()
                    } label: {
                        Text("Finish")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Helpers

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            step = min(step + 1, totalSteps - 1)
        }
    }

    private func goBack() {
        nameFieldFocused = false
        withAnimation(.easeInOut(duration: 0.3)) {
            step = max(step - 1, 0)
        }
    }

    private func advanceFromName() {
        nameFieldFocused = false
        advance()
    }

    private func toggleEquipment(_ item: Equipment) {
        if item == .noEquipment {
            if equipment.contains(.noEquipment) {
                equipment.remove(.noEquipment)
            } else {
                equipment = [.noEquipment]
            }
        } else {
            equipment.remove(.noEquipment)
            if equipment.contains(item) {
                equipment.remove(item)
            } else {
                equipment.insert(item)
            }
        }
    }

    private func finish() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let profile = UserProfile(
            name: trimmedName.isEmpty ? nil : trimmedName,
            currentState: currentState,
            goals: Array(goals),
            typicalAvailability: availability,
            trainingFrequency: frequency,
            equipment: Array(equipment),
            ftp: Int(ftpText)
        )
        appState.completeOnboarding(profile: profile)
    }
}

// MARK: - Onboarding Card

struct OnboardingCard<Content: View>: View {
    let question: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 32) {
            Text(question)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            content

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
    }
}

// MARK: - Onboarding Pill

struct OnboardingPill: View {
    let label: String
    var isSelected: Bool = false
    var dimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(dimmed ? .tertiary : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    OnboardingFlowView()
        .environment(AppState())
}
