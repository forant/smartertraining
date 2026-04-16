import Foundation
import Observation

// MARK: - User Profile & Onboarding

enum FitnessState: String, Codable, CaseIterable {
    case justStarting = "Just getting started"
    case gettingBack = "Getting back into training"
    case consistent = "Training somewhat consistently"
    case veryConsistent = "Training very consistently"
}

enum TrainingGoal: String, Codable, CaseIterable {
    case endurance = "Improve cardio fitness"
    case stronger = "Build strength"
    case consistent = "Stay consistent"
    case healthier = "Increase energy and overall health"
    case bikePerformance = "Support performance on the bike"
}

enum TypicalAvailability: String, Codable, CaseIterable {
    case short = "20\u{2013}30 min"
    case medium = "30\u{2013}45 min"
    case long = "45\u{2013}60+ min"
    case varies = "Varies day to day"
}

enum TrainingFrequency: String, Codable, CaseIterable {
    case light = "2\u{2013}3 days/week"
    case moderate = "3\u{2013}4 days/week"
    case heavy = "5+ days/week"
    case flexible = "Flexible"
}

enum Equipment: String, Codable, CaseIterable {
    case noEquipment = "No equipment"
    case dumbbells = "Dumbbells"
    case kettlebells = "Kettlebells"
    case bands = "Exercise bands"
    case stabilityBall = "Stability ball"
    case gym = "Full gym"
    case bikeTrainer = "Indoor trainer"
    case outdoorBike = "Outdoor bike"
}

struct UserProfile: Codable {
    var name: String?
    var currentState: FitnessState?
    var goals: [TrainingGoal]
    var typicalAvailability: TypicalAvailability?
    var trainingFrequency: TrainingFrequency?
    var equipment: [Equipment]
    var ftp: Int?

    static let empty = UserProfile(name: nil, currentState: nil, goals: [], typicalAvailability: nil, trainingFrequency: nil, equipment: [], ftp: nil)
}

struct CheckIn: Codable {
    var overallFeel: String
    var legs: String
    var motivation: String
    var timeAvailable: Int
    var contextFlags: [String]
    var notes: String?
}

enum WorkoutType: String, Codable {
    case recovery
    case endurance
    case quality

    var label: String {
        switch self {
        case .recovery: "Recovery"
        case .endurance: "Endurance"
        case .quality: "Quality"
        }
    }
}

enum WorkoutStepRole {
    case warmup, primary, cooldown, accessory
}

enum WorkoutStepModality {
    case cycling, strength, mobility, recovery
}

struct WorkoutStep {
    var role: WorkoutStepRole
    var modality: WorkoutStepModality
    var name: String
    var durationText: String
    var targetText: String
}

struct WorkoutRecommendation {
    var type: WorkoutType
    var title: String
    var summary: String
    var reason: String
    var steps: [WorkoutStep]
    var optionalExtras: [String]
}

enum WorkoutFeedback: String, Codable {
    case easy
    case right
    case hard
    case tooMuch

    var label: String {
        switch self {
        case .easy: "Easy"
        case .right: "Right"
        case .hard: "Hard"
        case .tooMuch: "Too much"
        }
    }

    var emoji: String {
        switch self {
        case .easy: "\u{1F44D}"
        case .right: "\u{1F642}"
        case .hard: "\u{1F613}"
        case .tooMuch: "\u{1F635}"
        }
    }
}

struct WorkoutHistoryEntry {
    var date: Date
    var title: String
    var type: WorkoutType
    var checkIn: CheckIn?
    var feedback: WorkoutFeedback?
}

enum CheckInPresentationContext {
    case regularCheckIn
    case updatingTodayPlan
    case returningAfterAbsence

    var title: String {
        switch self {
        case .regularCheckIn: "Welcome back"
        case .updatingTodayPlan: "Let's adjust today's plan"
        case .returningAfterAbsence: "Good to see you again"
        }
    }

    var subtitle: String {
        switch self {
        case .regularCheckIn: "How are you feeling today?"
        case .updatingTodayPlan: "What's changed?"
        case .returningAfterAbsence: "Let's get back into it"
        }
    }
}

// MARK: - App State

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool = false
    var userProfile: UserProfile = .empty

    var currentRecommendation: WorkoutRecommendation = .preview
    var latestCheckIn: CheckIn?
    var lastCheckInDate: Date?
    var todayFeedback: WorkoutFeedback?
    private(set) var recentHistory: [WorkoutHistoryEntry] = []

    private static let maxHistoryCount = 5

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let checkIn = "latestCheckIn"
        static let checkInDate = "lastCheckInDate"
        static let onboardingComplete = "hasCompletedOnboarding"
        static let userProfile = "userProfile"
    }

    init() {
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingComplete)
        if let profileData = defaults.data(forKey: Keys.userProfile),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            userProfile = saved
        }
        if let data = defaults.data(forKey: Keys.checkIn),
           let saved = try? JSONDecoder().decode(CheckIn.self, from: data) {
            lastCheckInDate = defaults.object(forKey: Keys.checkInDate) as? Date
            latestCheckIn = saved
            currentRecommendation = generateRecommendation(for: saved)
        }
    }

    func completeOnboarding(profile: UserProfile) {
        userProfile = profile
        hasCompletedOnboarding = true
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Keys.userProfile)
        }
        defaults.set(true, forKey: Keys.onboardingComplete)
    }

    var hasCheckedInToday: Bool {
        guard let lastDate = lastCheckInDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    var checkInContext: CheckInPresentationContext {
        guard let lastDate = lastCheckInDate else { return .returningAfterAbsence }
        if Calendar.current.isDateInYesterday(lastDate) {
            return .regularCheckIn
        }
        return .returningAfterAbsence
    }

    func submit(checkIn: CheckIn) {
        latestCheckIn = checkIn
        lastCheckInDate = Date()
        todayFeedback = nil
        let recommendation = generateRecommendation(for: checkIn)
        currentRecommendation = recommendation
        appendToHistory(recommendation: recommendation, checkIn: checkIn)
        persist(checkIn: checkIn)
    }

    func submitFeedback(_ feedback: WorkoutFeedback) {
        todayFeedback = feedback
        if let lastIndex = recentHistory.indices.last {
            recentHistory[lastIndex].feedback = feedback
        }
    }

    // DEBUG ONLY — remove before production
    func resetToday() {
        latestCheckIn = nil
        lastCheckInDate = nil
        todayFeedback = nil
        currentRecommendation = .preview
        defaults.removeObject(forKey: Keys.checkIn)
        defaults.removeObject(forKey: Keys.checkInDate)
    }

    // DEBUG ONLY — remove before production
    func resetOnboarding() {
        hasCompletedOnboarding = false
        userProfile = .empty
        defaults.removeObject(forKey: Keys.onboardingComplete)
        defaults.removeObject(forKey: Keys.userProfile)
    }

    // DEBUG ONLY — remove before production
    func debugSeedWorkout(type: WorkoutType) {
        let daysBack = recentHistory.count + 1
        let date = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

        let title: String
        switch type {
        case .recovery: title = "Recovery Day"
        case .endurance: title = "Endurance Ride"
        case .quality: title = "Threshold Intervals"
        }

        let entry = WorkoutHistoryEntry(date: date, title: title, type: type, checkIn: nil)
        recentHistory.insert(entry, at: 0)
        if recentHistory.count > Self.maxHistoryCount {
            recentHistory = Array(recentHistory.suffix(Self.maxHistoryCount))
        }
    }

    // DEBUG ONLY — remove before production
    func debugClearHistory() {
        recentHistory.removeAll()
    }

    private func appendToHistory(recommendation: WorkoutRecommendation, checkIn: CheckIn) {
        let entry = WorkoutHistoryEntry(
            date: Date(),
            title: recommendation.title,
            type: recommendation.type,
            checkIn: checkIn
        )
        recentHistory.append(entry)
        if recentHistory.count > Self.maxHistoryCount {
            recentHistory.removeFirst(recentHistory.count - Self.maxHistoryCount)
        }
    }

    private func persist(checkIn: CheckIn) {
        if let data = try? JSONEncoder().encode(checkIn) {
            defaults.set(data, forKey: Keys.checkIn)
        }
        defaults.set(Date(), forKey: Keys.checkInDate)
    }

    // MARK: - Recommendation Engine

    private let engine = RecommendationEngine()

    private func generateRecommendation(for checkIn: CheckIn) -> WorkoutRecommendation {
        let inputs = RecommendationEngine.Inputs(
            profile: userProfile,
            checkIn: checkIn,
            recentHistory: recentHistory
        )
        return engine.recommend(for: inputs)
    }
}

// MARK: - Preview Workout

extension WorkoutRecommendation {
    static let preview = WorkoutRecommendation(
        type: .endurance,
        title: "45 min Zone 2 Ride",
        summary: "Aerobic base work",
        reason: "A steady endurance ride fits where you are right now.",
        steps: [
            WorkoutStep(role: .warmup, modality: .cycling, name: "Warm-up", durationText: "5 min", targetText: "60% FTP"),
            WorkoutStep(role: .primary, modality: .cycling, name: "Main", durationText: "35 min", targetText: "Zone 2 / 70–80% FTP"),
            WorkoutStep(role: .cooldown, modality: .cycling, name: "Cool down", durationText: "5 min", targetText: "60% → 40% FTP")
        ],
        optionalExtras: []
    )
}

// MARK: - Preview Data

extension UserProfile {
    static let preview = UserProfile(
        name: "Alex",
        currentState: .consistent,
        goals: [.endurance],
        typicalAvailability: .medium,
        trainingFrequency: .moderate,
        equipment: [.bikeTrainer],
        ftp: 250
    )
}
