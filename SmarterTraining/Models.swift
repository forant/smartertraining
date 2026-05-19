import Foundation
import Observation
import UserNotifications

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

    var displayText: String {
        switch self {
        case .endurance: "Improve endurance"
        case .stronger: "Build strength"
        case .consistent: "Stay consistent"
        case .healthier: "Feel healthier and more energetic"
        case .bikePerformance: "Improve cycling performance"
        }
    }
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

struct RecentActivity: Codable, Equatable {
    var type: String
    var timing: String?
    var intensity: String?
}

struct CheckIn: Codable, Identifiable {
    let id: UUID
    var overallFeel: String
    var legs: String
    var motivation: String
    var timeAvailable: Int
    var recentActivities: [RecentActivity]
    var contextFlags: [String]
    var notes: String?

    init(
        id: UUID = UUID(),
        overallFeel: String,
        legs: String,
        motivation: String,
        timeAvailable: Int,
        contextFlags: [String],
        recentActivities: [RecentActivity] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.overallFeel = overallFeel
        self.legs = legs
        self.motivation = motivation
        self.timeAvailable = timeAvailable
        self.recentActivities = recentActivities
        self.contextFlags = contextFlags
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        overallFeel = try container.decode(String.self, forKey: .overallFeel)
        legs = try container.decode(String.self, forKey: .legs)
        motivation = try container.decode(String.self, forKey: .motivation)
        timeAvailable = try container.decode(Int.self, forKey: .timeAvailable)
        recentActivities = try container.decodeIfPresent([RecentActivity].self, forKey: .recentActivities) ?? []
        contextFlags = try container.decode([String].self, forKey: .contextFlags)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
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

enum QualitySubtype: String, Codable, Equatable, CaseIterable {
    case vo2
    case threshold
    case muscularEndurance
    case tempo
    case overUnders

    var label: String {
        switch self {
        case .vo2: "VO2 Max"
        case .threshold: "Threshold"
        case .muscularEndurance: "Muscular Endurance"
        case .tempo: "Tempo"
        case .overUnders: "Over/Unders"
        }
    }

    /// Relative fatigue cost on a 1–3 scale used to shape next-day intent.
    /// VO2 and Threshold are the heaviest; Tempo is the lightest quality option.
    var recoveryCost: Int {
        switch self {
        case .vo2: 3
        case .threshold: 3
        case .overUnders: 2
        case .muscularEndurance: 2
        case .tempo: 1
        }
    }
}

enum WorkoutStepRole: String, Codable {
    case warmup, primary, cooldown, accessory
}

enum WorkoutStepModality: String, Codable {
    case cycling, strength, mobility, recovery
}

struct WorkoutStep: Codable {
    var role: WorkoutStepRole
    var modality: WorkoutStepModality
    var name: String
    var durationText: String
    var targetText: String
}

struct WorkoutRecommendation: Codable {
    var type: WorkoutType
    var qualitySubtype: QualitySubtype?
    var title: String
    var summary: String
    var reason: String
    var steps: [WorkoutStep]
    var optionalExtras: [String]

    init(
        type: WorkoutType,
        qualitySubtype: QualitySubtype? = nil,
        title: String,
        summary: String,
        reason: String,
        steps: [WorkoutStep],
        optionalExtras: [String]
    ) {
        self.type = type
        self.qualitySubtype = qualitySubtype
        self.title = title
        self.summary = summary
        self.reason = reason
        self.steps = steps
        self.optionalExtras = optionalExtras
    }
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

struct WorkoutHistoryEntry: Codable, Identifiable {
    let id: UUID
    var date: Date
    var title: String
    var type: WorkoutType
    var checkIn: CheckIn?
    var feedback: WorkoutFeedback?
    var feedbackAt: Date?
    var qualitySubtype: QualitySubtype?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        type: WorkoutType,
        checkIn: CheckIn? = nil,
        feedback: WorkoutFeedback? = nil,
        feedbackAt: Date? = nil,
        qualitySubtype: QualitySubtype? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.type = type
        self.checkIn = checkIn
        self.feedback = feedback
        self.feedbackAt = feedbackAt
        self.qualitySubtype = qualitySubtype
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(WorkoutType.self, forKey: .type)
        checkIn = try container.decodeIfPresent(CheckIn.self, forKey: .checkIn)
        feedback = try container.decodeIfPresent(WorkoutFeedback.self, forKey: .feedback)
        feedbackAt = try container.decodeIfPresent(Date.self, forKey: .feedbackAt)
        qualitySubtype = try container.decodeIfPresent(QualitySubtype.self, forKey: .qualitySubtype)
    }
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
    private(set) var coachNotes: CoachNotes = .empty
    private(set) var progressionState: ProgressionState = .empty
    private(set) var trainingApproach: TrainingApproach = .default

    private(set) var upcomingContextEvents: [UpcomingContextEvent] = []

    let store = LocalStore()
    let auth = BackendAuthService()
    private(set) var sync: BackendSyncService!
    private static let maxHistoryCount = 30

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let checkIn = "latestCheckIn"
        static let checkInDate = "lastCheckInDate"
        static let onboardingComplete = "hasCompletedOnboarding"
        static let userProfile = "userProfile"
        static let coachNotes = "coachNotes"
        static let progressionState = "progressionState"
        static let trainingApproach = "trainingApproach"
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
        upcomingContextEvents = store.loadUpcomingContext().filter { !$0.isExpired }
        recentHistory = store.loadWorkouts().suffix(Self.maxHistoryCount)
        if let notesData = defaults.data(forKey: Keys.coachNotes),
           let saved = try? JSONDecoder().decode(CoachNotes.self, from: notesData) {
            coachNotes = saved
        }
        if let progData = defaults.data(forKey: Keys.progressionState),
           let saved = try? JSONDecoder().decode(ProgressionState.self, from: progData) {
            progressionState = saved
        }
        if let approachRaw = defaults.string(forKey: Keys.trainingApproach),
           let saved = TrainingApproach(rawValue: approachRaw) {
            trainingApproach = saved
        }
        if let last = recentHistory.last,
           Calendar.current.isDateInToday(last.date) {
            todayFeedback = last.feedback
        }
        sync = BackendSyncService(auth: auth, store: store)

        #if DEBUG
        ScreenshotSeeder.applyIfRequested(to: self)
        #endif
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
        triggerSync()
    }

    func submitFeedback(_ feedback: WorkoutFeedback) {
        todayFeedback = feedback
        if let lastIndex = recentHistory.indices.last {
            recentHistory[lastIndex].feedback = feedback
            recentHistory[lastIndex].feedbackAt = Date()
            store.saveWorkouts(Array(recentHistory))
        }
        AnalyticsService.shared.track(.workoutFeedbackSubmitted, properties: [
            "feedback": feedback.rawValue
        ])
        applyProgressionUpdate(for: feedback)
        triggerSync()
    }

    /// Update progression state based on the just-submitted feedback. Reads the
    /// latest history entry to know which subtype was performed, and the matching
    /// ride to fold in coach-reflection signal when available.
    private func applyProgressionUpdate(for feedback: WorkoutFeedback) {
        guard let entry = recentHistory.last,
              entry.type == .quality,
              let subtype = entry.qualitySubtype else { return }

        let ride = store.finishedRides().first {
            Calendar.current.isDate($0.startDate, inSameDayAs: entry.date)
        }
        let reflection = ride?.coachReflection
        guard let signal = ProgressionSignalClassifier.signal(feedback: feedback, reflection: reflection) else { return }

        let previousTier = progressionState.tier(for: subtype)
        let updated = progressionState.applying(signal: signal, to: subtype, approach: trainingApproach)
        progressionState = updated
        persistProgressionState()

        let newTier = updated.tier(for: subtype)
        if newTier != previousTier {
            AnalyticsService.shared.track(.progressionTierChanged, properties: [
                "subtype": subtype.rawValue,
                "from_tier": previousTier.rawValue,
                "to_tier": newTier.rawValue,
                "signal": String(describing: signal),
                "training_approach": trainingApproach.rawValue
            ])
        }
    }

    private func persistProgressionState() {
        if let data = try? JSONEncoder().encode(progressionState) {
            defaults.set(data, forKey: Keys.progressionState)
        }
    }

    func triggerSync() {
        guard auth.isSignedIn else { return }
        Task { await sync.sync() }
    }

    // MARK: - Training Approach

    /// Updates the coaching approach. Like coach notes, this is *evolving context*
    /// — it does not retroactively rewrite today's plan. It takes effect at the next
    /// check-in and on every subsequent progression update.
    func setTrainingApproach(_ approach: TrainingApproach) {
        guard approach != trainingApproach else { return }
        let previous = trainingApproach
        trainingApproach = approach
        defaults.set(approach.rawValue, forKey: Keys.trainingApproach)
        AnalyticsService.shared.track(.trainingApproachChanged, properties: [
            "training_approach": approach.rawValue,
            "previous_approach": previous.rawValue
        ])
        triggerSync()
    }

    // MARK: - Coach Notes

    /// Coach Notes are evolving context. Edits do NOT rewrite today's plan — today
    /// was already shaped by today's check-in. Notes take effect at the next check-in
    /// so the user never sees their hero card change under them mid-day.
    func setCoachNotes(_ notes: CoachNotes) {
        var updated = notes
        if !updated.isEmpty {
            updated.updatedAt = Date()
        }
        coachNotes = updated
        if updated.isEmpty {
            defaults.removeObject(forKey: Keys.coachNotes)
        } else if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Keys.coachNotes)
        }
        AnalyticsService.shared.track(.coachNotesUpdated, properties: [
            "has_note": !updated.freeformNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "tag_count": updated.tags.count
        ])
        triggerSync()
    }

    // MARK: - Upcoming Context

    var upcomingContextSummary: UpcomingContextSummary {
        UpcomingContextSummary.build(from: upcomingContextEvents)
    }

    func addUpcomingContext(_ event: UpcomingContextEvent) {
        upcomingContextEvents.append(event)
        store.saveUpcomingContext(upcomingContextEvents)
        refreshRecommendationIfCheckedIn()
        triggerSync()
    }

    func updateUpcomingContext(_ event: UpcomingContextEvent) {
        if let index = upcomingContextEvents.firstIndex(where: { $0.id == event.id }) {
            var updated = event
            updated.updatedAt = Date()
            upcomingContextEvents[index] = updated
            store.saveUpcomingContext(upcomingContextEvents)
            refreshRecommendationIfCheckedIn()
            triggerSync()
        }
    }

    func deleteUpcomingContext(id: UUID) {
        upcomingContextEvents.removeAll { $0.id == id }
        store.saveUpcomingContext(upcomingContextEvents)
        refreshRecommendationIfCheckedIn()
        triggerSync()
    }

    // MARK: - Account Deletion

    func deleteAllLocalData() {
        hasCompletedOnboarding = false
        userProfile = .empty
        latestCheckIn = nil
        lastCheckInDate = nil
        todayFeedback = nil
        currentRecommendation = .preview
        recentHistory.removeAll()
        upcomingContextEvents.removeAll()
        coachNotes = .empty
        progressionState = .empty
        trainingApproach = .default

        defaults.removeObject(forKey: Keys.onboardingComplete)
        defaults.removeObject(forKey: Keys.userProfile)
        defaults.removeObject(forKey: Keys.checkIn)
        defaults.removeObject(forKey: Keys.checkInDate)
        defaults.removeObject(forKey: Keys.coachNotes)
        defaults.removeObject(forKey: Keys.progressionState)
        defaults.removeObject(forKey: Keys.trainingApproach)

        store.deleteAllData()

        CoachingNotificationManager.shared.cancelExistingCoachingNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        RememberedDeviceStore.shared.forgetTrainer()
        RememberedDeviceStore.shared.forgetHRM()
    }

    #if DEBUG
    /// Debug-only bulk seed for App Store screenshot scenarios. Wipes existing
    /// state and replaces it with the seed's contents. Persists to the real
    /// local store + UserDefaults so the app launches into the seeded state.
    /// This must never be called in production.
    func applyScreenshotSeed(_ seed: ScreenshotSeed) {
        deleteAllLocalData()

        if let profile = seed.profile {
            completeOnboarding(profile: profile)
        }
        if !seed.coachNotes.isEmpty {
            setCoachNotes(seed.coachNotes)
        }
        if seed.approach != .default {
            setTrainingApproach(seed.approach)
        }
        if seed.progressionState != .empty {
            progressionState = seed.progressionState
            persistProgressionState()
        }
        if !seed.history.isEmpty {
            recentHistory = seed.history
            store.saveWorkouts(seed.history)
        }
        for ride in seed.rides {
            store.saveRide(ride)
        }
        if let intent = seed.intent {
            store.saveIntent(intent)
        }
        if let checkIn = seed.checkIn {
            submit(checkIn: checkIn)
        }
        if let feedback = seed.feedback {
            submitFeedback(feedback)
        }
    }
    #endif

    private func refreshRecommendationIfCheckedIn() {
        if let checkIn = latestCheckIn, hasCheckedInToday {
            currentRecommendation = generateRecommendation(for: checkIn)
        }
    }

    #if DEBUG
    func resetToday() {
        latestCheckIn = nil
        lastCheckInDate = nil
        todayFeedback = nil
        currentRecommendation = .preview
        defaults.removeObject(forKey: Keys.checkIn)
        defaults.removeObject(forKey: Keys.checkInDate)

        // Also clear any completed rides logged today so the CompletedHeroCard
        // doesn't linger on the Today screen.
        let cal = Calendar.current
        for ride in store.finishedRides() where cal.isDateInToday(ride.startDate) {
            store.deleteRide(id: ride.id)
        }
        // Drop today's history entry too so memory + UI stay aligned.
        recentHistory.removeAll { cal.isDateInToday($0.date) }
        store.saveWorkouts(Array(recentHistory))
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        userProfile = .empty
        defaults.removeObject(forKey: Keys.onboardingComplete)
        defaults.removeObject(forKey: Keys.userProfile)
    }

    func debugSeedWorkout(type: WorkoutType) {
        let daysBack = recentHistory.count + 1
        let date = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

        let title: String
        switch type {
        case .recovery: title = "Recovery Day"
        case .endurance: title = "Endurance Ride"
        case .quality: title = "Threshold Intervals"
        }

        let entry = WorkoutHistoryEntry(date: date, title: title, type: type)
        recentHistory.insert(entry, at: 0)
        if recentHistory.count > Self.maxHistoryCount {
            recentHistory = Array(recentHistory.suffix(Self.maxHistoryCount))
        }
        store.saveWorkouts(Array(recentHistory))
    }

    func debugClearHistory() {
        recentHistory.removeAll()
        store.saveWorkouts([])
    }
    #endif

    private func appendToHistory(recommendation: WorkoutRecommendation, checkIn: CheckIn) {
        let entry = WorkoutHistoryEntry(
            title: recommendation.title,
            type: recommendation.type,
            checkIn: checkIn,
            qualitySubtype: recommendation.qualitySubtype
        )
        recentHistory.append(entry)
        if recentHistory.count > Self.maxHistoryCount {
            recentHistory.removeFirst(recentHistory.count - Self.maxHistoryCount)
        }
        store.saveWorkouts(Array(recentHistory))
    }

    private func persist(checkIn: CheckIn) {
        if let data = try? JSONEncoder().encode(checkIn) {
            defaults.set(data, forKey: Keys.checkIn)
        }
        defaults.set(Date(), forKey: Keys.checkInDate)
    }

    // MARK: - Recommendation Engine

    private let engine = RecommendationEngine()

    private func buildMemorySummary() -> TrainingMemorySummary {
        TrainingMemoryBuilder.build(
            history: recentHistory,
            rides: store.finishedRides()
        )
    }

    private func generateRecommendation(for checkIn: CheckIn) -> WorkoutRecommendation {
        let inputs = RecommendationEngine.Inputs(
            profile: userProfile,
            checkIn: checkIn,
            recentHistory: recentHistory,
            memorySummary: buildMemorySummary(),
            activeIntent: store.activeIntent(),
            upcomingContext: upcomingContextSummary,
            coachNotes: coachNotes,
            progression: progressionState,
            approach: trainingApproach
        )
        let result = engine.recommend(for: inputs)

        AnalyticsService.shared.track(.recommendationGenerated, properties: [
            "type": result.type.rawValue,
            "quality_subtype": result.qualitySubtype?.rawValue ?? "none",
            "step_count": result.steps.count,
            "has_extras": !result.optionalExtras.isEmpty,
            "history_count": AnalyticsProperties.countBucket(recentHistory.count),
            "has_intent": inputs.activeIntent != nil
        ])

        return result
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
