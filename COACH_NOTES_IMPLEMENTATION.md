# Coach Notes — Implementation Summary

## A. Implementation summary

Coach Notes is a persistent, lightweight athlete-context layer. It's a single `CoachNotes` value stored in `UserDefaults` containing a freeform note and an optional set of pre-defined tags. It surfaces on TodayView as a subtle entry card and is edited through a focused sheet. The same data flows into the recommendation engine and the LikelyTomorrow preview as **soft biases** — never overrides — so the engine stays explainable. The whole thing is heuristic, no ML, no clinical framing.

When notes are empty, the entry card asks "What should your coach know?" The sheet shows curated example sentences below the input until the user starts typing. Saving once turns the entry card into a quiet summary — "Legs fatigue first · 2 tags" — which reinforces "the app remembers me." Notes can be edited at any time. They survive launches; they get wiped along with everything else when the user deletes their data.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/CoachNotes.swift` | **New.** `CoachNotes` value type, `CoachNoteTag` enum (8 cases), summary-line helper. |
| `SmarterTraining/CoachNotesView.swift` | **New.** `CoachNotesEntryCard` (TodayView row) + `CoachNotesSheet` (multi-line input + tag chips + example list). |
| `SmarterTraining/Models.swift` | `AppState.coachNotes` property, `setCoachNotes(_:)` (persist + analytics + refresh recommendation), wired into `deleteAllLocalData`, threaded into `RecommendationEngine.Inputs`. |
| `SmarterTraining/RecommendationEngine.swift` | `Inputs.coachNotes` field. Three tag biases inside `chooseQualitySubtype`: `vo2MentallyDifficult` removes VO2, `kneeSensitivity` de-prioritizes ME, `legsFatigueFirst` promotes ME to the front. Applied before the variety filter so notes shape *what's in rotation*, not whether rotation happens. |
| `SmarterTraining/LikelyTomorrowPreview.swift` | `preview(...)` and `predictedQualitySubtype(...)` accept `coachNotes`; same three biases applied to the rotation order. |
| `SmarterTraining/TodayView.swift` | Coach Notes entry card placed below upcoming context. Sheet wired. `likelyTomorrowPreview` now passes `coachNotes`. |
| `SmarterTraining/TrainerIntegration/RideSessionView.swift` | `likelyTomorrowPreview` passes `appState.coachNotes`. |
| `SmarterTraining/Analytics/AnalyticsEvent.swift` | New event `coachNotesUpdated = "coach_notes_updated"`. Tracked with `has_note` (bool) and `tag_count` (int) — never the note content. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | 13 new `CoachNotesTests` covering model, encoding, engine biases, LikelyTomorrow integration, analytics raw value. |

## C. Persistence structure

```swift
struct CoachNotes: Codable, Equatable {
    var freeformNote: String
    var tags: Set<CoachNoteTag>
    var updatedAt: Date?

    static let empty: CoachNotes
    var isEmpty: Bool
    var summaryLine: String     // for the entry card
}

enum CoachNoteTag: String, Codable, CaseIterable {
    case kneeSensitivity
    case legsFatigueFirst
    case limitedWeekdayTime
    case moreWeekendAvailability
    case poorSleepRecently
    case returningAfterBreak
    case strongAerobicFitness
    case vo2MentallyDifficult
}
```

Stored under `UserDefaults` key `"coachNotes"` as JSON. Wiped on `AppState.deleteAllLocalData`.

## D. Example recommendation adjustments

| Tag(s) on file | Today's pick (peak readiness, 60 min) | Why |
|---|---|---|
| (none) | **VO2** | baseline |
| `vo2MentallyDifficult` | **Over/Unders** | VO2 stripped from the list before variety filter |
| `kneeSensitivity` | **VO2** then **Over/Unders** next time | ME stays out of the rotation when alternatives exist |
| `legsFatigueFirst` (good but not peak, 60 min) | **Muscular Endurance** | ME promoted from index 3 to index 0 |
| `legsFatigueFirst` + `vo2MentallyDifficult` | **ME** first, **VO2** never | both biases compose |
| `kneeSensitivity` + `legsFatigueFirst` | **VO2 / Threshold / Over/Unders** rotation, ME never | kneeSensitivity wins (more cautious) |

The LikelyTomorrow predictor honors the same biases — `vo2MentallyDifficult` means the preview never says "VO2 tomorrow."

## E. UI states

**Entry card, empty state** (TodayView, below upcoming context):

```
[icon] Coach context
       What should your coach know?
       >
```

A muted card, single tappable row. No call-to-action button, no progress indicator.

**Entry card, populated:**

```
[icon] Coach context
       Legs fatigue first on long rides * 2 tags
       >
```

The summary collapses the first sentence plus a tag count, so users see at a glance that their context is on file without having to re-read it.

**Sheet, empty state:**

```
Coach context
What should your coach know?
Anything that helps shape your training over time. Add what's true, skip what isn't.

[ multiline text field with "Type a note for your coach" placeholder ]

FOR EXAMPLE
- Cardio feels strong but my legs fatigue first.
- My knees sometimes flare up during low-cadence work.
- Work stress has been high lately.
- I usually have more time on weekends.
- I mentally struggle with VO2 intervals.
- Sleep has been inconsistent recently.
- Long steady rides feel easier than punchy efforts.

OPTIONAL TAGS
( Knee sensitivity ) ( Legs fatigue first ) ( Limited weekday time )
( More weekend availability ) ( Poor sleep recently ) ( Returning after break )
( Strong aerobic fitness ) ( VO2 mentally difficult )

[Cancel]                                                            [Save]
```

The example list disappears the moment the user types anything into the field. Chips toggle on tap and round-trip through `ContextChip` / `FlowLayout` (the existing reusable components from check-in).

## F. Future extension opportunities

- **AI / backend plumbing.** `AICoachService` and `PostWorkoutReflectionService` send a dictionary payload to the backend today. Adding `"coach_notes": { "note": ..., "tags": [...] }` to those payloads would let the AI coach use the persistent context when generating reflections and "why this" explanations — without anything more on the client.
- **Reason builder integration.** `RecommendationEngine.buildQualityReason` could mention the relevant note when applicable: *"...muscular endurance fits given that legs fatigue first for you."* — a one-line surface where the personalization shows up explicitly. Easy to add when the design is ready.
- **Tag library evolution.** The eight starter tags are intentionally narrow. New ones (e.g. `breathingPattern`, `lowMorningEnergy`, `cyclingFootIssues`) can be added without migration since `CoachNoteTag` is rawValue-keyed and `Set<CoachNoteTag>` decodes unknown tags as not-present.
- **Per-session note prompt.** A second freeform layer keyed by today's check-in could capture *transient* context ("travel-week, slept badly") without overwriting the persistent coach notes. Already a clean separation point in the model.
- **Tag-driven duration ceiling.** `limitedWeekdayTime` and `moreWeekendAvailability` aren't yet wired into the engine (they're available as data only). When ready, both could shape `LikelyTomorrowBuilder`'s duration guidance based on the predicted day-of-week. Left out for now to keep "no calendar logic" intact.
- **AI-suggested tags.** When the freeform note clearly maps onto a tag the user hasn't selected, the backend could suggest the tag for one-tap confirmation. Keeps the user in control while reducing manual taxonomy work.

## Test results

- **13/13** new `CoachNotesTests` pass (model, persistence, engine biases, LikelyTomorrow integration, analytics raw value).
- **40/40** prior tests pass (quality subtype audit + selection + LikelyTomorrow + account deletion + analytics event uniqueness) — confirming the new feature wipes correctly on account deletion and the new event slots cleanly into the existing analytics registry.
