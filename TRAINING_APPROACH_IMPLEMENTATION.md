# Training Approach — Implementation Summary

## A. Implementation summary

A three-option coaching-philosophy preference (sustainable / balanced / ambitious) that biases how the existing adaptive engine balances progression pressure, recovery, and consistency. Balanced is the canonical default and the baseline against which the other two are tuned. All three approaches respect every readiness, load, and recovery protection — the approach setting changes thresholds and tendencies, not safeguards. The UI lives under Settings (not onboarding, by design), with explicit framing that no option is "better" — they reflect different goals, schedules, and recovery realities.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/TrainingApproach.swift` | **New.** Enum with title, short description, coach explanation, and four behavioral knobs (`advancementThreshold`, `regressionThreshold`, `preservesSuccessOnMixed`, `willingnessBias`). |
| `SmarterTraining/ProgressionState.swift` | `applying(signal:to:approach:at:)` now reads the approach to drive advancement/regression thresholds and mixed-signal handling. Existing call sites (no approach passed) default to `.balanced` — backward-compatible. |
| `SmarterTraining/RecommendationEngine.swift` | `Inputs.approach` field. `qualityWillingness(for:progression:approach:)` adds the approach's static bias (-1 / 0 / +1, capped within the -2…+2 band). Both willingness call sites in `chooseWorkoutType` and `chooseQualitySubtype` pass approach. `progressionFraming(...)` now generates approach-flavored copy at the progressing / stable tiers. |
| `SmarterTraining/Models.swift` | `AppState.trainingApproach` property persisted under `UserDefaults["trainingApproach"]`. `setTrainingApproach(_:)` setter that emits the new analytics event and triggers sync. `applyProgressionUpdate(...)` passes the current approach into `ProgressionState.applying(...)`. `generateRecommendation(...)` includes approach in `Inputs`. `deleteAllLocalData()` resets to `.default` and removes the UserDefaults key. |
| `SmarterTraining/SettingsView.swift` | New `coachSettingsSection` between `accountSection` and `devicesSection`. Inline contextual framing copy ("Training Approach shapes how your coach balances..."), three selectable rows with title + short description, and a footer note ("You can change this anytime..."). |
| `SmarterTraining/Analytics/AnalyticsEvent.swift` | New `trainingApproachChanged = "training_approach_changed"` event. Tracks `training_approach` and `previous_approach`. Also added `training_approach` property to the existing `progressionTierChanged` event payload. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | 19 new `TrainingApproachTests` covering defaults, all three thresholds, the mixed-forgiveness rule, willingness bias (lowered for sustainable, raised for ambitious, cap), readiness protections still applying under ambitious, approach-flavored reason copy, Codable, analytics raw value. |

## C. TrainingApproach model

```swift
enum TrainingApproach: String, Codable, Equatable, CaseIterable {
    case sustainable
    case balanced
    case ambitious

    static let `default`: TrainingApproach = .balanced

    var title: String                  // "Sustainable" / "Balanced" / "Ambitious"
    var shortDescription: String       // one-sentence
    var coachExplanation: String       // longer settings copy

    // Behavioral knobs
    var advancementThreshold: Int      // 3 / 2 / 2
    var regressionThreshold: Int       // 2 / 2 / 3
    var preservesSuccessOnMixed: Bool  // false / false / true
    var willingnessBias: Int           // -1 / 0 / +1
}
```

Persisted in `UserDefaults["trainingApproach"]` as the rawValue string. Wiped on account deletion.

## D. Behavioral differences by approach

| Knob | Sustainable | Balanced (default) | Ambitious |
|---|---|---|---|
| Successes to advance a tier | **3** | 2 | 2 |
| Struggles to regress a tier | 2 | 2 | **3** |
| Mixed signal breaks success streak | yes | yes | **no** |
| Static willingness bias | **-1** | 0 | **+1** |
| Reason copy flavor (stable tier) | "keeping progression steady and sustainable" | "good chance to extend the work" | "good opportunity to push progression slightly" |

What this means in practice:
- **Sustainable** athletes accumulate progression more slowly (needs three strong sessions to bump a tier), regress at the same pace as balanced, and the engine is less eager to prescribe quality. The intent is consistency and recovery realism.
- **Balanced** matches the engine's previous behavior exactly. No surprises for existing users.
- **Ambitious** advances at the same pace as balanced (because two successes is already a low bar) but holds confidence through one ambiguous session and gives one extra strike before regressing. Willingness for quality is bumped, but every readiness, load, and recovery protection still fires.

## E. Example recommendation differences

| Scenario | Sustainable | Balanced | Ambitious |
|---|---|---|---|
| 2 strong VO2 sessions, fresh today | Stays at starter tier — needs one more strong session | Advances to progressing (5 x 3) | Advances to progressing (5 x 3) |
| 1 strong + 1 "hard but completed" VO2 | Stays at starter; mixed broke the streak | Stays at starter; mixed broke the streak | **Advances** — mixed didn't break the streak |
| 2 struggles after a progressing session | Regresses to starter | Regresses to starter | **Holds** at progressing — one more strike allowed |
| Marginal quality day (Good / Normal / Medium) with -1 willingness profile | Endurance instead | Endurance | More likely to prescribe a tempo/threshold quality |
| Bad feel, fresh legs, peak motivation | Recovery (protection) | Recovery (protection) | **Recovery (protection — even ambitious)** |
| Dead legs | Recovery (protection) | Recovery (protection) | **Recovery (protection — even ambitious)** |
| Heavy week load (`hasHighRecentLoad`) | Load-downshift → ME/Tempo/Threshold | Same | Same |

The protections row matters: **Ambitious never overrides safety**. The hard-recovery overrides, load down-shift, and returning-after-break guards all run before the approach has any effect on subtype eligibility.

## F. Example rationale differences

Same athlete with a stable-tier threshold session:

> **Sustainable:** "Your training consistency can handle it, and fresh legs make today right for quality work. Threshold work builds the ceiling: sustained efforts right at your limit. You've handled recent threshold work consistently — keeping progression steady and sustainable."

> **Balanced:** "Your training consistency can handle it, and fresh legs make today right for quality work. Threshold work builds the ceiling: sustained efforts right at your limit. You've handled recent threshold work consistently, so this is a good chance to extend the work."

> **Ambitious:** "Your training consistency can handle it, and fresh legs make today right for quality work. Threshold work builds the ceiling: sustained efforts right at your limit. You've been handling recent threshold work consistently, so this is a good opportunity to push progression slightly."

No "beast mode" copy. No macho framing. Hedged with "steady", "extend", "slightly".

## G. Analytics additions

**New event:** `training_approach_changed`

Properties:
- `training_approach`: `"sustainable" | "balanced" | "ambitious"`
- `previous_approach`: previous value

**Enriched event:** `progression_tier_changed`

Now also carries `training_approach` so future observability can attribute tier transitions to the athlete's current approach.

These provide the substrate for future coaching telemetry like:
- Average sessions-per-tier-advancement by approach
- Regression rate by approach (sustainable should be highest)
- Quality prescription rate by approach (ambitious should be highest, all else equal)

## H. Future extension opportunities

- **Per-subtype approach.** An athlete might want sustainable on VO2 (knees) but ambitious on tempo. Phase 2 could allow per-subtype overrides. The `applying(signal:to:approach:)` API is already shaped for this.
- **Approach-aware load down-shift.** Sustainable might engage the load-downshift gate slightly earlier (lower load threshold). Ambitious might require a slightly higher load before withholding VO2. Single-line tweak inside `chooseQualitySubtype`.
- **Approach-aware coach reflection prompts.** Sustainable athletes might never see the "more repeatable than recent VO2?" prompt (too aspirational); ambitious athletes might get it more often. A small switch on `CoachReflectionGenerator.generate(...)` based on approach.
- **Approach guardrails for ambitious.** If an ambitious athlete chains multiple struggles or a `.tooMuch` feedback, the engine could transiently downgrade willingness for the next 7 days — protecting the athlete from their own setting without changing the setting itself.
- **Onboarding hint** (much later). Once we have weeks of athlete data, we could suggest a switch ("Looking at your last month, you might find Sustainable a better fit"). Suggestion only, never automatic.
- **Backend payload.** `AICoachService` and `PostWorkoutReflectionService` can include `training_approach` so the AI coach matches the requested coaching tone in any generated copy.

## Test results

- **19/19** new `TrainingApproachTests` pass: defaults, metadata, all three advancement/regression thresholds, mixed-forgiveness, willingness bias direction and cap, readiness protections still firing under ambitious (bad feel / dead legs / getting sick), approach-flavored reason copy contains "steady"/"push" markers, Codable, analytics raw value.
- **40/40** prior tests pass across `ProgressionStateTests`, `ProgressionEngineIntegrationTests`, `QualitySubtypeAuditTests`, `AccountDeletionTests`, `AnalyticsEventTests` — confirming the default-balanced behavior matches pre-change behavior exactly and account deletion wipes the new setting.

## Constraint compliance

- **No difficulty mode framing:** UI copy emphasizes "coaching philosophy", "recovery realities", "no approach is better".
- **Not in onboarding:** Setting lives in Settings → Coach Settings only. New users start on `.balanced` and can change after experiencing the coach.
- **No sliders:** Three discrete options as labeled rows with descriptions.
- **No athlete scores or hidden metrics exposed:** The four internal knobs are private to the enum.
- **No separate engines:** All three approaches share the same code paths. Only thresholds and one bias integer differ.
- **Ambitious cannot override safety:** Tests verify bad feel / dead legs / getting sick still trigger recovery under ambitious. Load-downshift, returning-after-break, and intent-active-day protections all run before approach can influence subtype eligibility.
