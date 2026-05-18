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

    private let totalSteps = 9

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
                if step >= 2 {
                    ProgressView(value: Double(step - 1), total: Double(totalSteps - 2))
                        .tint(.accentColor)
                        .padding(.horizontal, 56)
                }
            }

            TabView(selection: $step) {
                introScreen.tag(0)
                howItWorksScreen.tag(1)
                nameScreen.tag(2)
                stateScreen.tag(3)
                goalsScreen.tag(4)
                availabilityScreen.tag(5)
                frequencyScreen.tag(6)
                equipmentScreen.tag(7)
                ftpScreen.tag(8)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: step)
        }
    }

    // MARK: - Intro Screens

    private var introScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 12) {
                Text("Training for people\nwith real lives")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Adaptive workouts that adjust around your schedule, fatigue, motivation, and recovery.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                AnalyticsService.shared.track(.onboardingIntroViewed)
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

    private var howItWorksScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("How SmarterTraining works")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 24) {
                howItWorksStep(
                    number: 1,
                    title: "Check in",
                    description: "Tell the coach how you're feeling, how much time you have, and what life looks like today."
                )
                howItWorksStep(
                    number: 2,
                    title: "Get today's recommendation",
                    description: "Your workout adapts around fatigue, recovery, consistency, and upcoming events."
                )
                howItWorksStep(
                    number: 3,
                    title: "Train without overthinking",
                    description: "Ride indoors with smart trainer control or take the workout outside."
                )
            }

            Text("Built for consistency, not perfection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                AnalyticsService.shared.track(.onboardingHowItWorksViewed)
                AnalyticsService.shared.track(.onboardingStarted)
                advance()
            } label: {
                Text("Personalize my training")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func howItWorksStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Personalization Screens

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
                            label: goal.displayText,
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
        OnboardingCard(question: "What equipment do you regularly use?") {
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
        OnboardingCard(question: "Do you know your FTP?") {
            VStack(spacing: 20) {
                Text("Used to personalize cycling workouts. You can update this anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

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
        let fromStep = step
        withAnimation(.easeInOut(duration: 0.3)) {
            step = min(step + 1, totalSteps - 1)
        }
        AnalyticsService.shared.track(.onboardingStepCompleted, properties: [
            "step": fromStep,
            "step_name": stepName(for: fromStep)
        ])
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

        AnalyticsService.shared.track(.onboardingCompleted, properties: [
            "has_ftp": profile.ftp != nil,
            "equipment_count": profile.equipment.count,
            "goal_count": profile.goals.count,
            "has_trainer": profile.equipment.contains(.bikeTrainer)
        ])
        AnalyticsService.shared.setUserProperties([
            "fitness_state": profile.currentState?.rawValue ?? "unknown",
            "training_frequency": profile.trainingFrequency?.rawValue ?? "unknown",
            "typical_availability": profile.typicalAvailability?.rawValue ?? "unknown",
            "has_ftp": profile.ftp != nil,
            "has_trainer": profile.equipment.contains(.bikeTrainer)
        ])
    }

    private func stepName(for step: Int) -> String {
        switch step {
        case 0: "intro"
        case 1: "how_it_works"
        case 2: "name"
        case 3: "fitness_state"
        case 4: "goals"
        case 5: "availability"
        case 6: "frequency"
        case 7: "equipment"
        case 8: "ftp"
        default: "unknown"
        }
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
                .fixedSize(horizontal: false, vertical: true)

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
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(isSelected ? Theme.Surface.selectedControl : Theme.Surface.unselectedControl)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(isSelected ? Theme.Border.selected : .clear, lineWidth: Theme.Border.selectedWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    OnboardingFlowView()
        .environment(AppState())
}
