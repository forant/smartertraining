import Foundation
import Testing
@testable import SmarterTraining

// MARK: - Event Type Tests

struct UpcomingContextEventTypeTests {

    @Test func allCasesHaveDisplayText() {
        for type in UpcomingContextEventType.allCases {
            #expect(!type.displayText.isEmpty)
        }
    }

    @Test func allCasesHaveIcon() {
        for type in UpcomingContextEventType.allCases {
            #expect(!type.icon.isEmpty)
        }
    }

    @Test func allCasesHaveReasonLabel() {
        for type in UpcomingContextEventType.allCases {
            #expect(!type.reasonLabel.isEmpty)
        }
    }

    @Test func highIntensityTypesAreCorrect() {
        let highIntensity = UpcomingContextEventType.allCases.filter(\.isHighIntensity)
        #expect(highIntensity.contains(.bigOutdoorRide))
        #expect(highIntensity.contains(.raceOrEvent))
        #expect(highIntensity.contains(.wantToPushHarder))
        #expect(highIntensity.count == 3)
    }

    @Test func constraintTypesAreCorrect() {
        let constraints = UpcomingContextEventType.allCases.filter(\.isConstraint)
        #expect(constraints.contains(.travel))
        #expect(constraints.contains(.busyWorkday))
        #expect(constraints.contains(.familyCommitment))
        #expect(constraints.contains(.limitedTime))
        #expect(constraints.count == 4)
    }

    @Test func rangeContextTypesAreCorrect() {
        let range = UpcomingContextEventType.allCases.filter(\.isRangeContext)
        #expect(range.contains(.travel))
        #expect(range.contains(.recoveryFocused))
        #expect(range.contains(.familyCommitment))
        #expect(range.count == 3)
    }

    @Test func anchoredTypesAreNotRangeContext() {
        #expect(!UpcomingContextEventType.bigOutdoorRide.isRangeContext)
        #expect(!UpcomingContextEventType.raceOrEvent.isRangeContext)
        #expect(!UpcomingContextEventType.busyWorkday.isRangeContext)
        #expect(!UpcomingContextEventType.wantToPushHarder.isRangeContext)
    }

    @Test func showsImpactSkipsRecoveryAndPushHarder() {
        #expect(!UpcomingContextEventType.recoveryFocused.showsImpact)
        #expect(!UpcomingContextEventType.wantToPushHarder.showsImpact)
        #expect(UpcomingContextEventType.travel.showsImpact)
        #expect(UpcomingContextEventType.bigOutdoorRide.showsImpact)
    }

    @Test func rawValuesAreSnakeCase() {
        for type in UpcomingContextEventType.allCases {
            #expect(type.rawValue == type.rawValue.lowercased())
            #expect(!type.rawValue.contains(" "))
        }
    }
}

// MARK: - Impact Tests

struct UpcomingContextImpactTests {

    @Test func allCasesHaveDisplayText() {
        for impact in UpcomingContextImpact.allCases {
            #expect(!impact.displayText.isEmpty)
        }
    }

    @Test func rawValuesRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for impact in UpcomingContextImpact.allCases {
            let data = try encoder.encode(impact)
            let decoded = try decoder.decode(UpcomingContextImpact.self, from: data)
            #expect(decoded == impact)
        }
    }
}

// MARK: - Duration Tests

struct UpcomingContextDurationTests {

    @Test func allCasesHaveDisplayText() {
        for dur in UpcomingContextDuration.allCases {
            #expect(!dur.displayText.isEmpty)
        }
    }

    @Test func approximateDaysAreReasonable() {
        #expect(UpcomingContextDuration.oneToTwoDays.approximateDays == 2)
        #expect(UpcomingContextDuration.threeToFiveDays.approximateDays == 4)
        #expect(UpcomingContextDuration.aboutAWeek.approximateDays == 7)
        #expect(UpcomingContextDuration.notSure.approximateDays == 3)
    }

    @Test func rawValuesRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for dur in UpcomingContextDuration.allCases {
            let data = try encoder.encode(dur)
            let decoded = try decoder.decode(UpcomingContextDuration.self, from: data)
            #expect(decoded == dur)
        }
    }

    @Test func rawValuesAreSnakeCase() {
        for dur in UpcomingContextDuration.allCases {
            #expect(dur.rawValue == dur.rawValue.lowercased())
            #expect(!dur.rawValue.contains(" "))
        }
    }
}

// MARK: - Event Tests

struct UpcomingContextEventTests {

    private func makeEvent(
        daysFromNow: Int,
        type: UpcomingContextEventType = .bigOutdoorRide,
        impact: UpcomingContextImpact = .moderate,
        duration: UpcomingContextDuration? = nil
    ) -> UpcomingContextEvent {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Calendar.current.startOfDay(for: Date()))!
        return UpcomingContextEvent(date: date, type: type, impact: impact, duration: duration)
    }

    @Test func todayEventIsNotExpired() {
        let event = makeEvent(daysFromNow: 0)
        #expect(!event.isExpired)
        #expect(event.daysFromNow == 0)
        #expect(event.dayLabel == "Today")
    }

    @Test func tomorrowEvent() {
        let event = makeEvent(daysFromNow: 1)
        #expect(!event.isExpired)
        #expect(event.daysFromNow == 1)
        #expect(event.dayLabel == "Tomorrow")
    }

    @Test func futureEventShowsWeekday() {
        let event = makeEvent(daysFromNow: 3)
        #expect(!event.isExpired)
        #expect(event.daysFromNow == 3)
        #expect(!event.dayLabel.isEmpty)
        #expect(event.dayLabel != "Today")
        #expect(event.dayLabel != "Tomorrow")
    }

    @Test func yesterdayAnchoredEventIsExpired() {
        let event = makeEvent(daysFromNow: -1)
        #expect(event.isExpired)
    }

    // MARK: - Range event expiration

    @Test func rangeEventStartedYesterdayStillActive() {
        let event = makeEvent(daysFromNow: -1, type: .travel, duration: .threeToFiveDays)
        #expect(!event.isExpired)
    }

    @Test func rangeEventFullyPassedIsExpired() {
        let event = makeEvent(daysFromNow: -5, type: .travel, duration: .threeToFiveDays)
        #expect(event.isExpired)
    }

    @Test func rangeEventOnLastDayStillActive() {
        let event = makeEvent(daysFromNow: -2, type: .familyCommitment, duration: .threeToFiveDays)
        #expect(!event.isExpired)
    }

    @Test func weekLongEventStartedThreeDaysAgoStillActive() {
        let event = makeEvent(daysFromNow: -3, type: .recoveryFocused, duration: .aboutAWeek)
        #expect(!event.isExpired)
    }

    @Test func weekLongEventStartedEightDaysAgoExpired() {
        let event = makeEvent(daysFromNow: -8, type: .recoveryFocused, duration: .aboutAWeek)
        #expect(event.isExpired)
    }

    // MARK: - Narrative labels

    @Test func anchoredEventNarrativeLabelToday() {
        let event = makeEvent(daysFromNow: 0, type: .bigOutdoorRide)
        #expect(event.narrativeLabel == "Big ride today")
    }

    @Test func anchoredEventNarrativeLabelTomorrow() {
        let event = makeEvent(daysFromNow: 1, type: .busyWorkday)
        #expect(event.narrativeLabel == "Busy workday tomorrow")
    }

    @Test func anchoredEventNarrativeLabelWeekday() {
        let event = makeEvent(daysFromNow: 3, type: .raceOrEvent)
        let label = event.narrativeLabel
        #expect(label.hasPrefix("Race/event "))
        #expect(!label.contains("starting"))
    }

    @Test func rangeEventNarrativeLabelFuture() {
        let event = makeEvent(daysFromNow: 2, type: .travel, duration: .threeToFiveDays)
        let label = event.narrativeLabel
        #expect(label.contains("Travel"))
        #expect(label.contains("starting"))
        #expect(label.contains("3\u{2013}5 days"))
    }

    @Test func rangeEventNarrativeLabelStartingToday() {
        let event = makeEvent(daysFromNow: 0, type: .travel, duration: .oneToTwoDays)
        let label = event.narrativeLabel
        #expect(label.contains("Travel"))
        #expect(label.contains("1\u{2013}2 days"))
    }

    @Test func rangeEventNarrativeLabelAlreadyStarted() {
        let event = makeEvent(daysFromNow: -1, type: .travel, duration: .threeToFiveDays)
        let label = event.narrativeLabel
        #expect(label.contains("Travel"))
        #expect(label.contains("more days"))
    }

    @Test func rangeEventNarrativeLabelWrappingUp() {
        let event = makeEvent(daysFromNow: -3, type: .travel, duration: .threeToFiveDays)
        let label = event.narrativeLabel
        #expect(label.contains("wrapping up"))
    }

    // MARK: - Codable round-trips

    @Test func eventRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = makeEvent(daysFromNow: 2, type: .travel, impact: .hard)
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UpcomingContextEvent.self, from: data)

        #expect(decoded.id == event.id)
        #expect(decoded.type == .travel)
        #expect(decoded.impact == .hard)
    }

    @Test func eventWithDurationRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = makeEvent(daysFromNow: 1, type: .travel, duration: .threeToFiveDays)
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UpcomingContextEvent.self, from: data)

        #expect(decoded.duration == .threeToFiveDays)
    }

    @Test func eventWithNoteRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var event = makeEvent(daysFromNow: 1)
        event.note = "Century ride with the group"

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UpcomingContextEvent.self, from: data)

        #expect(decoded.note == "Century ride with the group")
    }

    @Test func backwardCompatibleDecodingWithoutDuration() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "createdAt": "2025-01-01T00:00:00Z",
            "updatedAt": "2025-01-01T00:00:00Z",
            "date": "2025-01-02T00:00:00Z",
            "type": "travel",
            "impact": "moderate"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(UpcomingContextEvent.self, from: Data(json.utf8))

        #expect(event.type == .travel)
        #expect(event.impact == .moderate)
        #expect(event.duration == nil)
    }
}

// MARK: - Summary Tests

struct UpcomingContextSummaryTests {

    private func makeEvent(
        daysFromNow: Int,
        type: UpcomingContextEventType,
        impact: UpcomingContextImpact = .unknown,
        duration: UpcomingContextDuration? = nil
    ) -> UpcomingContextEvent {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Calendar.current.startOfDay(for: Date()))!
        return UpcomingContextEvent(date: date, type: type, impact: impact, duration: duration)
    }

    @Test func emptyEventsProduceEmptySummary() {
        let summary = UpcomingContextSummary.build(from: [])
        #expect(summary.isEmpty)
        #expect(!summary.hasBigRideSoon)
        #expect(!summary.hasBusyDaySoon)
        #expect(!summary.hasTravelSoon)
        #expect(!summary.wantsToPushHarder)
        #expect(!summary.recoveryFocusedActive)
    }

    @Test func expiredEventsAreExcluded() {
        let expired = makeEvent(daysFromNow: -1, type: .bigOutdoorRide)
        let summary = UpcomingContextSummary.build(from: [expired])
        #expect(summary.isEmpty)
    }

    @Test func farFutureEventsAreExcluded() {
        let farFuture = makeEvent(daysFromNow: 10, type: .bigOutdoorRide)
        let summary = UpcomingContextSummary.build(from: [farFuture])
        #expect(summary.isEmpty)
    }

    @Test func bigRideTomorrow() {
        let event = makeEvent(daysFromNow: 1, type: .bigOutdoorRide, impact: .hard)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasBigRideSoon)
        #expect(summary.daysUntilBigRide == 1)
        #expect(summary.bigRideLabel == "big ride")
    }

    @Test func raceEventDetected() {
        let event = makeEvent(daysFromNow: 3, type: .raceOrEvent, impact: .veryHard)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasBigRideSoon)
        #expect(summary.daysUntilBigRide == 3)
        #expect(summary.bigRideLabel == "race")
    }

    @Test func travelDetected() {
        let event = makeEvent(daysFromNow: 2, type: .travel)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasTravelSoon)
        #expect(summary.daysUntilTravel == 2)
        #expect(!summary.hasBigRideSoon)
    }

    @Test func busyDayDetected() {
        let event = makeEvent(daysFromNow: 0, type: .busyWorkday)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasBusyDaySoon)
        #expect(summary.daysUntilBusyDay == 0)
    }

    @Test func familyCommitmentCountsAsBusyDay() {
        let event = makeEvent(daysFromNow: 1, type: .familyCommitment)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasBusyDaySoon)
        #expect(summary.daysUntilBusyDay == 1)
    }

    @Test func recoveryFocusedDetected() {
        let event = makeEvent(daysFromNow: 0, type: .recoveryFocused)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.recoveryFocusedActive)
        #expect(!summary.wantsToPushHarder)
    }

    @Test func wantsToPushHarderDetected() {
        let event = makeEvent(daysFromNow: 0, type: .wantToPushHarder)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.wantsToPushHarder)
        #expect(!summary.recoveryFocusedActive)
    }

    @Test func limitedTimeDetected() {
        let event = makeEvent(daysFromNow: 1, type: .limitedTime)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasLimitedTimeSoon)
    }

    @Test func hardEventCountIncludesHighIntensityAndHardImpact() {
        let events = [
            makeEvent(daysFromNow: 1, type: .bigOutdoorRide, impact: .moderate),
            makeEvent(daysFromNow: 2, type: .travel, impact: .hard),
            makeEvent(daysFromNow: 3, type: .busyWorkday, impact: .light),
        ]
        let summary = UpcomingContextSummary.build(from: events)

        #expect(summary.upcomingHardEventCount == 2)
    }

    @Test func nearestBigRideWins() {
        let events = [
            makeEvent(daysFromNow: 5, type: .bigOutdoorRide),
            makeEvent(daysFromNow: 2, type: .raceOrEvent),
        ]
        let summary = UpcomingContextSummary.build(from: events)

        #expect(summary.daysUntilBigRide == 2)
        #expect(summary.bigRideLabel == "race")
    }

    @Test func multipleTypesDetectedSimultaneously() {
        let events = [
            makeEvent(daysFromNow: 1, type: .bigOutdoorRide, impact: .hard),
            makeEvent(daysFromNow: 0, type: .busyWorkday),
            makeEvent(daysFromNow: 3, type: .travel),
        ]
        let summary = UpcomingContextSummary.build(from: events)

        #expect(summary.hasBigRideSoon)
        #expect(summary.hasBusyDaySoon)
        #expect(summary.hasTravelSoon)
        #expect(summary.events.count == 3)
    }

    // MARK: - Range event summary integration

    @Test func activeRangeEventIncludedInSummary() {
        let event = makeEvent(daysFromNow: -1, type: .travel, duration: .threeToFiveDays)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.hasTravelSoon)
        #expect(!summary.isEmpty)
    }

    @Test func expiredRangeEventExcludedFromSummary() {
        let event = makeEvent(daysFromNow: -5, type: .travel, duration: .threeToFiveDays)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.isEmpty)
    }

    @Test func recoveryFocusedRangeStillActive() {
        let event = makeEvent(daysFromNow: -2, type: .recoveryFocused, duration: .aboutAWeek)
        let summary = UpcomingContextSummary.build(from: [event])

        #expect(summary.recoveryFocusedActive)
    }
}
