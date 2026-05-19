# Coach Reflection — Implementation Summary

## A. Implementation summary

A lightweight, structured post-workout reflective coaching layer. After a workout finishes, a single targeted prompt appears below the existing summary / charts / Likely Tomorrow stack. The athlete answers with a chip, the coach responds with a short validating line that references their history when possible, and the card collapses. One interaction per workout. No chat, no thread, no journaling.

The pipeline is fully deterministic: templates driven by workout signals, layered with optional history and coach-note references. The "conversation" is not the product. The product is the structured signal we extract, the moment of validation, and the longitudinal context we build for future coaching.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/CoachReflection.swift` | **New.** Types (`CoachReflectionPromptKind`, `CoachReflectionResponse`, `CoachReflectionPrompt`, `CoachReflection` record). `CoachReflectionGenerator` (signal-driven prompt picker). `CoachReflectionValidator` (baseline + history-aware validation lines). |
| `SmarterTraining/CoachReflectionCard.swift` | **New.** Interactive `CoachReflectionCard` (prompt -> validation -> collapsed phases) and read-only `SavedCoachReflectionCard` for the history detail view. |
| `SmarterTraining/StravaIntegration/CompletedWorkout.swift` | New `coachReflection: CoachReflection?` field with default-nil decoder for backward compatibility. |
| `SmarterTraining/TrainerIntegration/RideSessionView.swift` | Inserts `CoachReflectionCard` into the summary phase below the Likely Tomorrow / reflection cards. Generator runs against the just-finished workout + recent rides + active recommendation + coach notes. Save callback writes the reflection back onto the `CompletedWorkout` via `LocalStore.saveRide`. |
| `SmarterTraining/WorkoutDetailView.swift` | Renders `SavedCoachReflectionCard` in the history sheet whenever the ride has a saved reflection. |
| `SmarterTraining/Analytics/AnalyticsEvent.swift` | Two new events: `coachReflectionShown` and `coachReflectionAnswered`. Properties carry `prompt_kind` and `response` only — never the freeform note. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | New `CoachReflectionTests` (15 tests): generator selection, validator coverage and history layering, Codable round-trip, backward-compatible decode, analytics raw values. |

## C. Reflection architecture overview

```
[CompletedWorkout]   [WorkoutRecommendation]   [recent CompletedWorkouts]   [CoachNotes]
        \                    |                          |                       /
         \-------- CoachReflectionGenerator.generate(...) ---------/
                                  |
                                  v
                       CoachReflectionPrompt
                       (kind, question, choices)
                                  |
              [user taps a chip in CoachReflectionCard]
                                  |
                                  v
        [CoachReflectionValidator.validate(kind, response, context)]
                                  |
                                  v
                        Validation copy (string)
                                  |
                                  v
                          CoachReflection record
                                  |
        --- persisted onto CompletedWorkout.coachReflection ---
                                  |
                                  v
                  Card collapses to "Reflection saved"
```

Three deterministic pieces:

1. **Generator** picks at most one prompt kind based on signals:
   - Recovery workout: `nil` (don't push reflection on recovery days)
   - Workout duration < 75% of expected: `shortenedReason`
   - VO2 with prior VO2 history: `repeatability`
   - Threshold with prior threshold history: `sustainability`
   - Muscular Endurance: `effortLimit`
   - Over/Unders: `controlLateInWorkout`
   - Tempo: `sustainability`
   - Endurance / fallback: `effortLimit`

2. **Validator** returns a baseline line per `(promptKind, response)` pair, optionally extended with one history reference when context supports it. References can come from:
   - Coach notes (`legsFatigueFirst`, `vo2MentallyDifficult`, `limitedWeekdayTime`, `poorSleepRecently`, `strongAerobicFitness`)
   - Prior same-subtype quality count from history
   - Prior-same-response flag (placeholder for future enrichment)

3. **Card** is a small three-phase state machine: `prompt` -> `validation` -> `collapsed`. Saving fires an `onSave` callback that writes the `CoachReflection` onto the `CompletedWorkout` and re-saves it through `LocalStore.saveRide`.

## D. Example reflection flows

### Flow 1 — VO2 workout, athlete has prior VO2 history, answers "More repeatable"

**Prompt shown:** "Did this feel more repeatable than your recent VO2 sessions?"

**Choices:** More repeatable / About the same / Harder

**Athlete picks:** More repeatable

**Coach validation:** "Repeatability landing easier is a meaningful sign your engine is adapting. Compared to your last few sessions of this kind, that's a positive trend in repeatability."

**Persisted as:** `CoachReflection(promptKind: .repeatability, response: .easier, ...)`

### Flow 2 — Muscular Endurance, athlete has `legsFatigueFirst` coach note, answers "Legs"

**Prompt:** "Did your legs or breathing limit you first?"

**Choices:** Legs / Breathing / Both / Neither

**Athlete picks:** Legs

**Validation:** "Noted — legs giving in first is common on this kind of work. That's consistent with what you've told me about your legs going first — useful as we tune the work."

### Flow 3 — Workout cut short, athlete has `limitedWeekdayTime` note, answers "Time"

**Prompt:** "You shortened today's workout. Mostly time-constrained or fatigue-constrained?"

**Choices:** Time / Fatigue / Both

**Athlete picks:** Time

**Validation:** "Real-life days happen. Showing up for what fit is the point. Matches what you've told me about weekday time — we can lean shorter on these days."

### Flow 4 — Over/Unders, no prior over-unders, answers "Yes"

**Prompt:** "Did the overs feel more controlled this time around?"

**Choices:** Yes / Somewhat / Not really

**Athlete picks:** Yes

**Validation:** "Late-set control suggests the lactate handling is coming together."

### Flow 5 — Recovery day

No prompt is generated. Recovery is for letting things settle, not for extracting more reflection from the athlete.

## E. Example longitudinal validation responses

| Context signal | Validation suffix appended |
|---|---|
| `legsFatigueFirst` + response `.legs` | "That's consistent with what you've told me about your legs going first — useful as we tune the work." |
| `strongAerobicFitness` + response `.breathing` | "Your aerobic side is strong, so getting breathing-limited usually means the intensity is in the right zone." |
| Prior VO2 ride + response `.easier` (repeatability) | "Compared to your last few sessions of this kind, that's a positive trend in repeatability." |
| `vo2MentallyDifficult` + response `.harder` (repeatability) | "You've mentioned VO2 can feel mentally tough — getting through the session is still the win." |
| Prior threshold ride + response `.yes` (sustainability) | "That's a step forward compared to the last few sessions of this kind." |
| `limitedWeekdayTime` + response `.time` (shortened) | "Matches what you've told me about weekday time — we can lean shorter on these days." |
| `poorSleepRecently` + response `.fatigue` (shortened) | "Sleep has been inconsistent lately — that's a credible reason to dial it back." |
| Prior over/unders + response `.yes` (control late) | "That looks smoother than recent over/under work — a good sign." |

Tone hedges: "suggests", "looks like", "consistent with", "a meaningful sign", "lines up with". Never "you crushed it" or fake certainty.

## F. Persistence model

```swift
struct CoachReflection: Codable, Identifiable, Equatable {
    let id: UUID
    let workoutId: UUID                       // links to CompletedWorkout.id
    let promptKind: CoachReflectionPromptKind
    let question: String                      // the exact prompt shown
    let response: CoachReflectionResponse     // the chip the athlete picked
    let responseLabel: String                 // user-facing label of that chip
    let note: String?                         // optional freeform follow-up
    let validation: String                    // the coach line shown back
    let createdAt: Date
}
```

Stored on `CompletedWorkout.coachReflection` (`Codable, Optional`). The whole ride re-encodes via `LocalStore.saveRide`. Backward compatible — older rides decode with `coachReflection == nil`. Wiped by `LocalStore.deleteAllData` along with all other ride data, so account deletion clears reflection history without extra plumbing.

`CoachReflectionPromptKind` and `CoachReflectionResponse` are `String`-rawValue enums so the persisted form stays inspectable.

## G. Future extension opportunities

- **Adaptive progression hook.** Repeated `legs` responses on `effortLimit` for ME sessions are a clear "muscular endurance progression is paying off" signal — feed that into a future ME rep/duration progression model. The shape is already in `recentQualitySubtypes7d` + `coachReflection.response`.
- **Reflection-aware recommendation.** Repeated `.time` shortened-reason responses on weekdays should bias `LikelyTomorrowBuilder` toward shorter weekday durations. The data is already persisted; just needs to be read in the builder.
- **Backend forwarding.** `AICoachService` and `PostWorkoutReflectionService` can include the most recent saved reflection in their payload — gives the AI coach the athlete's own self-report when generating the next "why this" or next-day guidance.
- **Cadence / HR / power signals.** The generator could pick `controlLateInWorkout` even when not on over/unders if late-interval HR drift is small relative to early HR drift. Stub `controlLateInWorkout` exists; just needs the signal computation.
- **Prior-same-response enrichment.** `CoachReflectionValidator.Context.priorSameResponse` is wired but not yet populated. Reading the last N reflections of the same `promptKind` would let the validator say "you've answered this way before" with confidence.
- **Light streaks.** "You've shown up for 4 weeks in a row, even with shortened sessions" — a reflection-history-driven affirmation. Gentle, not gamified.

## Test results

- **15/15** new `CoachReflectionTests` pass (generator selection across all subtypes + recovery + shortened, validator coverage of all 16 prompt/response baselines, four history-layering paths, persistence round-trip, backward-compatible decode, analytics raw values).
- **42/42** prior tests pass (CoachNotes, LikelyTomorrow, QualitySubtype audit, analytics uniqueness, CompletedWorkout reflection fields) — confirming no regression and that the new field decodes cleanly alongside the existing `PostWorkoutReflection`.

## Constraint compliance

- One reflection interaction per workout (saved state persists; card does not re-prompt).
- No open-ended chat — chips only, with one optional short note field.
- No infinite thread — interaction ends at `collapsed`.
- No AI personality / branding — coach voice is grounded copy in deterministic templates.
- No gamification, no celebration language ("crushed it", "amazing", etc.).
- Skipped on recovery days so reflection lands on training-stress days only.
- Existing `PostWorkoutReflection` (AI session evaluation) is untouched — the new system is parallel, not a replacement.
