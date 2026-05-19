# What matters today — Implementation Summary

## A. Implementation summary

A compact card directly below "Why This" on TodayView that explains *how* to execute today's workout — pacing, what success feels like, what NOT to optimize for. One paragraph, ~10-second read, deterministic templates layered with tier / approach / coach-note context. Never AI-chatty, never motivational fluff, never bulleted.

Where "Why This" tells the athlete *why the workout exists*, "What matters today" tells them *what successful execution feels like*.

## B. Files changed

| File | Change |
|---|---|
| `SmarterTraining/ExecutionGuidance.swift` | **New.** `ExecutionGuidanceBuilder` (deterministic generator: base template per type/subtype + 3 layered modifiers) and `ExecutionGuidanceCard` SwiftUI view. Hard length cap at 400 chars with sentence-boundary clamp. |
| `SmarterTraining/TodayView.swift` | Inserts `ExecutionGuidanceCard` between `coachExplanationCard` and `WorkoutBreakdownCard` when there's no completed ride today. New computed property `executionGuidance` pulls progression state, training approach, and coach notes from `appState` and feeds them to the builder. |
| `SmarterTrainingTests/SmarterTrainingTests.swift` | 24 new `ExecutionGuidanceTests` covering coverage, subtype-specific language, tier modifiers, approach modifiers, coach-note influence, recovery/endurance ignoring quality modifiers, length cap, and a comprehensive no-macho-language sweep. |

## C. Guidance generation architecture

```
WorkoutRecommendation -> ProgressionState -> TrainingApproach -> CoachNotes
                                |
                                v
                ExecutionGuidanceBuilder.build(...)
                                |
                                v
        baseTemplate(type / subtype)  [always]
                                |
                                v
              + tierAddition(tier, subtype)        [quality only]
              + approachAddition(approach, subtype) [quality only]
              + coachNoteAddition(notes, subtype)   [quality + matching subtype]
                                |
                                v
                  clamp(joined, maxLength: 400)
                                |
                                v
                       Single paragraph
```

**Layer 1 — Base template (always):** seven baselines, one per workout type and quality subtype. Drawn directly from the spec examples ("These efforts should feel hard quickly, but still repeatable…").

**Layer 2 — Tier addition (quality only):**
- Starter → "Lean conservative early — getting a feel for the work matters more than hitting every target."
- Progressing → *(no addition — current canonical baseline)*
- Stable → "Smoothness under accumulating fatigue is the win today."
- Advanced → "Composure under sustained load is the goal. Form is the win, not the watts."

Tier addition is silent at progressing so the athlete doesn't feel like they "leveled up" — the language just evolves.

**Layer 3 — Training-approach addition (quality only):**
- Sustainable → "Leave a little in reserve."
- Balanced → *(no addition)*
- Ambitious → "If the work feels repeatable, this is a fair day to lean into it — composed, not reckless."

**Layer 4 — Coach-note addition (quality + matching subtype only):**
- `kneeSensitivity` + (ME/threshold/over-unders) → "Keep the cadence comfortable — no grinding."
- `vo2MentallyDifficult` + VO2 → "Discomfort is the point. Just stay repeatable."
- `legsFatigueFirst` + (ME/threshold) → "Pace the legs early — they're the limiter today."

Recovery and endurance only ever show the base template — they intentionally ignore tier, approach, and note modifiers (verified by tests).

## D. Example outputs for every subtype

**Recovery:**
> The goal today is circulation and recovery, not fitness gain. Keep the effort easy enough that your legs gradually feel better, not heavier.

**Endurance:**
> Keep the effort conversational and relaxed. Finishing fresher than you expected is often a sign you paced this correctly.

**VO2 (progressing tier, balanced approach, no notes):**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session.

**Threshold:**
> Stay controlled early so the final interval remains smooth. Today is about repeatable sustained work, not survival.

**Muscular Endurance:**
> The goal today is sustained pressure, not explosive power. Your legs should gradually fatigue while breathing stays relatively controlled.

**Tempo:**
> This should feel steady and sustainable throughout. If you're gasping early, the effort is probably too high.

**Over/Unders:**
> This isn't about chasing the highest possible heart rate. Focus on smooth control as fatigue accumulates — each set should feel a little more taxing without falling apart.

## E. Progression-tier examples

Same VO2 workout, different tiers (everything else neutral):

**Starter:**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session. Lean conservative early — getting a feel for the work matters more than hitting every target.

**Progressing:**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session.

**Stable:**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session. Smoothness under accumulating fatigue is the win today.

**Advanced:**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session. Composure under sustained load is the goal. Form is the win, not the watts.

## F. Training-approach examples

Same threshold workout, different approaches (progressing tier, no notes):

**Sustainable:**
> Stay controlled early so the final interval remains smooth. Today is about repeatable sustained work, not survival. Leave a little in reserve.

**Balanced:**
> Stay controlled early so the final interval remains smooth. Today is about repeatable sustained work, not survival.

**Ambitious:**
> Stay controlled early so the final interval remains smooth. Today is about repeatable sustained work, not survival. If the work feels repeatable, this is a fair day to lean into it — composed, not reckless.

Note that ambitious uses "lean into" and "composed, not reckless" — never "push", "crush", "destroy", "beast", "empty the tank", or "punish". The no-macho language sweep test confirms this across every (type × subtype × tier × approach) combination.

## G. Coach-note influence examples

**Muscular Endurance with `legsFatigueFirst`:**
> The goal today is sustained pressure, not explosive power. Your legs should gradually fatigue while breathing stays relatively controlled. Pace the legs early — they're the limiter today.

**Muscular Endurance with `kneeSensitivity`:**
> The goal today is sustained pressure, not explosive power. Your legs should gradually fatigue while breathing stays relatively controlled. Keep the cadence comfortable — no grinding.

**VO2 with `vo2MentallyDifficult`:**
> These efforts should feel hard quickly, but still repeatable. Don't sprint the first interval — the goal is consistent quality across the full session. Discomfort is the point. Just stay repeatable.

**Tempo with `kneeSensitivity`:** *(unchanged — knee note doesn't fire on tempo since it's not a low-cadence subtype)*

## H. Future extension opportunities

- **Mid-workout micro-guidance.** The active ride view (`RideSessionView`) could surface a one-line variant of this guidance during the workout's primary set ("smooth, repeatable through this set"). Same generator, separate compact variant.
- **Post-workout reflection alignment.** If today's guidance was "stay controlled early so the final interval remains smooth" and the athlete picks "Harder" on the reflection prompt, the post-workout validation could pull the original guidance language ("the early control did its job — the final interval is where it shows"). Builds a closed loop between intent and reflection.
- **Profile-availability shading.** Short-time sessions could pick a tighter variant of the base template ("Keep the work short and clean — duration is the constraint today, not effort"). Easy to add — `recommendation.steps` already encodes duration intent.
- **Backend / AI co-pilot path.** Once a backend reflection service is live, it can override the deterministic template with a richer line, but with the same length cap and tone constraints. The deterministic path stays as a guaranteed fallback.
- **Approach-aware coach reflection prompt selection.** Sustainable athletes might never be asked "did this feel more repeatable?" if the guidance was already framed around reserve. Possible Phase-2 link between `ExecutionGuidance` and `CoachReflectionGenerator`.

## Test results

- **24/24** new `ExecutionGuidanceTests` pass.
- **All prior tests still pass** — no regressions. The new card sits between two existing cards in TodayView; the existing UI tests don't depend on its absence.

## Constraint compliance

- **One paragraph only**, no bullets, hard 400-char cap with sentence-boundary clamp.
- **No physiology jargon**, no "tips and tricks" lists.
- **No macho language anywhere** — verified by a sweep test that runs every (type × subtype × tier × approach) combination against a blacklist (`crush`, `destroy`, `beast`, `empty the tank`, `punish`, `hardcore`).
- **Tiers never exposed** to the user as numbers or labels — the language evolves with tier but doesn't announce it.
- **No AI / chat** — pure deterministic templates with `String` concatenation.
- **Recovery and endurance ignore quality modifiers** — the cards stay calm and short for those days.
- **Single takeaway per workout** — the layered structure adds at most one short clause per layer, so the athlete reads one core idea + a few qualifiers, never a wall of advice.
