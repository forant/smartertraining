# Screenshot / Demo Seeding — Implementation Summary

## A. Implementation summary

Debug-only seeding infrastructure that bulk-populates real production models — `UserProfile`, `WorkoutHistoryEntry`, `CompletedWorkout`, `ProgressionState`, `CoachNotes`, `CoachReflection`, `TrainingApproach`, `ShortTermTrainingIntent` — and lets the real app UI render naturally. No mock views, no screenshot-only types.

Trigger is a launch argument. The seeder runs at the very end of `AppState.init` under `#if DEBUG`, wipes any existing local state, applies the seed, and routes the rest of the boot through the production engine. Production builds compile this code out entirely.

The factories produce realistic, deterministic telemetry — realistic HR drift, power sawtooth across intervals, cadence variation — so charts render believably without obvious synthetic patterns.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/ScreenshotFactory.swift` | **New, `#if DEBUG`.** Factories for `UserProfile`, `CheckIn`, `WorkoutHistoryEntry`, `ProgressionState`, `CoachNotes`, `CompletedWorkout` (with `SyntheticSamples` generator), and `CoachReflection`. Deterministic given start time + FTP. |
| `SmarterTraining/ScreenshotSeeder.swift` | **New, `#if DEBUG`.** `ScreenshotSeed` struct, `ScreenshotSeeder` enum with five scenarios + appearance override parsing. Launch-arg-driven. |
| `SmarterTraining/Models.swift` | New `#if DEBUG` method `AppState.applyScreenshotSeed(_:)` that wipes state and applies the seed inside the file scope where `private(set)` properties are writable. `AppState.init` invokes `ScreenshotSeeder.applyIfRequested(to:)` at the end of init under `#if DEBUG`. |
| `SmarterTraining/SmarterTrainingApp.swift` | New `screenshotColorScheme` computed property (`#if DEBUG`) reads the appearance override and applies `.preferredColorScheme(.light/.dark)` to ContentView. Returns `nil` in release builds. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | 18 new tests across `ScreenshotSeederTests` and `ScreenshotFactoryTests`: launch-arg parsing, scenario construction, realistic-sample shape, sample determinism, power range sanity, progression-state assembly. |

## C. Available seed scenarios

| Scenario | Launch argument | What it surfaces |
|---|---|---|
| Today Recommendation | `-seedTodayRecommendation` | Power-athlete profile + fresh check-in + 6-day history + stable progression + balanced approach. Engine lands on a quality recommendation with the full WHY THIS + WHAT MATTERS TODAY + LIKELY TOMORROW stack populated. |
| Adaptive Coaching | `-seedAdaptiveCoaching` | Same profile + a completed threshold ride from 2 hours ago + a saved CoachReflection ("Yes, sustainable" answer with validation copy) + advanced progression + ambitious approach + `.right` feedback on today's history. Drives the completed-state hero card, charts, and the SavedCoachReflectionCard. |
| Recovery Day | `-seedRecoveryDay` | Consistent-endurance profile + low-readiness check-in (Okay/Heavy/Low + Poor sleep flag) + sustainable approach + a `poorSleepRecently` coach note. Engine returns `.recovery`. Calm rationale, calm guidance, no progression framing. |
| Progression State | `-seedProgression` | Power-athlete profile + advanced progression (8+ confident successes in threshold, 4 in VO2) + ambitious approach. Reason copy includes "push progression slightly" framing. |
| Coach Settings | `-seedCoachSettings` | Consistent-endurance profile + moderate check-in + realistic coach notes ("Cardio feels strong but my legs fatigue first…" with `legsFatigueFirst` + `moreWeekendAvailability` tags). Coach Notes entry card shows its populated state; Settings → Coach Settings has visible content. |

## D. Launch arguments

Scenario triggers (one at a time):

```
-seedTodayRecommendation
-seedAdaptiveCoaching
-seedRecoveryDay
-seedProgression
-seedCoachSettings
```

Appearance overrides (orthogonal, can combine with any scenario):

```
-forceLightMode
-forceDarkMode
```

Example invocation in an Xcode scheme's Run / Arguments tab:

```
-seedAdaptiveCoaching -forceLightMode
```

Production builds: every line in the seeder, factory, and `applyScreenshotSeed` is wrapped in `#if DEBUG`. Release builds never see them.

## E. Seed architecture overview

```
[ launch arguments ]
       |
       v
ScreenshotSeeder.applyIfRequested(to: appState)
       |
       v
ScreenshotSeeder.scenario(from:) -> Scenario?
       |
       v
ScreenshotSeeder.build(scenario) -> ScreenshotSeed
       |
       v
appState.applyScreenshotSeed(seed)   [Models.swift, #if DEBUG]
       |
       +-- deleteAllLocalData()              wipe
       +-- completeOnboarding(profile)       skip onboarding gate
       +-- setCoachNotes(notes)              persist notes
       +-- setTrainingApproach(approach)     persist approach
       +-- progressionState = ...            persist progression
       +-- recentHistory = ...               persist history
       +-- store.saveRide(ride)              persist ride(s)
       +-- store.saveIntent(intent)          persist intent
       +-- submit(checkIn: ...)              triggers real engine
       +-- submitFeedback(...)               optional feedback for completed scenarios
       |
       v
[ AppState.init completes -> ContentView renders real UI off real state ]
```

The seeder operates exclusively via existing AppState API (plus a few direct `private(set)` assignments inside the file). It does not touch the engine, the reason builder, the LikelyTomorrow builder, the ExecutionGuidance builder, the CoachReflection generator, or any UI component. Every card the user sees post-seed is the same code path a real athlete sees.

## F. Example screenshot flows

**App Store hero shot (Adaptive Coaching)**

```
Xcode scheme args: -seedAdaptiveCoaching -forceLightMode
```

Renders:
1. TodayView opens with CompletedHeroCard showing today's threshold ride title and "View Summary" button.
2. Charts section shows realistic power + HR sawtooth across the 45-min session.
3. Coach Reflection summary card displays the saved Q&A: "Did the effort feel sustainable through the set?" → "Yes" → coach validation referencing prior threshold work.
4. Tapping View Summary opens the WorkoutDetailView with the same data + the SavedCoachReflectionCard.

**Recommendation card hero (Today Recommendation)**

```
Xcode scheme args: -seedTodayRecommendation
```

Renders:
1. TodayView opens with WorkoutHeroCard showing a tier-aware quality recommendation.
2. "Why This" card explains the choice based on readiness + history.
3. "What matters today" card adds execution guidance with stable-tier smoothness phrasing.
4. Likely Tomorrow inline label hints at the next probable day.
5. Workout breakdown card lists warmup / main / cooldown with the "Total Workout Time" footer line.

**Calm/Sustainable hero (Recovery Day)**

```
Xcode scheme args: -seedRecoveryDay -forceLightMode
```

Renders:
1. WorkoutHeroCard with "Easy Spin" or "Recovery Day" title.
2. Reason copy mentions poor sleep + heavy legs.
3. Execution guidance: "The goal today is circulation and recovery, not fitness gain…"
4. Coach Notes entry card shows the populated "Sleep has been inconsistent recently" summary.

## G. Future extension opportunities

- **More scenarios.** Add `-seedFirstQualityDay`, `-seedReturningAfterBreak`, `-seedBigRideTomorrow`, `-seedKneeSensitivity`, etc. New scenarios are ~20 lines of seed construction each.
- **Workout-runtime seeding.** Real runtime requires a connected trainer, but a screenshot path could seed `RideSessionView` directly with a frozen in-flight state (current interval index, recent samples, ERG target). Would need a small mock injection point into the runtime — out of Phase 1 scope.
- **Deep-link triggers.** Add a custom URL scheme (`smartertraining://seed/adaptiveCoaching`) so screenshots can be re-applied from the home screen without rebuilding. Same scenario IDs, different entry point.
- **Persistent re-seed.** Currently a seed persists until the user manually resets — a future `-resetAfterScreenshot` flag could wipe data on app background.
- **Fastlane / xcrun automation.** With launch arguments stable, an automation script can drive `xcrun simctl boot ... && xcrun simctl launch --args -seedX simulator app.bundle.id` to generate the entire App Store screenshot set headlessly.
- **AI integration scenarios.** When backend AI is wired, add seeds that include AI-generated `PostWorkoutReflection.sessionEvaluation` text so screenshots show the AI-coach experience too.

## Test results

- **18/18** new tests pass:
  - 6 launch-arg parsing tests (every scenario + unknown + empty + both appearance overrides).
  - 6 scenario-construction tests (every scenario produces a non-empty seed; specific approach / coach-note / progression invariants).
  - 6 factory tests (history span, quality subtype presence, sample count, sample shape, deterministic regeneration, power range sanity, progression assembly).
- **All prior tests still pass** — no production code path changed.

## Constraint compliance

- **Production never sees this code:** every seeder/factory line is `#if DEBUG`. Two files are entirely wrapped. The `AppState.applyScreenshotSeed` method is wrapped. The launch-arg check in `AppState.init` is wrapped. The appearance override in `SmarterTrainingApp` is wrapped with an `#else return nil`.
- **No fake mock UI:** zero new SwiftUI views. The seeder mutates `AppState` and `LocalStore` then the existing UI renders.
- **Real models only:** every field on every seeded model is the same type a real user generates. No `ScreenshotCompletedWorkout` lookalike.
- **Deterministic:** `SyntheticSamples` uses an arithmetic-noise function (`(n*9301 + 49297) % 233`) keyed to the sample second, so the same start time + FTP produces byte-identical samples across runs. Verified by `sampleGenerationIsDeterministic`.
- **No production persistence touched** when running without a seed argument: `applyIfRequested` returns early when `scenario(from:)` returns nil.
- **Account deletion clears seeded state:** `applyScreenshotSeed` itself starts with `deleteAllLocalData()`, and the user can clear seeded state via the normal Settings → Delete account flow.
- **No shipping debug UI:** seeding is invisible from inside the app — the only signal is the seeded data showing up.
