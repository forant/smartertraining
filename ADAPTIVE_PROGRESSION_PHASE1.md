# Adaptive Progression — Phase 1

## A. Implementation summary

Persistent coaching memory per quality subtype. The engine now remembers what level the athlete is at in each of the five quality subtypes (VO2, Threshold, Muscular Endurance, Tempo, Over/Unders) and prescribes accordingly. Consecutive confident successes earn an advancement; consecutive struggles earn a regression. State updates after every quality-day feedback and persists to `UserDefaults`. The recommendation engine reads the tier and picks a tier-specific workout template; the reason copy explains why today's variant looks the way it does.

The system is conservatively progressive. Two successes in a row required to advance (not one). Two struggles required to regress (not one). Mixed signals hold. Builders only progress at sufficient time budgets — short-time sessions still get the trainer-friendly compact template regardless of tier.

No ML, no opaque scoring, no periodization. Just per-subtype counters + deterministic transitions.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/ProgressionState.swift` | **New.** `ProgressionTier` enum (starter / progressing / stable / advanced). `SubtypeProgressionState`. `ProgressionState` container with `applying(signal:to:)`. `ProgressionSignal` (confidentSuccess / mixed / struggle). `ProgressionSignalClassifier` (maps `WorkoutFeedback` + optional `CoachReflection` to a signal). |
| `SmarterTraining/RecommendationEngine.swift` | `Inputs.progression` field. `qualityWillingness(for:progression:)` overload — adds +1 to willingness when 2+ subtypes are at stable or better. `buildWorkout(... tier:)` overload threads tier through. All five subtype builders rewritten with tier-aware main sets (starter / progressing / stable / advanced) and time-fallback resolution via `resolveTier(...)`. `buildReason(... tier:)` overload appends `progressionFraming(...)` explainability line at progressing/stable/advanced tiers. |
| `SmarterTraining/Models.swift` | `AppState.progressionState` (`@Observable`, persisted to UserDefaults under `progressionState`). `submitFeedback` hooks `applyProgressionUpdate(...)` which reads the latest quality history entry + matching ride's coach reflection, classifies the signal, applies the transition, persists, and emits `progressionTierChanged` on tier changes. `deleteAllLocalData` wipes both the in-memory state and the UserDefaults key. `generateRecommendation` passes the state into `Inputs`. `QualitySubtype` is now `CaseIterable`. |
| `SmarterTraining/Analytics/AnalyticsEvent.swift` | New `progressionTierChanged = "progression_tier_changed"` event. Properties: `subtype`, `from_tier`, `to_tier`, `signal`. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | 31 new tests across `ProgressionStateTests`, `ProgressionAwareBuilderTests`, `ProgressionEngineIntegrationTests`, `ProgressionAnalyticsTests`. Existing `TimeShapingTests/longQualityHasLongerWarmup()` continues to pass (warmup pacing preserved at time >= 60). |

## C. New progression models

```swift
enum ProgressionTier: Int, Codable, Equatable, Comparable, CaseIterable {
    case starter = 0
    case progressing = 1
    case stable = 2
    case advanced = 3
}

struct SubtypeProgressionState: Codable, Equatable {
    var tier: ProgressionTier
    var consecutiveSuccesses: Int
    var consecutiveStruggles: Int
    var sessionsAtCurrentTier: Int
    var lastUpdatedAt: Date?
}

struct ProgressionState: Codable, Equatable {
    func state(for subtype: QualitySubtype) -> SubtypeProgressionState
    func tier(for subtype: QualitySubtype) -> ProgressionTier
    func applying(signal: ProgressionSignal, to subtype: QualitySubtype) -> ProgressionState
    var stableOrBetterSubtypeCount: Int
}

enum ProgressionSignal: Equatable {
    case confidentSuccess
    case mixed
    case struggle
}

enum ProgressionSignalClassifier {
    static func signal(feedback: WorkoutFeedback?, reflection: CoachReflection? = nil) -> ProgressionSignal?
}
```

**Transition rules:**

- 2 consecutive `confidentSuccess` → advance one tier (capped at `.advanced`).
- 2 consecutive `struggle` → regress one tier (capped at `.starter`).
- `mixed` → tier holds, counters drift toward neutral.
- After advancement or regression, the consecutive counter resets.

## D. Example progression paths per subtype

Each subtype has 4 tier templates. Short-time (< 30 min, < 35 min for ME) sessions skip the tier system and use a single trainer-friendly compact template.

**VO2 Max** (106–115% FTP)

| Tier | Main set | Notes |
|---|---|---|
| Starter | 4 x 2 min @ 108–115% / 2 min easy | Shorter reps to learn the system |
| Progressing | 5 x 3 min @ 106–112% / 3 min easy | Current standard |
| Stable | 6 x 3 min @ 106–112% / 3 min easy | Extra rep when handled consistently |
| Advanced | 6 x 3 min @ 110–115% / 2 min 30 sec easy | Tighter recoveries |

**Threshold** (95–100% FTP)

| Tier | Main set |
|---|---|
| Starter | 3 x 5 min |
| Progressing | 4 x 5 min |
| Stable | 3 x 10 min |
| Advanced | 2 x 15 min |

**Muscular Endurance** (88–95% FTP)

| Tier | Main set |
|---|---|
| Starter | 4 x 8 min |
| Progressing | 3 x 9 min |
| Stable | 3 x 12 min |
| Advanced | 2 x 20 min |

**Tempo** (80–87% FTP)

| Tier | Main set |
|---|---|
| Starter | 20 min continuous |
| Progressing | 25 min continuous |
| Stable | 2 x 15 min |
| Advanced | 2 x 20 min |

**Over/Unders** (alternating 105% / 88% FTP)

| Tier | Main set |
|---|---|
| Starter | 3 x 6 min, 4 min easy |
| Progressing | 4 x 6 min, 4 min easy |
| Stable | 4 x 6 min, 3 min easy (tighter recoveries) |
| Advanced | 5 x 6 min, 4 min easy |

If the available time can't fit the requested tier (e.g. 40 min asking for advanced ME), `resolveTier(...)` falls back one tier at a time until it finds one that fits. Floor is starter.

## E. Example recommendation changes — before vs after

| Scenario | Before Phase 1 | After Phase 1 |
|---|---|---|
| Athlete who has done 2 consistently-good VO2 sessions, 60 min today, peak readiness | `5 x 3 min @ 106–112%` (every time) | `6 x 3 min @ 106–112%` — *stable* tier earned |
| Athlete with 4 strong threshold sessions, 60 min, peak readiness | `4 x 6 min @ 95–100%` (every time) | `2 x 15 min @ 95–100%` — *advanced* sustained intervals |
| Brand-new athlete, first ME workout, 45 min | `3 x 9 min @ 88–95%` | `4 x 8 min @ 88–95%` — *starter* shorter blocks |
| Athlete who reported "too much" on 2 consecutive VO2 sessions | Same VO2 workout next time | Drops VO2 back one tier — fewer reps, easier landing |
| Athlete with stable VO2 AND stable threshold, marginal-but-positive check-in | Endurance day | More likely to land quality — willingness +1 from progression demonstrably earned |
| Athlete at advanced ME, only 40 min available | Same workout regardless | Falls back to progressing ME (3 x 9 min) — time governs the ceiling |

## F. Example explainability copy

Added to the quality reason at progressing/stable/advanced tiers (silent at starter so we don't volunteer "you're a beginner"):

| Tier | Appended line |
|---|---|
| Starter | *(silent)* |
| Progressing | "Recent VO2 work has been landing — keeping the structure consistent today." |
| Stable | "You've handled recent threshold work consistently, so this is a good chance to extend the work." |
| Advanced | "Muscular Endurance is one of your stronger systems right now — today reflects that." |

Tone hedges and never overstates: "landing", "handled consistently", "extend the work". No tier numbers, no levels, no "adaptive score increased" copy.

## G. Persistence architecture

```
ProgressionState (single Codable value)
        |
        v
JSONEncoder/Decoder
        |
        v
UserDefaults["progressionState"]
```

Load happens once in `AppState.init`. Save happens on every `submitFeedback` that produces a quality signal. Encoding is dictionary-shaped (`{ "vo2": SubtypeProgressionState, ... }`) so the on-disk form stays readable and unknown subtypes decode cleanly to `.starter` defaults.

Update timing:
1. User submits workout feedback via `AppState.submitFeedback(_:)`.
2. `applyProgressionUpdate(for:)` looks up the latest history entry — only acts when the entry is a quality session with a recorded subtype.
3. Looks up the matching `CompletedWorkout` by date to read `coachReflection` if present.
4. `ProgressionSignalClassifier.signal(...)` maps feedback + reflection to a `ProgressionSignal`.
5. `progressionState.applying(signal:to:)` produces the new state, transition rules applied internally.
6. Persists to UserDefaults. Emits `progressionTierChanged` only when the tier actually changed.

Account deletion: `deleteAllLocalData()` resets `progressionState = .empty` in memory and removes the UserDefaults key. Confirmed by the existing `AccountDeletionTests` suite, which still passes.

## H. Future extension opportunities for Phase 2

- **Telemetry-driven signal enrichment.** Heart-rate drift, power fade, and cadence stability are sitting in `CompletedWorkout.samples` today, unused. Phase 2 could feed those into `ProgressionSignalClassifier` — e.g., HR drift < 4 bpm late in a threshold set is a confident-success signal even without explicit feedback.
- **Sessions-at-tier maturity bonus.** `sessionsAtCurrentTier` is tracked but not yet consulted. Phase 2 could require N sessions before allowing an advancement — protecting against single-good-day jumps.
- **Targeted progression nudge.** When an athlete is one success away from advancement, the engine could mildly prefer their about-to-progress subtype. Stub: `state.consecutiveSuccesses == 1 && tier < .advanced` is the trigger.
- **Backend forwarding.** `AICoachService` and `PostWorkoutReflectionService` can include progression state in their payloads. The AI coach can then say "given that you're stable in threshold but starter in over/unders, today's mix should..." with real context.
- **UI surfacing (subtle).** Today there's no UI for progression state — it's felt, not managed. Phase 2 could add an opt-in subtle indicator on workout history rows (a tiny chevron or "extended" tag) for advanced-tier sessions. Stay nowhere near a level dashboard.
- **Regression with notice.** Currently regression is silent. Phase 2 could surface a brief reason ("Recent sessions have been hard — pulling back a touch") in the workout card the first time a regression takes effect.
- **Per-subtype "ready to progress" flag.** Once `sessionsAtCurrentTier` + `consecutiveSuccesses` cross a threshold, expose a readiness flag the engine can weight when picking subtype — the athlete who is one push away from advancing in VO2 should be slightly more likely to *get* VO2 next quality day.

## Test results

- **31/31** new Phase 1 tests pass: transitions, classifier, persistence, all 5 subtype builder tier mappings, time-fallback, willingness boost, reason copy, analytics raw value.
- **All 91** prior tests still pass (subtype audit, selection, builder, notes, reflection, likely tomorrow, time shaping, analytics uniqueness, account deletion, onboarding bias).

## Constraint compliance

- **No telemetry intelligence:** `ProgressionSignalClassifier` reads only `WorkoutFeedback` and optional `CoachReflection.response`. No HR/power/cadence inference. Hooks are in place for Phase 2.
- **No fatigue models:** Tier transitions are pure counter logic. No physiological assumptions.
- **No AI planning agents:** Engine remains deterministic. Inputs in, recommendation out.
- **No analytics screens:** Zero new UI surfaces. State is "felt, not managed."
- **No periodization systems:** No week structure, no taper, no peaking. One decision per session.
- **No opaque scoring:** Tiers are an enum with four values; the entire state is human-readable.
